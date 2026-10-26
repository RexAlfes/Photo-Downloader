unit uItems;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Math, StrUtils, DateUtils, Graphics, FPReadJPEG,
  LazFileUtils, md5, uSettings, uExif, uHeic, uRotate, uTiffRead;

type
  TItemStatus = (isNew, isDownloaded, isNameClash, isDuplicate);

  TScanProgress = procedure(Count: Integer) of object;

  { TImageItem - one image found on the source }
  TImageItem = class
  public
    Index: Integer;                 // 1-based number shown in the grid
    FullPath, FileName, SourceDir: string;
    Size: Int64;
    FileTime, CaptureTime: TDateTime;
    Camera, Make, Serial, Owner: string;
    ISO: Integer;
    Orientation: Integer;           // EXIF orientation 1..8 (0 = unknown)
    IsReadOnly: Boolean;
    Status: TItemStatus;
    Selected: Boolean;
    DestPath: string;
    NoDelete: Boolean;              // a backup copy failed: keep the original on the card
    BackupPath: string;
    ClashInfo: string;              // why the item is flagged as a name clash
    DateKey: string;                // 'yyyy/mm/dd'
    Thumb: TBitmap;
    ThumbTried: Boolean;
    destructor Destroy; override;
    function StatusText: string;
    function IsProblem: Boolean;
    function IsJpeg: Boolean;
    function SizeText: string;
  end;

function ItemAt(L: TObjectList; I: Integer): TImageItem;
var
  { Set to True (e.g. from the progress callback) to stop a running scan }
  ScanAbort: Boolean = False;

procedure ScanFolder(const Root: string; S: TAppSettings; Items: TObjectList;
  Progress: TScanProgress);
procedure EvaluateItems(Items: TObjectList; S: TAppSettings);
const
  BlankJobMark = '{no job}';        // stored in DateJobCodes for a date whose job code is blank

function JobCodeFor(S: TAppSettings; Item: TImageItem): string;
function ComputeDest(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer): string;
function ExampleDest(S: TAppSettings; const DirMask, NameMask, Job: string): string;
function UniqueName(const Dest: string): string;
procedure EnsureThumb(Item: TImageItem; Box: Integer);
{ Frees an item's thumbnail again (it is rendered anew, or read from the disk cache, when needed) }
procedure ReleaseThumb(Item: TImageItem);
{ True for file types that are slow to decode (HEIC, AVIF, TIFF, DNG) }
function ThumbIsHeavy(const FileName: string): Boolean;
{ Turns the bitmap upright for an EXIF orientation of 2..8; Bmp may be replaced. }
procedure OrientBitmap(var Bmp: TBitmap; Orient: Integer);
{ Builds a bitmap (at most MaxSide pixels on the long side) from the uncompressed
  image data of a TIFF/DNG file. False if the file has no such image. }
function LoadTiffBitmap(const FileName: string; MaxSide: Integer; Bmp: TBitmap): Boolean;
{ True if the plain TIFF/DNG image is larger than a JPEG preview of W x H pixels. }
function TiffRgbIsLarger(const FileName: string; W, H: Integer): Boolean;
procedure LogThumb(const Msg: string);
function CopyFileStream(const Src, Dst: string): Boolean;
type
  TCopyResult = (crOk, crFailed, crVerifyFailed, crCanceled);
var
  { Called every few hundred KB while copying or verifying (keeps the window alive) }
  CopyPump: TThreadMethod = nil;
  { Set to True from CopyPump to stop the running copy }
  CopyAbort: Boolean = False;
{ Copies Src to Dst. The MD5 of the source is computed while it is read. With Verify the copy is
  read back and compared. On any failure the incomplete or wrong copy is deleted. }
function CopyFileChecked(const Src, Dst: string; Verify: Boolean; out Hash: string;
  out Err: string): TCopyResult;
{ MD5 of a file as 32 hex characters; '' if it cannot be read }
function HashOfFile(const FileName: string): string;
{ Folder for the backup copy of an item (own folder template, same patterns), with the file
  name of the main copy }
function BackupDestFor(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer;
  const MainDest: string): string;
function FormatSize(Size: Int64): string;

implementation


const
  AttrHidden = $02;   // portable copies of faHidden / faSysFile
  AttrSystem = $04;
  ImageExts = ';.jpg;.jpeg;.jpe;.png;.gif;.tif;.tiff;.bmp;.nef;.nrw;.cr2;.cr3;.crw;' +
              '.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;.heic;.heif;.avif;' +
              '.mp4;.mov;.lrv;.mp3;.thm;';
  TiffExts = ';.tif;.tiff;.dng;';
  RawExts = ';.nef;.nrw;.cr2;.cr3;.crw;.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;';
  ExifExts = ';.jpg;.jpeg;.jpe;.tif;.tiff;.nef;.nrw;.cr2;.cr3;.heic;.heif;.avif;.crw;.arw;.sr2;.dng;.pef;.srw;';

var
  { Items that currently hold a thumbnail, oldest first. Every thumbnail is a Windows bitmap
    handle and a process may only own about 10,000 of them, so only the newest ones are kept. }
  ThumbLru: TList = nil;

const
  ThumbKeepMax = 1200;

{ TImageItem }

destructor TImageItem.Destroy;
begin
  if Assigned(ThumbLru) then ThumbLru.Remove(Self);
  Thumb.Free;
  inherited Destroy;
end;

function TImageItem.StatusText: string;
begin
  case Status of
    isNew: Result := 'New file';
    isDownloaded: Result := 'Already downloaded';
    isNameClash:
      begin
        Result := 'Name clash';
        if ClashInfo <> '' then Result := Result + ' (' + ClashInfo + ')';
      end;
    isDuplicate: Result := 'Duplicate file';
  else
    Result := '';
  end;
end;

function TImageItem.IsProblem: Boolean;
begin
  Result := Status = isNameClash;
end;

function TImageItem.IsJpeg: Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E = '.jpg') or (E = '.jpeg') or (E = '.jpe');
end;

