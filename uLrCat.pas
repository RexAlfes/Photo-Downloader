unit uLrCat;

{$mode objfpc}{$H+}

{ Photo information for Lightroom preview files (.lrprev), read from the Lightroom catalog.

  A .lrprev file holds no file name, date or camera, only an id. Lightroom keeps its previews in
  the folder "<catalog> Previews.lrdata" next to the catalog "<catalog>.lrcat". The preview id
  leads to the photo in two steps: previews.db in the .lrdata folder (table ImageCacheEntry: preview
  uuid -> imageId), then the catalog (table Adobe_images, id_local = imageId) with the file name,
  capture time, camera model, serial number and ISO.

  Both files are SQLite databases. They are read with the SQLite library of the system, loaded only
  when a .lrprev file is scanned: sqlite3.dll (next to the program) or winsqlite3.dll (part of
  Windows 10 and 11) on Windows, libsqlite3 on Linux. Without the library, or without a catalog,
  .lrprev files are handled as before. The databases are opened read-only and never changed.

  Every catalog that is needed is read once per scan into memory and closed again. }

interface

uses
  Classes, SysUtils;

type
  { What the catalog knows about the photo of one preview }
  TLrCatInfo = record
    OrigName: string;  // file name of the photo in the catalog, with extension
    CaptureTime: TDateTime;  // capture time
    HasDate: Boolean;  // True when the catalog holds a usable capture time
    Camera, Serial: string;  // camera model and serial number
    ISO: Integer;  // ISO speed (0 = unknown)
  end;

{ Looks up the photo of a .lrprev file in its Lightroom catalog; False when there is no catalog,
  no SQLite library or no entry for the preview. }
function LrCatLookup(const LrPrevFile: string; out Info: TLrCatInfo): Boolean;
{ Forgets the catalogs read so far (call at the start of each scan, so changes in Lightroom are seen). }
procedure LrCatReset;
{ Text about the SQLite library for the Status dialog. }
function LrCatLibraryText: string;
{ Messages about catalogs that could not be read since the last LrCatReset (for the log), one per line. }
function LrCatMessages: string;

implementation

uses
  sqlite3dyn, ctypes;

type
  { One catalog read into memory }
  TLrCatalog = class
    Previews: TStringList;  // preview uuid -> photo (object: TLrPhoto); sorted
    Photos: TList;  // every TLrPhoto, freed with the catalog
    constructor Create;
    destructor Destroy; override;
  end;

  { One photo of a catalog }
  TLrPhoto = class
    Info: TLrCatInfo;  // what the catalog knows about it
  end;

var
  LibState: Integer = 0;  // SQLite library: 0 = not tried yet, 1 = loaded, -1 = not found
  LibName: string = '';  // name of the library that was loaded
  Catalogs: TStringList = nil;  // .lrdata folder -> TLrCatalog (nil object when it could not be read)
  Messages: string = '';  // problems since the last LrCatReset

constructor TLrCatalog.Create;
begin
  inherited Create;
  Previews := TStringList.Create;  // preview uuids
  Previews.CaseSensitive := False;  // uuids may differ in letter case
  Photos := TList.Create;  // the photos
end;

destructor TLrCatalog.Destroy;
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to Photos.Count - 1 do TLrPhoto(Photos[I]).Free;  // free every photo
  Photos.Free;  // free the list
  Previews.Free;  // free the uuids
  inherited Destroy;
end;

{ Loads the SQLite library once; False when the system has none. }
function LoadLib: Boolean;
const
  {$IFDEF WINDOWS}
  Names: array[0..1] of string = ('sqlite3.dll', 'winsqlite3.dll');  // own copy first, then the one of Windows
  {$ELSE}
  Names: array[0..1] of string = ('libsqlite3.so.0', 'libsqlite3.so');  // the usual Linux names
  {$ENDIF}
var
  I: Integer;  // I: loop counter
begin
  if LibState = 0 then  // not tried yet
  begin
    LibState := -1;  // assume none is found
    for I := Low(Names) to High(Names) do  // try every name
      try
        if TryInitializeSqlite(UnicodeString(Names[I])) >= 0 then  // loaded
        begin
          LibState := 1;  // remember it
          LibName := Names[I];  // and its name
          Break;
        end;
      except
        // a broken library counts as missing
      end;
  end;
  Result := LibState = 1;  // True when a library is loaded