function FormatSize(Size: Int64): string;
begin
  if Size >= 1048576 then
    Result := FormatFloat('0.0', Size / 1048576) + 'MB'
  else
    Result := IntToStr((Size + 512) div 1024) + 'KB';
end;

function TImageItem.SizeText: string;
begin
  Result := FormatSize(Size);
end;

function ItemAt(L: TObjectList; I: Integer): TImageItem;
begin
  Result := TImageItem(L[I]);
end;

{ ---- scanning ---- }

function IsImageFile(const Name: string): Boolean;
begin
  Result := Pos(';' + LowerCase(ExtractFileExt(Name)) + ';', ImageExts) > 0;
end;

function CompareItems(A, B: Pointer): Integer;
var
  X, Y: TImageItem;
begin
  X := TImageItem(A);
  Y := TImageItem(B);
  Result := CompareValue(X.CaptureTime, Y.CaptureTime);
  if Result = 0 then
    Result := CompareText(X.FileName, Y.FileName);
end;

var
  LastProgTick: QWord = 0;

procedure ScanDir(const Dir: string; Items: TObjectList; var Cnt: Integer;
  Progress: TScanProgress);
var
  SR: TSearchRec;
  Full: string;
  It: TImageItem;
  Info: TExifInfo;
begin
  if FindFirstUTF8(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) <> 0 then Exit;
  try
    repeat
      if ScanAbort then Break;
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then Continue;
      Full := IncludeTrailingPathDelimiter(Dir) + SR.Name;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        // skip hidden/system folders such as $RECYCLE.BIN and System Volume Information
        if (SR.Attr and (AttrHidden or AttrSystem)) = 0 then
          ScanDir(Full, Items, Cnt, Progress);
      end
      else if IsImageFile(SR.Name) then
      begin
        It := TImageItem.Create;
        It.FullPath := Full;
        It.FileName := SR.Name;
        It.SourceDir := Dir;
        It.Size := SR.Size;
        try
          It.FileTime := FileDateToDateTime(SR.Time);
        except
          It.FileTime := Now;
        end;
        It.IsReadOnly := (SR.Attr and faReadOnly) <> 0;
        It.CaptureTime := It.FileTime;
        if Pos(';' + LowerCase(ExtractFileExt(SR.Name)) + ';', ExifExts) > 0 then
          if ReadExifFromFile(Full, Info) then
          begin
            if Info.HasDate then It.CaptureTime := Info.DateTaken;
            It.Camera := Info.Model;
            It.Make := Info.Make;
            It.Serial := Info.Serial;
            It.ISO := Info.ISO;
            It.Orientation := Info.Orientation;
            if Info.Owner <> '' then It.Owner := Info.Owner else It.Owner := Info.Artist;
          end;
        Items.Add(It);
        Inc(Cnt);
        if Assigned(Progress) and (GetTickCount64 - LastProgTick >= 80) then
        begin
          LastProgTick := GetTickCount64;
          Progress(Cnt);
        end;
      end;
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
end;

procedure ScanFolder(const Root: string; S: TAppSettings; Items: TObjectList;
  Progress: TScanProgress);
var
  Cnt, I: Integer;
  Dcim: string;
begin
  Items.Clear;
  Cnt := 0;
  ScanAbort := False;
  Dcim := IncludeTrailingPathDelimiter(Root) + 'DCIM';
  if (not S.ScanWholeDisk) and DirectoryExistsUTF8(Dcim) then
    ScanDir(Dcim, Items, Cnt, Progress)
  else
    ScanDir(Root, Items, Cnt, Progress);
  Items.Sort(@CompareItems);
  for I := 0 to Items.Count - 1 do
    ItemAt(Items, I).Index := I + 1;
end;

{ ---- tokens ---- }

function SanitizePart(const V: string): string;
var
  I: Integer;