end;

{ Turns a file path into an SQLite URI that opens the file read-only without locking it. }
function ReadOnlyUri(const Path: string): string;
var
  P: string;  // P: the path with forward slashes
  I: Integer;  // I: character position
begin
  P := StringReplace(Path, '\', '/', [rfReplaceAll]);  // URIs use forward slashes
  Result := '';
  for I := 1 to Length(P) do  // escape everything but plain characters (UTF-8 bytes too)
    if P[I] in ['A'..'Z', 'a'..'z', '0'..'9', '/', ':', '-', '_', '.', '~'] then
      Result := Result + P[I]
    else
      Result := Result + '%' + IntToHex(Ord(P[I]), 2);
  if (Result <> '') and (Result[1] <> '/') then Result := '/' + Result;  // Windows: /C:/...
  // immutable: Lightroom may have the catalog open; nothing is written, so no lock is needed
  Result := 'file://' + Result + '?mode=ro&immutable=1';
end;

{ Opens a database read-only; nil (and a message) when that fails. }
function OpenDb(const Path: string): psqlite3;
begin
  Result := nil;  // no database yet
  if sqlite3_open_v2(PAnsiChar(ReadOnlyUri(Path)), @Result, SQLITE_OPEN_READONLY or SQLITE_OPEN_URI, nil) <> SQLITE_OK then
  begin
    if Result <> nil then
    begin
      Messages := Messages + Path + ': ' + string(sqlite3_errmsg(Result)) + LineEnding;  // the reason
      sqlite3_close(Result);  // close what was opened
    end
    else
      Messages := Messages + Path + ': could not be opened' + LineEnding;  // no reason available
    Result := nil;
  end;
end;

{ Returns column Col of the current row as text ('' for NULL). }
function ColText(St: psqlite3_stmt; Col: Integer): string;
var
  P: PAnsiChar;  // P: the text in the library's memory
begin
  P := PAnsiChar(sqlite3_column_text(St, Col));  // UTF-8 text
  if P = nil then Result := '' else Result := string(P);  // copy it
end;

{ Reads a Lightroom time text (yyyy-mm-ddThh:nn[:ss[.fff]]); False for no or a placeholder date. }
function ParseLrTime(const S: string; out DT: TDateTime): Boolean;
var
  Y, M, D, H, N, Sec: Integer;  // Y, M, D: date; H, N, Sec: time
  Tm: TDateTime;  // Tm: time part
begin
  Result := False;  // assume no usable date
  DT := 0;  // no date yet
  if (Length(S) < 10) or (S[5] <> '-') or (S[8] <> '-') then Exit;  // not a date
  Y := StrToIntDef(Copy(S, 1, 4), 0);  // year
  M := StrToIntDef(Copy(S, 6, 2), 0);  // month
  D := StrToIntDef(Copy(S, 9, 2), 0);  // day
  // Lightroom writes 1904-01-01 or 1970-01-01 for photos without a date
  if Y <= 1970 then Exit;  // placeholder date
  if not TryEncodeDate(Y, M, D, DT) then Exit;  // invalid date
  H := StrToIntDef(Copy(S, 12, 2), 0);  // hour (0 when missing)
  N := StrToIntDef(Copy(S, 15, 2), 0);  // minute
  Sec := StrToIntDef(Copy(S, 18, 2), 0);  // second
  if TryEncodeTime(H, N, Sec, 0, Tm) then DT := DT + Tm;  // add the time
  Result := True;  // a usable date
end;

{ Reads the catalog that belongs to the .lrdata folder LrData; nil when it cannot be read. }
function ReadCatalog(const LrData: string): TLrCatalog;
const
  PhotoSql =  // every photo with its file name and camera data
    'select i.id_local, f.baseName, f.extension, i.captureTime, cm.value, sn.value, m.isoSpeedRating ' +
    'from Adobe_images i ' +
    'left join AgLibraryFile f on f.id_local = i.rootFile ' +
    'left join AgHarvestedExifMetadata m on m.image = i.id_local ' +
    'left join AgInternedExifCameraModel cm on cm.id_local = m.cameraModelRef ' +
    'left join AgInternedExifCameraSN sn on sn.id_local = m.cameraSNRef';
  PreviewSql = 'select uuid, imageId from ImageCacheEntry';  // preview uuid -> photo id
var
  Name, CatFile: string;  // Name: name of the .lrdata folder; CatFile: the catalog file
  Db: psqlite3;  // Db: the open database
  St: psqlite3_stmt;  // St: the running query
  Ids: TStringList;  // Ids: photo id (10 digits) -> TLrPhoto; sorted
  Ph: TLrPhoto;  // Ph: one photo
  Ext: string;  // Ext: file extension of the photo
  I: Integer;  // I: position in Ids
begin
  Result := nil;  // nothing read yet
  // "<catalog> Previews.lrdata" belongs to "<catalog>.lrcat" in the same folder
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(LrData));  // folder name
  CatFile := ExtractFilePath(ExcludeTrailingPathDelimiter(LrData)) +
    Copy(Name, 1, Length(Name) - Length(' Previews.lrdata')) + '.lrcat';  // the catalog
  if not FileExists(CatFile) then
  begin
    Messages := Messages + CatFile + ': catalog not found' + LineEnding;  // the reason
    Exit;
  end;
  if not FileExists(IncludeTrailingPathDelimiter(LrData) + 'previews.db') then
  begin
    Messages := Messages + LrData + ': no previews.db (Lightroom versions before Classic are not supported)' + LineEnding;
    Exit;
  end;
  Ids := TStringList.Create;  // photo ids
  Ids.Sorted := True;  // fast lookups
  Result := TLrCatalog.Create;  // the catalog
  try
    // step 1: every photo of the catalog
    Db := OpenDb(CatFile);  // open the catalog
    if Db = nil then begin FreeAndNil(Result); Exit; end;  // cannot be read
    try
      if sqlite3_prepare_v2(Db, PAnsiChar(PhotoSql), -1, @St, nil) <> SQLITE_OK then
      begin
        Messages := Messages + CatFile + ': ' + string(sqlite3_errmsg(Db)) + LineEnding;  // not a catalog this code knows
        FreeAndNil(Result);
        Exit;
      end;
      try
        while sqlite3_step(St) = SQLITE_ROW do  // every photo
        begin
          Ph := TLrPhoto.Create;  // new photo
          Result.Photos.Add(Ph);  // owned by the catalog
          Ext := ColText(St, 2);  // file extension
          Ph.Info.OrigName := ColText(St, 1);  // base name
          if Ext <> '' then Ph.Info.OrigName := Ph.Info.OrigName + '.' + Ext;  // with its extension
          Ph.Info.HasDate := ParseLrTime(ColText(St, 3), Ph.Info.CaptureTime);  // capture time
          Ph.Info.Camera := ColText(St, 4);  // camera model
          Ph.Info.Serial := ColText(St, 5);  // serial number
          Ph.Info.ISO := Round(sqlite3_column_double(St, 6));  // ISO speed (0 when NULL)
          Ids.AddObject(Format('%.10d', [sqlite3_column_int64(St, 0)]), Ph);  // by its id
        end;
      finally
        sqlite3_finalize(St);  // end the query
      end;
    finally
      sqlite3_close(Db);  // close the catalog
    end;
    // step 2: the preview uuids of the .lrdata folder
    Db := OpenDb(IncludeTrailingPathDelimiter(LrData) + 'previews.db');  // open the preview list
    if Db = nil then begin FreeAndNil(Result); Exit; end;  // cannot be read
    try
      if sqlite3_prepare_v2(Db, PAnsiChar(PreviewSql), -1, @St, nil) <> SQLITE_OK then
      begin
        Messages := Messages + LrData + ': ' + string(sqlite3_errmsg(Db)) + LineEnding;  // not a preview list this code knows
        FreeAndNil(Result);
        Exit;
      end;
      try
        while sqlite3_step(St) = SQLITE_ROW do  // every preview
          if Ids.Find(Format('%.10d', [Round(sqlite3_column_double(St, 1))]), I) then  // its photo is in the catalog
            Result.Previews.AddObject(ColText(St, 0), Ids.Objects[I]);  // uuid -> photo
      finally
        sqlite3_finalize(St);  // end the query
      end;
    finally
      sqlite3_close(Db);  // close the preview list
    end;
    Result.Previews.Sorted := True;  // sort once for fast lookups
  finally
    Ids.Free;  // the photos stay in Result.Photos
  end;
end;

{ Returns the .lrdata folder that holds a .lrprev file (it lies a few folders down), or ''. }
function LrDataFolderOf(const LrPrevFile: string): string;
var
  Dir, Up: string;  // Dir: folder being checked; Up: its parent
  Depth: Integer;  // Depth: folders checked
begin
  Result := '';  // not found yet
  Dir := ExtractFileDir(LrPrevFile);  // folder of the file
  for Depth := 1 to 5 do  // .lrdata\0\0005\file.lrprev: two folders up, a little room for other layouts
  begin
    if SameText(Copy(Dir, Length(Dir) - Length(' Previews.lrdata') + 1, MaxInt), ' Previews.lrdata') then
      Exit(Dir);  // found
    Up := ExtractFileDir(Dir);  // parent folder
    if (Up = '') or (Up = Dir) then Exit;  // reached the root
    Dir := Up;  // go up
  end;
end;

{ Returns the preview uuid of a .lrprev file: the file name starts with it (uuid-digest.lrprev). }
function UuidOf(const LrPrevFile: string): string;
var
  N: string;  // N: file name
  I: Integer;  // I: character position
begin
  Result := '';  // not found yet
  N := ExtractFileName(LrPrevFile);  // file name
  if Length(N) < 36 then Exit;  // too short for a uuid
  for I := 1 to 36 do  // 8-4-4-4-12 hex digits
    if I in [9, 14, 19, 24] then
    begin
      if N[I] <> '-' then Exit;  // a dash is missing
    end
    else if not (N[I] in ['0'..'9', 'A'..'F', 'a'..'f']) then Exit;  // not a hex digit
  Result := Copy(N, 1, 36);  // the uuid