begin
  Result := V;
  for I := 1 to Length(Result) do
    if WinSafeNamesOn then
    begin
      if Result[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then
        Result[I] := '_';
    end
    else if Result[I] in ['/', #0] then      // Linux only forbids the path separator
      Result[I] := '_';
end;

function NormMask(const M: string): string;
begin
  Result := StringReplace(M, '\', PathDelim, [rfReplaceAll]);
  if PathDelim <> '/' then Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
end;

{ Token r: the longest run of digits in the original name (the last one on a tie),
  or the whole original name when it has no digits, so unnumbered files stay unique. }
function ImageNumberOf(const Base: string): string;
var
  I, J: Integer;
  Run: string;
begin
  Result := '';
  I := 1;
  while I <= Length(Base) do
  begin
    if Base[I] in ['0'..'9'] then
    begin
      J := I;
      while (J <= Length(Base)) and (Base[J] in ['0'..'9']) do Inc(J);
      Run := Copy(Base, I, J - I);
      if Length(Run) >= Length(Result) then Result := Run;
      I := J;
    end
    else
      Inc(I);
  end;
  if Result = '' then Result := Base;
end;

function MapValue(S: TAppSettings; const Camera: string; Which: Integer): string;
var
  I: Integer;
  N, A, B, Raw: string;
begin
  Raw := '{T1}';
  if S.Mappings.Count > 0 then
  begin
    MapSplit(S.Mappings[0], N, A, B);
    if Which = 8 then Raw := A else Raw := B;
  end;
  for I := 1 to S.Mappings.Count - 1 do
  begin
    MapSplit(S.Mappings[I], N, A, B);
    if SameText(N, Camera) then
    begin
      if Which = 8 then Raw := A else Raw := B;
      Break;
    end;
  end;
  Result := StringReplace(Raw, '{T1}', Camera, [rfReplaceAll, rfIgnoreCase]);
end;

function TokenValue(const Tok: string; Item: TImageItem; const Job: string;
  SeqDown, SeqSess: Integer; S: TAppSettings; out Known: Boolean): string;
var
  DT: TDateTime;
  H, W, I: Integer;
  Base: string;
begin
  Known := True;
  DT := Item.CaptureTime;
  Base := ChangeFileExt(Item.FileName, '');
  case Tok of
    'd': Result := FormatDateTime('yyyymmdd', DT);
    'y': Result := FormatDateTime('yy', DT);
    'Y': Result := FormatDateTime('yyyy', DT);
    'm': Result := FormatDateTime('mm', DT);
    'b': Result := FormatDateTime('mmm', DT);
    'B': Result := FormatDateTime('mmmm', DT);
    'D': Result := FormatDateTime('dd', DT);
    'a': Result := FormatDateTime('ddd', DT);
    'A': Result := FormatDateTime('dddd', DT);
    'W': Result := Format('%.2d', [WeekOf(DT)]);
    't': Result := FormatDateTime('hhnnss', DT);
    'H': Result := FormatDateTime('hh', DT);
    'I':
      begin
        H := HourOf(DT) mod 12;
        if H = 0 then H := 12;
        Result := Format('%.2d', [H]);
      end;
    'M': Result := FormatDateTime('nn', DT);
    'S': Result := FormatDateTime('ss', DT);
    'q': Result := ExtractFileName(ExcludeTrailingPathDelimiter(Item.SourceDir));
    'r': Result := ImageNumberOf(Base);
    'o': Result := Base;
    'f':
      begin
        I := 1;
        while (I <= Length(Base)) and not (Base[I] in ['0'..'9']) do Inc(I);
        Result := Copy(Base, 1, I - 1);
      end;
    'O': Result := Item.Owner;
    'i': Result := IntToStr(Item.ISO);
    'c': Result := Item.Serial;
    'T', 'T1': Result := Item.Camera;
    'T8': Result := MapValue(S, Item.Camera, 8);
    'T9': Result := MapValue(S, Item.Camera, 9);
    'J': Result := Job;
    'seq#': Result := IntToStr(SeqDown);
  else
    if (Length(Tok) = 2) and (Tok[1] = 'n') and (Tok[2] in ['1'..'9']) then
    begin
      W := Ord(Tok[2]) - Ord('0');
      Result := IntToStr(SeqSess);
      while Length(Result) < W do Result := '0' + Result;
    end
    else
    begin
      Known := False;
      Result := '';
    end;
  end;
end;

function ExpandTokens(const Mask: string; Item: TImageItem; const Job: string;
  SeqDown, SeqSess: Integer; S: TAppSettings): string;
var
  I, J: Integer;
  Tok, V: string;
  Known: Boolean;
begin
  Result := '';
  I := 1;
  while I <= Length(Mask) do
  begin
    if Mask[I] = '{' then
    begin
      J := PosEx('}', Mask, I + 1);
      if J > 0 then
      begin
        Tok := Copy(Mask, I + 1, J - I - 1);
        V := TokenValue(Tok, Item, Job, SeqDown, SeqSess, S, Known);
        if Known then
          Result := Result + SanitizePart(V)
        else
          Result := Result + Copy(Mask, I, J - I + 1);   // e.g. the literal {Job Name}
        I := J + 1;
        Continue;
      end;
    end;
    Result := Result + Mask[I];
    Inc(I);
  end;
end;

function JobCodeFor(S: TAppSettings; Item: TImageItem): string;
begin
  Result := S.DateJobCodes.Values[Item.DateKey];
  if Result = BlankJobMark then
    Result := ''                    // this date was given a blank job code on purpose
  else if Result = '' then
    Result := S.JobCode;
end;

{ A blank job code leaves separators behind ("2026-10-25-"); remove them. }
function TidyBlankJob(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to 3 do
  begin
    Result := StringReplace(Result, '--', '-', [rfReplaceAll]);
    Result := StringReplace(Result, '__', '_', [rfReplaceAll]);
    Result := StringReplace(Result, ' -', '-', [rfReplaceAll]);
    Result := StringReplace(Result, '- ', '-', [rfReplaceAll]);
    Result := StringReplace(Result, '-' + PathDelim, PathDelim, [rfReplaceAll]);
    Result := StringReplace(Result, '_' + PathDelim, PathDelim, [rfReplaceAll]);
    Result := StringReplace(Result, PathDelim + '-', PathDelim, [rfReplaceAll]);
    Result := StringReplace(Result, PathDelim + '_', PathDelim, [rfReplaceAll]);
  end;
  while (Result <> '') and (Result[Length(Result)] in ['-', '_', ' ']) do
    Delete(Result, Length(Result), 1);
  while (Result <> '') and (Result[1] in ['-', '_', ' ']) do
    Delete(Result, 1, 1);
end;

function BuildDest(S: TAppSettings; Item: TImageItem; const DirMask, NameMask, Job: string;
  SeqDown, SeqSess: Integer): string;
var
  Dir, Nm, Ext: string;
begin
  Dir := ExpandTokens(NormMask(DirMask), Item, Job, SeqDown, SeqSess, S);
  Nm := ExpandTokens(NormMask(NameMask), Item, Job, SeqDown, SeqSess, S);
  if Job = '' then
  begin
    Dir := TidyBlankJob(Dir);
    Nm := TidyBlankJob(Nm);
  end;
  Ext := ExtractFileExt(Item.FileName);
  if S.RenameJpe and SameText(Ext, '.jpe') then Ext := '.jpg';
  if S.LowerExt then Ext := LowerCase(Ext);
  if S.LowerName then Nm := LowerCase(Nm);
  if Dir <> '' then Dir := IncludeTrailingPathDelimiter(Dir);
  Result := Dir + Nm + Ext;
end;

function ComputeDest(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer): string;
begin
  Result := BuildDest(S, Item, S.DownloadDir, S.FileNameMask, JobCodeFor(S, Item),
    SeqDown, SeqSess);
end;

function ExampleDest(S: TAppSettings; const DirMask, NameMask, Job: string): string;
var
  It: TImageItem;
begin
  It := TImageItem.Create;
  try
    It.FileName := '_DSC0123.JPG';
    It.SourceDir := 'DCIM' + PathDelim + '100NCD700';
    It.CaptureTime := Now;
    It.Camera := 'NIKON D700';
    It.Serial := '1234567';
    It.Owner := 'Owner';
    It.ISO := 200;
    Result := BuildDest(S, It, DirMask, NameMask, Job, S.SeqNext, 1);
  finally
    It.Free;
  end;
end;

function UniqueName(const Dest: string): string;
var
  N: Integer;
  Base, Ext: string;
begin
  Ext := ExtractFileExt(Dest);
  Base := Copy(Dest, 1, Length(Dest) - Length(Ext));
  N := 1;
  repeat
    Result := Base + '-' + IntToStr(N) + Ext;
    Inc(N);
  until not FileExistsUTF8(Result);
end;

{ ---- status ---- }

procedure EvaluateItems(Items: TObjectList; S: TAppSettings);
var
  I, P, J: Integer;
  It: TImageItem;
  Dups, Groups, Firsts: TStringList;
  Key: string;
begin
  Dups := TStringList.Create;
  Groups := TStringList.Create;
  Firsts := TStringList.Create;
  try
    Dups.Sorted := True;
    Dups.CaseSensitive := False;
    Groups.Sorted := True;
    Groups.CaseSensitive := False;
    Firsts.Sorted := True;
    Firsts.CaseSensitive := False;

    // pass 1: destination names, duplicates and per-destination counts
    for I := 0 to Items.Count - 1 do
    begin
      It := ItemAt(Items, I);
      It.DateKey := FormatDateTime('yyyy"/"mm"/"dd', It.CaptureTime);
      It.DestPath := ComputeDest(S, It, S.SeqNext + I, I + 1);
      It.ClashInfo := '';
      // the same photo found twice (copies in other folders, renamed copies):
      // identical size, capture time and camera
      Key := IntToStr(It.Size) + '|' + FloatToStr(It.CaptureTime) + '|' + It.Camera;
      if Dups.IndexOf(Key) >= 0 then
        It.Status := isDuplicate
      else
      begin
        Dups.Add(Key);
        It.Status := isNew;
        P := Groups.IndexOf(It.DestPath);
        if P < 0 then
          begin
            Groups.AddObject(It.DestPath, TObject(PtrInt(1)));
            Firsts.AddObject(It.DestPath, TObject(PtrInt(It.Index)));
          end
        else
          Groups.Objects[P] := TObject(PtrInt(PtrInt(Groups.Objects[P]) + 1));
      end;
    end;

    // pass 2: compare with what is already on disk
    for I := 0 to Items.Count - 1 do
    begin
      It := ItemAt(Items, I);
      if It.Status = isDuplicate then Continue;
      if FileExistsUTF8(It.DestPath) then
      begin
        if S.IgnoreSizeCheck or (FileSizeUtf8(It.DestPath) = It.Size) then
          It.Status := isDownloaded
        else
          begin
            It.Status := isNameClash;
            It.ClashInfo := 'a different file with this name already exists';
          end;
      end
      else
      begin
        P := Groups.IndexOf(It.DestPath);
        if (P >= 0) and (PtrInt(Groups.Objects[P]) > 1) then
        begin
          It.Status := isNameClash;
          J := PtrInt(Firsts.Objects[Firsts.IndexOf(It.DestPath)]);
          if J = It.Index then
            It.ClashInfo := 'same new name as other files'
          else if (J >= 1) and (J <= Items.Count) then
            It.ClashInfo := 'same new name (' + ExtractFileName(It.DestPath) + ') as #' + IntToStr(J) +
              ' ' + ItemAt(Items, J - 1).FullPath
          else
            It.ClashInfo := 'same new name as #' + IntToStr(J);
        end;
      end;
    end;
  finally
    Dups.Free;
    Groups.Free;
    Firsts.Free;
  end;
end;

{ ---- thumbnails ---- }

procedure OrientBitmap(var Bmp: TBitmap; Orient: Integer);
var
  Nb: TBitmap;
  X, Y, W, H, NW, NH, NX, NY: Integer;
begin
  if (Bmp = nil) or (Orient < 2) or (Orient > 8) then Exit;
  W := Bmp.Width;
  H := Bmp.Height;
  if (W <= 0) or (H <= 0) then Exit;
  OrientDims(Orient, W, H, NW, NH);
  Nb := TBitmap.Create;
  try
    Nb.SetSize(NW, NH);
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        OrientPoint(Orient, W, H, X, Y, NX, NY);
        Nb.Canvas.Pixels[NX, NY] := Bmp.Canvas.Pixels[X, Y];
      end;
  except
    Nb.Free;
    Exit;
  end;
  Bmp.Free;
  Bmp := Nb;
end;

{ appends a line to thumbnail.log in the settings folder (diagnostics for unreadable previews) }
procedure LogThumb(const Msg: string);
var
  FN, Line: string;
  Strm: TFileStream;
begin
  if not LogEnabled then Exit;
  try
    FN := ConfigDir + 'thumbnail.log';
    if FileExistsUTF8(FN) then
    begin
      if FileSizeUtf8(FN) > 200000 then Exit;
      Strm := TFileStream.Create(FN, fmOpenWrite or fmShareDenyNone);
      Strm.Position := Strm.Size;
    end
    else
      Strm := TFileStream.Create(FN, fmCreate);
    try
      Line := FormatDateTime('hh:nn:ss', Now) + ' ' + Msg + LineEnding;
      Strm.WriteBuffer(Line[1], Length(Line));
    finally
      Strm.Free;
    end;
  except
    // logging must never disturb the program
  end;
end;

type
  TBmpFileHdr = packed record
    bfType: Word;
    bfSize, bfReserved, bfOffBits: LongWord;
  end;
  TBmpInfoHdr = packed record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPels, biYPels: LongInt;
    biClrUsed, biClrImportant: LongWord;
  end;

function TiffRgbIsLarger(const FileName: string; W, H: Integer): Boolean;
var
  R: TTiffRgb;
begin
  Result := FindTiffRgb(FileName, R) and (Int64(R.W) * R.H > Int64(W) * H);
end;

function LoadTiffBitmap(const FileName: string; MaxSide: Integer; Bmp: TBitmap): Boolean;
var
  R: TTiffRgb;
  Strm: TFileStream;
  Ms: TMemoryStream;
  FH: TBmpFileHdr;
  IH: TBmpInfoHdr;
  Sc: Double;
  NW, NH, X, Y, SX, SY, Bps, Hi, P, LineLen: Integer;
  Row, Line: TBytes;
  G: Byte;
begin
  Result := False;
  Row := nil;
  Line := nil;
  if not FindTiffRgb(FileName, R) then Exit;
  Bps := R.Bits div 8;
  if Max(R.W, R.H) > MaxSide then Sc := MaxSide / Max(R.W, R.H) else Sc := 1;
  NW := Max(1, Round(R.W * Sc));
  NH := Max(1, Round(R.H * Sc));
  // index of the most significant byte of a sample
  if R.Big then Hi := 0 else Hi := Bps - 1;
  LineLen := ((NW * 3 + 3) div 4) * 4;
  SetLength(Line, LineLen);

  FH.bfType := $4D42;
  FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;
  FH.bfReserved := 0;
  FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
  IH.biSize := SizeOf(IH);
  IH.biWidth := NW;
  IH.biHeight := NH;                 // positive height: rows are stored bottom-up
  IH.biPlanes := 1;
  IH.biBitCount := 24;
  IH.biCompression := 0;
  IH.biSizeImage := LineLen * NH;
  IH.biXPels := 2835;
  IH.biYPels := 2835;
  IH.biClrUsed := 0;
  IH.biClrImportant := 0;

  Ms := TMemoryStream.Create;
  try
    try
      Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        Ms.WriteBuffer(FH, SizeOf(FH));
        Ms.WriteBuffer(IH, SizeOf(IH));
        for Y := NH - 1 downto 0 do
        begin
          SY := Y * R.H div NH;
          if not ReadTiffRgbRow(Strm, R, SY, Row) then Exit;
          FillChar(Line[0], LineLen, 0);
          for X := 0 to NW - 1 do
          begin
            SX := X * R.W div NW;
            P := SX * R.Spp * Bps + Hi;
            if R.Spp = 3 then
            begin
              Line[X * 3 + 2] := Row[P];              // red
              Line[X * 3 + 1] := Row[P + Bps];        // green
              Line[X * 3] := Row[P + 2 * Bps];        // blue
            end
            else
            begin
              G := Row[P];
              if R.Photo = 0 then G := 255 - G;       // WhiteIsZero
              Line[X * 3] := G;
              Line[X * 3 + 1] := G;
              Line[X * 3 + 2] := G;
            end;
          end;
          Ms.WriteBuffer(Line[0], LineLen);
        end;
      finally
        Strm.Free;
      end;
      Ms.Position := 0;
      Bmp.LoadFromStream(Ms);
      Result := (Bmp.Width > 0) and (Bmp.Height > 0);
    except
      Result := False;
    end;
  finally
    Ms.Free;
  end;
end;

function PickScale(W, H, Box: Integer): TJPEGScale;
var
  Ratio: Integer;
begin
  Ratio := Max(W, H) div Max(1, Box);
  if Ratio >= 8 then Result := jsEighth
  else if Ratio >= 4 then Result := jsQuarter
  else if Ratio >= 2 then Result := jsHalf
  else Result := jsFullSize;
end;

const
  { Change when the decoders change so that thumbnails kept from an older version are rebuilt }
  ThumbCacheVersion = '2';

function ThumbCacheName(Item: TImageItem; Box: Integer): string;
begin
  Result := CacheDir + 'thumbcache' + PathDelim + MD5Print(MD5String(
    ThumbCacheVersion + '|' + LowerCase(Item.FullPath) + '|' + IntToStr(Item.Size) + '|' +
    FloatToStr(Item.FileTime) + '|' + IntToStr(Box))) + '.jpg';
end;

function LoadCachedThumb(Item: TImageItem; Box: Integer): Boolean;
var
  FN: string;
  J: TJPEGImage;
  B: TBitmap;
begin
  Result := False;
  FN := ThumbCacheName(Item, Box);
  if not FileExistsUTF8(FN) then Exit;
  J := TJPEGImage.Create;
  try
    try
      J.LoadFromFile(FN);
      if J.Empty then Exit;
      B := TBitmap.Create;
      B.SetSize(J.Width, J.Height);
      B.Canvas.Draw(0, 0, J);
      Item.Thumb := B;
      Result := True;
    except
      Result := False;
    end;
  finally
    J.Free;
  end;
end;

procedure SaveCachedThumb(Item: TImageItem; Box: Integer);
var
  J: TJPEGImage;
begin
  try
    ForceDirectoriesUTF8(CacheDir + 'thumbcache');
    J := TJPEGImage.Create;
    try
      J.Assign(Item.Thumb);
      J.CompressionQuality := 88;
      J.SaveToFile(ThumbCacheName(Item, Box));
    finally
      J.Free;
    end;
  except
    // the cache is only a speed-up
  end;
end;

{ 1 = TIFF, 2 = JPEG, 0 = anything else, judged by the first bytes of the file }
function SniffFileKind(const FileName: string): Integer;
var
  F: TFileStream;
  B: array[0..3] of Byte;
begin
  Result := 0;
  {$PUSH}{$HINTS OFF}FillChar(B, SizeOf(B), 0);{$POP}
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      if F.Read(B[0], 4) < 4 then Exit;
    finally
      F.Free;
    end;
    if ((B[0] = $49) and (B[1] = $49) and (B[2] = $2A) and (B[3] = 0)) or
       ((B[0] = $4D) and (B[1] = $4D) and (B[2] = 0) and (B[3] = $2A)) then
      Result := 1
    else if (B[0] = $FF) and (B[1] = $D8) then
      Result := 2;
  except
    Result := 0;
  end;
end;

procedure EnsureThumbCore(Item: TImageItem; Box: Integer);
var
  Heavy: Boolean;
  Ext: string;
  Jpg: TJPEGImage;
  Pic: TPicture;
  Mem: TMemoryStream;
  G: TGraphic;
  W, H, NW, NH, Rank, Attempt: Integer;
  Deep: Boolean;
  Sc: Double;
  Bmp: TBitmap;
  TiffErr: string;
  Sniff: Integer;
begin
  W := 0;
  H := 0;
  Deep := True;
  TiffErr := '';
  if Item.ThumbTried then Exit;
  Item.ThumbTried := True;
  Ext := LowerCase(ExtractFileExt(Item.FileName));
  // slow-to-decode types are kept in a small on-disk cache
  Heavy := (Pos(';' + Ext + ';', HeicExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0);
  if Heavy and LoadCachedThumb(Item, Box) then Exit;
  Jpg := nil;
  Pic := nil;
  Mem := nil;
  G := nil;
  Bmp := nil;
  try
    try
      if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') then
      begin
        Jpg := TJPEGImage.Create;
        if ReadJpegDims(Item.FullPath, W, H) then
          Jpg.Scale := PickScale(W, H, Box)
        else
          Jpg.Scale := jsQuarter;
        Jpg.Performance := jpBestSpeed;
        Jpg.LoadFromFile(Item.FullPath);
        G := Jpg;
      end
      else if (Pos(';' + Ext + ';', RawExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0) then
      begin
        // RAW, TIFF and DNG: use an embedded JPEG preview when there is one. TIFF and
        // DNG files are not searched beyond the first 4 MB (they can be very large).
        Deep := Pos(';' + Ext + ';', TiffExts) = 0;
        Mem := TMemoryStream.Create;
        for Rank := 0 to 2 do
        begin
          Mem.Clear;
          if not ExtractEmbeddedJpeg(Item.FullPath, Rank, Deep, Mem, W, H) then Break;
          // the plain image in the file is bigger than this preview: build the thumbnail from it
          if (not Deep) and TiffRgbIsLarger(Item.FullPath, W, H) then Break;
          // attempt 0: reduced-size fast decode; attempt 1: decoder defaults
          for Attempt := 0 to 1 do
          begin
            Mem.Position := 0;
            Jpg := TJPEGImage.Create;
            try
              if Attempt = 0 then
              begin
                Jpg.Scale := PickScale(W, H, Box);
                Jpg.Performance := jpBestSpeed;
              end;
              Jpg.LoadFromStream(Mem);
              G := Jpg;
              Break;
            except
              on E: Exception do
              begin
                LogThumb(Item.FileName + ': preview #' + IntToStr(Rank) + ' (' + IntToStr(W) +
                  'x' + IntToStr(H) + ') attempt ' + IntToStr(Attempt) + ' failed: ' +
                  E.ClassName + ' ' + E.Message);
                FreeAndNil(Jpg);
              end;
            end;
          end;
          if G <> nil then Break;
        end;
        if (G = nil) and (not Deep) then
        begin
          // TIFF / DNG without a usable JPEG: build the thumbnail from the image data itself
          Bmp := TBitmap.Create;
          if LoadTiffBitmap(Item.FullPath, Box, Bmp) then
          begin
            if Pos(';' + Ext + ';', HeicExts) = 0 then OrientBitmap(Bmp, Item.Orientation);
            Item.Thumb := Bmp;
            Bmp := nil;
            if Heavy then SaveCachedThumb(Item, Box);
            Exit;
          end;
          FreeAndNil(Bmp);
          // compressed or 1-bit TIFF (scans, LZW, fax ...): the general TIFF reader
          Bmp := TBitmap.Create;
          TiffErr := '';
          if LoadTiffThumb(Item.FullPath, Box, Bmp, TiffErr) then
          begin
            if Pos(';' + Ext + ';', HeicExts) = 0 then OrientBitmap(Bmp, Item.Orientation);
            Item.Thumb := Bmp;
            Bmp := nil;
            if Heavy then SaveCachedThumb(Item, Box);
            Exit;
          end;
          FreeAndNil(Bmp);
        end;
        if G = nil then
          LogThumb(Item.FileName + ': no usable preview or thumbnail image found' +
            IfThen(TiffErr <> '', ' (' + TiffErr + ')', ''));
      end
      else if (Ext = '.png') or (Ext = '.bmp') or (Ext = '.gif') then
      begin
        Sniff := SniffFileKind(Item.FullPath);
        if Sniff = 1 then
        begin
          // a TIFF with a .png/.bmp name
          Bmp := TBitmap.Create;
          if LoadTiffThumb(Item.FullPath, Box, Bmp, TiffErr) then
          begin
            Item.Thumb := Bmp;
            Bmp := nil;
            Exit;
          end;
          FreeAndNil(Bmp);
          LogThumb(Item.FileName + ': this is a TIFF file with a wrong extension (' + TiffErr + ')');
        end
        else if Sniff = 2 then
        begin
          // a JPEG with a .png/.bmp name
          Jpg := TJPEGImage.Create;
          Jpg.LoadFromFile(Item.FullPath);
          G := Jpg;
        end
        else
        begin
          Pic := TPicture.Create;
          Pic.LoadFromFile(Item.FullPath);
          G := Pic.Graphic;
        end;
      end
      else if Pos(';' + Ext + ';', HeicExts) > 0 then
      begin
        // HEIC / HEIF / AVIF: bundled decoder (see uHeic); the placeholder stays if it cannot decode
        Pic := TPicture.Create;
        if LoadHeicPicture(Item.FullPath, Pic, Box * 2, True) then
          G := Pic.Graphic
        else if HeicEnabled then
          LogThumb(Item.FileName + ': HEIC/AVIF decode failed: ' + HeicLastError)
        else
          LogThumb(Item.FileName + ': HEIC preview is not compiled in');
      end;
      if (G = nil) or G.Empty then Exit;
      W := G.Width;
      H := G.Height;
      if (W <= 0) or (H <= 0) then Exit;
      Sc := Box / Max(W, H);
      if Sc > 1 then Sc := 1;
      NW := Max(1, Round(W * Sc));
      NH := Max(1, Round(H * Sc));
      Bmp := TBitmap.Create;
      Bmp.SetSize(NW, NH);
      Bmp.Canvas.StretchDraw(Rect(0, 0, NW, NH), G);
      // HEIC decoders normally apply the file's own rotation; HeicExtraOrientation checks that
      if Pos(';' + Ext + ';', HeicExts) = 0 then
        OrientBitmap(Bmp, Item.Orientation)
      else
        OrientBitmap(Bmp, HeicExtraOrientation(Item.FullPath, W, H, Item.Orientation));
      Item.Thumb := Bmp;
      Bmp := nil;
      if Heavy then SaveCachedThumb(Item, Box);
    except
      on E: Exception do
        LogThumb(Item.FileName + ': ' + E.ClassName + ' ' + E.Message);
    end;
  finally
    Bmp.Free;
    Jpg.Free;
    Pic.Free;
    Mem.Free;
  end;
end;

{ ---- file copy ---- }

function ThumbIsHeavy(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Pos(';' + Ext + ';', HeicExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0);
end;

procedure ReleaseThumb(Item: TImageItem);
begin
  if ThumbLru <> nil then ThumbLru.Remove(Item);
  FreeAndNil(Item.Thumb);
  Item.ThumbTried := False;
end;

procedure EnsureThumb(Item: TImageItem; Box: Integer);
var
  Old: TImageItem;
begin
  if Item.ThumbTried then Exit;
  EnsureThumbCore(Item, Box);
  if Item.Thumb = nil then Exit;
  if ThumbLru = nil then ThumbLru := TList.Create;
  ThumbLru.Add(Item);
  while ThumbLru.Count > ThumbKeepMax do
  begin
    Old := TImageItem(ThumbLru[0]);
    ReleaseThumb(Old);
  end;
end;

function CopyFileStream(const Src, Dst: string): Boolean;
const
  BufSize = 262144;
var
  FI, FO: TFileStream;
  Buf: Pointer;
  N: LongInt;
begin
  Result := False;
  GetMem(Buf, BufSize);
  try
    try
      FI := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        FO := TFileStream.Create(Dst, fmCreate);
        try
          repeat
            N := FI.Read(Buf^, BufSize);
            if N > 0 then FO.WriteBuffer(Buf^, N);
          until N <= 0;
        finally
          FO.Free;
        end;
      finally
        FI.Free;
      end;
      Result := FileSizeUtf8(Dst) = FileSizeUtf8(Src);
    except
      Result := False;
    end;
  finally
    FreeMem(Buf);
  end;
  if not Result then
    DeleteFileUTF8(Dst);
end;

function HashOfFile(const FileName: string): string;
const
  BufSize = 262144;
var
  F: TFileStream;
  Buf: Pointer;
  N: LongInt;
  Ctx: TMD5Context;
  Dig: TMD5Digest;
begin
  Result := '';
  GetMem(Buf, BufSize);
  try
    try
      F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        MD5Init(Ctx);
        repeat
          N := F.Read(Buf^, BufSize);
          if N > 0 then MD5Update(Ctx, Buf^, N);
          if Assigned(CopyPump) then CopyPump;
          if CopyAbort then Exit;
        until N <= 0;
        MD5Final(Ctx, Dig);
        Result := MD5Print(Dig);
      finally
        F.Free;
      end;
    except
      Result := '';
    end;
  finally
    FreeMem(Buf);
  end;
end;

function CopyFileChecked(const Src, Dst: string; Verify: Boolean; out Hash: string;
  out Err: string): TCopyResult;
const
  BufSize = 262144;
var
  FI, FO: TFileStream;
  Buf: Pointer;
  N: LongInt;
  Ctx: TMD5Context;
  Dig: TMD5Digest;
  Back: string;
begin
  Result := crFailed;
  Hash := '';
  Err := '';
  GetMem(Buf, BufSize);
  try
    try
      FI := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        FO := TFileStream.Create(Dst, fmCreate);
        try
          MD5Init(Ctx);
          repeat
            N := FI.Read(Buf^, BufSize);
            if N > 0 then
            begin
              MD5Update(Ctx, Buf^, N);
              FO.WriteBuffer(Buf^, N);
            end;
            if Assigned(CopyPump) then CopyPump;
            if CopyAbort then
            begin
              Result := crCanceled;
              Break;
            end;
          until N <= 0;
          MD5Final(Ctx, Dig);
          Hash := MD5Print(Dig);
        finally
          FO.Free;
        end;
      finally
        FI.Free;
      end;
      if Result = crCanceled then
        Err := 'canceled'
      else if FileSizeUtf8(Dst) <> FileSizeUtf8(Src) then
        Err := 'the copy has a different size than the original'
      else if Verify then
      begin
        Back := HashOfFile(Dst);
        if CopyAbort then
          Result := crCanceled
        else if Back = '' then
        begin
          Result := crVerifyFailed;
          Err := 'the copy could not be read back';
        end
        else if Back <> Hash then
        begin
          Result := crVerifyFailed;
          Err := 'checksum of the copy (' + Back + ') differs from the original (' + Hash + ')';
        end
        else
          Result := crOk;
      end
      else
        Result := crOk;
    except
      on E: Exception do
      begin
        Result := crFailed;
        Err := E.Message;
      end;
    end;
  finally
    FreeMem(Buf);
  end;
  if Result <> crOk then
    DeleteFileUTF8(Dst);
end;

function BackupDestFor(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer;
  const MainDest: string): string;
var
  P: string;
begin
  P := BuildDest(S, Item, S.BackupDir, S.FileNameMask, JobCodeFor(S, Item), SeqDown, SeqSess);
  Result := ExtractFilePath(P) + ExtractFileName(MainDest);
end;

finalization
  FreeAndNil(ThumbLru);

end.