end;

function LrCatLookup(const LrPrevFile: string; out Info: TLrCatInfo): Boolean;
var
  LrData, Uuid: string;  // LrData: the .lrdata folder; Uuid: id of the preview
  Cat: TLrCatalog;  // Cat: its catalog
  I: Integer;  // I: position in a list
begin
  Result := False;  // assume nothing is found
  Info.OrigName := ''; Info.CaptureTime := 0; Info.HasDate := False;  // clear the fields
  Info.Camera := ''; Info.Serial := ''; Info.ISO := 0;
  Uuid := UuidOf(LrPrevFile);  // id of the preview
  LrData := LrDataFolderOf(LrPrevFile);  // folder of the previews
  if (Uuid = '') or (LrData = '') then Exit;  // not a preview inside a Lightroom catalog folder
  if not LoadLib then  // no SQLite library on this system
  begin
    if Messages = '' then  // say it once
      Messages := 'SQLite library not found: .lrprev files cannot be matched to their Lightroom catalog' + LineEnding;
    Exit;
  end;
  if Catalogs = nil then
  begin
    Catalogs := TStringList.Create;  // catalogs read in this scan
    Catalogs.OwnsObjects := True;  // freed with the list
    Catalogs.Sorted := True;  // fast lookups
  end;
  if not Catalogs.Find(LrData, I) then  // first preview of this catalog
  begin
    try
      Cat := ReadCatalog(LrData);  // read it (nil when it cannot be read)
    except
      on E: Exception do
      begin
        Messages := Messages + LrData + ': ' + E.Message + LineEnding;  // the reason
        Cat := nil;  // treat it as unreadable
      end;
    end;
    I := Catalogs.AddObject(LrData, Cat);  // remember it, also when it failed
  end;
  Cat := TLrCatalog(Catalogs.Objects[I]);  // the catalog
  if (Cat = nil) or not Cat.Previews.Find(Uuid, I) then Exit;  // unreadable, or the preview is not listed
  Info := TLrPhoto(Cat.Previews.Objects[I]).Info;  // the photo
  Result := True;  // found
end;

procedure LrCatReset;
begin
  FreeAndNil(Catalogs);  // forget the catalogs
  Messages := '';  // and the messages
end;

function LrCatLibraryText: string;
begin
  case LibState of
    1: Result := LibName;  // the library in use
    -1: Result := 'not found (Lightroom catalogs cannot be read)';  // none on this system
  else
    Result := 'not needed yet (loaded when a .lrprev file is scanned)';  // not tried
  end;
end;

function LrCatMessages: string;
begin
  Result := Messages;  // problems since the last reset
end;

finalization
  FreeAndNil(Catalogs);  // free the catalogs
  if LibState = 1 then ReleaseSqlite;  // unload the library

end.
