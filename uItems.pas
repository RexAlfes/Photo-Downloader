unit uItems;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Math, StrUtils, DateUtils, Graphics, FPReadJPEG,
  LazFileUtils, md5, uSettings, uExif, uHeic, uRotate, uTiffRead, uPngFix, uWebP, uVideoThumb, uLrPrev, uLrCat;

type
  TItemStatus = (isNew, isDownloaded, isNameClash, isDuplicate);  // state of an image compared with earlier downloads

  TScanProgress = procedure(Count: Integer) of object;  // callback that reports the number of files found

  { TImageItem - one image found on the source }
  TImageItem = class
  public
    Index: Integer;                 // 1-based number shown in the grid
    FullPath, FileName, SourceDir: string;  // FullPath: complete path; FileName: name only; SourceDir: folder it was found in
    Size: Int64;  // file size in bytes
    FileTime, CaptureTime: TDateTime;  // FileTime: modification time; CaptureTime: time the picture was taken
    Camera, Make, Serial, Owner: string;  // camera model, camera maker, camera serial number, owner
    ISO: Integer;  // ISO speed
    Orientation: Integer;           // EXIF orientation 1..8 (0 = unknown)
    IsReadOnly: Boolean;  // True when the file is read-only
    Status: TItemStatus;  // download state
    Selected: Boolean;  // True when selected in the grid
    DestPath: string;  // planned destination path
    NoDelete: Boolean;              // a backup copy failed: keep the original on the card
    BackupPath: string;  // path of the backup copy
    ClashInfo: string;              // why the item is flagged as a name clash
    DateKey: string;                // 'yyyy/mm/dd'
    Thumb: TBitmap;  // thumbnail picture
    ThumbTried: Boolean;  // True once a thumbnail was tried
    Duration: Double;               // length of a video in seconds (0 = unknown or not a video)
    CatalogName: string;            // .lrprev: file name of the photo in the Lightroom catalog ('' = unknown)
    destructor Destroy; override;  // frees the thumbnail
    function StatusText: string;  // text for the status column
    function IsProblem: Boolean;  // True when the item has a problem
    function IsJpeg: Boolean;  // True for JPEG files
    function IsVideo: Boolean;  // True for MP4, MOV and LRV files
    function IsAudio: Boolean;  // True for MP3 files
    function DurationText: string;  // video length as h:mm:ss or m:ss ('' when unknown)
    function SizeText: string;  // size as text
  end;

function ItemAt(L: TObjectList; I: Integer): TImageItem;  // Returns item I of the list as an image item.
var
  { Set to True (e.g. from the progress callback) to stop a running scan }
  ScanAbort: Boolean = False;  // scan abort flag
  { Folder the scan is reading now (for the progress display) }
  ScanCurrentDir: string = '';

procedure ScanFolder(const Root: string; S: TAppSettings; Items: TObjectList;  // Scans a folder (DCIM when present) for images and fills Items.
  Progress: TScanProgress);
procedure EvaluateItems(Items: TObjectList; S: TAppSettings);  // Works out the status and destination of every item.
const
  BlankJobMark = '{no job}';        // stored in DateJobCodes for a date whose job code is blank

function JobCodeFor(S: TAppSettings; Item: TImageItem): string;  // Returns the job code that applies to an item.
function ComputeDest(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer): string;  // Builds the destination path of an item.
function ExampleDest(S: TAppSettings; const DirMask, NameMask, Job: string): string;  // Builds an example destination path.
function UniqueName(const Dest: string; NStyle: Boolean = False): string;  // Makes a destination name unique.
procedure EnsureThumb(Item: TImageItem; Box: Integer);  // Makes sure an item has a thumbnail.
{ Frees an item's thumbnail again (it is rendered anew, or read from the disk cache, when needed) }
procedure ReleaseThumb(Item: TImageItem);
{ True for file types that are slow to decode (HEIC, AVIF, TIFF, DNG) }
function ThumbIsHeavy(const FileName: string): Boolean;
{ Keeps the thumbnail disk cache below ThumbCacheMaxBytes by deleting the oldest files
  (called when the program closes) }
procedure PruneThumbCache;
{ What a file really is, from its first bytes: 1 TIFF, 2 JPEG, 3 PNG, 4 BMP, 5 GIF, 6 WebP,
  7 HEIC/AVIF family, 0 other }
function SniffFileKind(const FileName: string): Integer;
{ The first bytes of a file as text for the log, e.g. ' [file starts with: 52 49 46 46 ...]' }
function HeaderNote(const FileName: string): string;
{ True if the file starts with plain text instead of picture data }
function LooksLikeText(const FileName: string): Boolean;
{ Turns the bitmap upright for an EXIF orientation of 2..8; Bmp may be replaced. }
procedure OrientBitmap(var Bmp: TBitmap; Orient: Integer);
{ Builds a bitmap (at most MaxSide pixels on the long side) from the uncompressed
  image data of a TIFF/DNG file. False if the file has no such image. }
function LoadTiffBitmap(const FileName: string; MaxSide: Integer; Bmp: TBitmap): Boolean;
{ True if the plain TIFF/DNG image is larger than a JPEG preview of W x H pixels. }
function TiffRgbIsLarger(const FileName: string; W, H: Integer): Boolean;
procedure LogThumb(const Msg: string);  // Writes a line to the thumbnail log.
function CopyFileStream(const Src, Dst: string): Boolean;  // Copies a file with a stream.
type
  TCopyResult = (crOk, crFailed, crVerifyFailed, crCanceled);  // result of a copy
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
{ True when Item is a .lrprev file that is downloaded as a .jpg only (Lightroom previews as .jpg, without the original) }
function LrPrevJpgOnly(S: TAppSettings; Item: TImageItem): Boolean;
{ Writes the largest preview picture of the .lrprev file Src to Dst as a .jpg (not re-encoded);
  with Verify the file is read back and compared. Hash is the MD5 of the .jpg. }
function SaveLrPrevJpg(const Src, Dst: string; Verify: Boolean; out Hash: string;
  out Err: string): TCopyResult;
{ Folder for the backup copy of an item (own folder template, same patterns), with the file
  name of the main copy }
function BackupDestFor(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer;
  const MainDest: string): string;
function FormatSize(Size: Int64): string;  // Formats a file size as text.

implementation


const
  AttrHidden = $02;   // portable copies of faHidden / faSysFile
  AttrSystem = $04;  // attribute bit for system entries
  ImageExts = ';.jpg;.jpeg;.jpe;.png;.gif;.tif;.tiff;.bmp;.nef;.nrw;.cr2;.cr3;.crw;' +  // file types that are scanned (first part)
              '.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;.heic;.heif;.avif;.webp;' +  // file types that are scanned (second part)
              '.mp4;.mov;.lrv;.mp3;.thm;.lrprev;';
  VideoExts = ';.mp4;.mov;.lrv;';  // video file types
  AudioExts = ';.mp3;';  // audio file types
  TiffExts = ';.tif;.tiff;.dng;';  // TIFF file types
  RawExts = ';.nef;.nrw;.cr2;.cr3;.crw;.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;';  // raw file types
  ExifExts = ';.jpg;.jpeg;.jpe;.tif;.tiff;.nef;.nrw;.cr2;.cr3;.heic;.heif;.avif;.crw;.arw;.sr2;.dng;.pef;.srw;';  // file types that may hold EXIF data

var
  { Items that currently hold a thumbnail, oldest first. Every thumbnail is a Windows bitmap
    handle and a process may only own about 10,000 of them, so only the newest ones are kept. }
  ThumbLru: TList = nil;  // items that currently hold a thumbnail

const
  ThumbKeepMax = 1200;  // largest number of thumbnails kept at once

{ TImageItem }

{ Frees the thumbnail and removes the item from the thumbnail list. }
destructor TImageItem.Destroy;
begin
  if Assigned(ThumbLru) then ThumbLru.Remove(Self);  // remove the item from the thumbnail list
  Thumb.Free;  // free the thumbnail
  inherited Destroy;  // run the inherited destructor
end;

{ Returns the text shown in the status column. }
function TImageItem.StatusText: string;
begin
  case Status of  // by state
    isNew:
      begin
        Result := 'New file';  // not downloaded yet
        if ClashInfo <> '' then Result := 'New file (renamed)';  // a name clash that is renamed automatically (reason in ClashInfo)
      end;
    isDownloaded: Result := 'Already downloaded';  // already downloaded
    isNameClash:
      begin
        Result := 'Name clash';  // name clash (the reason is in ClashInfo, shown in Properties and the status bar)
      end;
    isDuplicate: Result := 'Duplicate file';  // same content as another file
  else
    Result := '';  // unknown state
  end;
end;

{ True when the item has a problem (a name clash). }
function TImageItem.IsProblem: Boolean;
begin
  Result := Status = isNameClash;  // only name clashes are problems
end;

{ True when the file has a JPEG extension. }
function TImageItem.IsJpeg: Boolean;
var
  E: string;  // E: file extension
begin
  E := LowerCase(ExtractFileExt(FileName));  // lower case extension
  Result := (E = '.jpg') or (E = '.jpeg') or (E = '.jpe');  // compare with the JPEG extensions
end;

{ True when the file has a video extension. }
function TImageItem.IsVideo: Boolean;
begin
  Result := Pos(';' + LowerCase(ExtractFileExt(FileName)) + ';', VideoExts) > 0;  // look the extension up in the video list
end;

{ True when the file has an audio extension. }
function TImageItem.IsAudio: Boolean;
begin
  Result := Pos(';' + LowerCase(ExtractFileExt(FileName)) + ';', AudioExts) > 0;  // look the extension up in the audio list
end;

{ Returns the length of a video as h:mm:ss or m:ss. }
function TImageItem.DurationText: string;
var
  T: Int64;  // T: whole seconds
begin
  Result := '';  // unknown by default
  if Duration <= 0 then Exit;  // no length known
  T := Round(Duration);  // whole seconds
  if T >= 3600 then
    Result := Format('%d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60])  // hours, minutes, seconds
  else
    Result := Format('%d:%.2d', [T div 60, T mod 60]);  // minutes and seconds
end;

{ Formats a size as MB or KB. }
function FormatSize(Size: Int64): string;
begin
  if Size >= 1048576 then  // a megabyte or more
    Result := FormatFloat('0.0', Size / 1048576) + 'MB'  // show with one decimal
  else
    Result := IntToStr((Size + 512) div 1024) + 'KB';  // show in rounded KB
end;

{ Returns the size of the item as text. }
function TImageItem.SizeText: string;
begin
  Result := FormatSize(Size);  // format the size
end;

{ Returns item I of the list. }
function ItemAt(L: TObjectList; I: Integer): TImageItem;
begin
  Result := TImageItem(L[I]);  // cast the list entry
end;

{ ---- scanning ---- }

{ True when the file name has an image extension. }
function IsImageFile(const Name: string): Boolean;
begin
  Result := Pos(';' + LowerCase(ExtractFileExt(Name)) + ';', ImageExts) > 0;  // look the extension up in the list
end;

{ Compares two items by capture time, then by name. }
function CompareItems(A, B: Pointer): Integer;
var
  X, Y: TImageItem;  // X, Y: the items
begin
  X := TImageItem(A);  // first item
  Y := TImageItem(B);  // second item
  Result := CompareValue(X.CaptureTime, Y.CaptureTime);  // compare the capture times
  if Result = 0 then
    Result := CompareText(X.FileName, Y.FileName);  // same time: compare the names
end;

{ Chooses the capture time of a video. The creation time in an MP4/MOV header is Universal Time on
  phones but the camera's own clock time on many cameras. The file time (the end of the recording)
  tells which reading is right: the one that puts the start of the clip closest to it wins. When
  neither fits (a copied file, say) the Universal Time reading is used. }
function PickMovieTime(Created, FileTime: TDateTime; Duration: Double): TDateTime;
var
  AsLocal: TDateTime;  // AsLocal: the stored time converted from Universal Time to local time
  Start: TDateTime;  // Start: start of the recording according to the file time
  DiffRaw, DiffLocal: Double;  // DiffRaw, DiffLocal: distance of each reading from Start
begin
  AsLocal := UniversalTimeToLocal(Created);  // Universal Time reading
  Start := FileTime - Duration / 86400;  // file time is the end of the recording
  DiffRaw := Abs(Created - Start);  // distance of the stored time used as it is
  DiffLocal := Abs(AsLocal - Start);  // distance of the converted time
  if (DiffRaw < DiffLocal) and (DiffRaw < 1) then  // the stored time is already local and plausible
    Result := Created  // use it unchanged
  else
    Result := AsLocal;  // use the converted time
end;

var
  ScanSkipLrData: Boolean = True;  // True: Lightroom preview folders (.lrdata) are not scanned (set by ScanFolder)
  LastProgTick: QWord = 0;  // time of the last progress report
  LoggedMsgs: TStringList = nil;  // messages already written to the log, so that each is written only once

{ ---- EXIF cache ----
  The scan keeps the EXIF fields of every file it read in exifcache.txt (in CacheDir), so a folder
  that is scanned again does not read every file again. A line is used only while the file keeps
  its path, size and modification time. }

const
  { Change when ReadExifFromFile changes so that values kept from an older version are read again }
  ExifCacheVersion = 'PhotoDownloader EXIF cache 1';  // first line of the cache file
  ExifCacheMax = 100000;  // largest number of files kept in the cache

type
  { The cached EXIF fields of one file }
  TExifCacheEntry = class
    Data: string;  // the fields, separated by tabs
    Used: Boolean;  // True when the file was seen in this session (kept first when the cache is full)
  end;

var
  ExifCache: TStringList = nil;  // key (path, size, time) -> TExifCacheEntry; loaded on the first scan
  ExifCacheDirty: Boolean = False;  // True when the cache changed since it was saved

{ Returns the name of the EXIF cache file. }
function ExifCacheFile: string;
begin
  Result := CacheDir + 'exifcache.txt';  // next to the thumbnail cache
end;

{ Returns the cache key of a file: path, size and modification time, separated by tabs. }
function ExifCacheKey(const FullPath: string; Size: Int64; Time: LongInt): string;
begin
  Result := FullPath + #9 + IntToStr(Size) + #9 + IntToStr(Time);  // key fields
end;

{ Loads the EXIF cache file into ExifCache (an empty cache when there is none or it is from another version). }
procedure LoadExifCache;
var
  L: TStringList;  // L: lines of the file
  I, P, Tabs: Integer;  // I: line; P: character position; Tabs: tabs counted
  E: TExifCacheEntry;  // E: new entry
  Line: string;  // Line: current line
begin
  ExifCache := TStringList.Create;  // the cache
  ExifCache.OwnsObjects := True;  // entries are freed with the list
  ExifCache.CaseSensitive := True;  // keys compare exactly
  ExifCache.UseLocale := False;  // compare the bytes, not by language rules
  L := TStringList.Create;  // lines of the file
  try
    try
      if FileExistsUTF8(ExifCacheFile) then L.LoadFromFile(ExifCacheFile);  // read the file
    except
      L.Clear;  // an unreadable cache is ignored
    end;
    if (L.Count > 0) and (L[0] = ExifCacheVersion) then  // only a cache of this version is used
    begin
      ExifCache.Capacity := L.Count;  // room for every line
      for I := 1 to L.Count - 1 do  // every line after the version
      begin
        Line := L[I];  // current line
        // the key is the first three fields; the rest is the data
        Tabs := 0;  // no tab yet
        P := 1;  // start of the line
        while (P <= Length(Line)) and (Tabs < 3) do  // find the third tab
        begin
          if Line[P] = #9 then Inc(Tabs);  // count the tab
          Inc(P);  // next character
        end;
        if Tabs < 3 then Continue;  // a broken line
        E := TExifCacheEntry.Create;  // new entry
        E.Data := Copy(Line, P, MaxInt);  // the data after the key
        ExifCache.AddObject(Copy(Line, 1, P - 2), E);  // the key without its last tab
      end;
    end;
  finally
    L.Free;  // free the lines
  end;
  ExifCache.Sorted := True;  // sort once after loading (faster than keeping it sorted while adding)
  ExifCache.Duplicates := dupIgnore;  // a key is kept only once
  ExifCacheDirty := False;  // same as the file
end;

{ Writes the EXIF cache file when it changed; files seen in this session are kept first when it is full. }
procedure SaveExifCache;
var
  L: TStringList;  // L: lines of the file
  I, Pass: Integer;  // I: entry; Pass: 0 = entries seen in this session, 1 = the others
  E: TExifCacheEntry;  // E: current entry
begin
  if (ExifCache = nil) or (not ExifCacheDirty) then Exit;  // nothing to write
  L := TStringList.Create;  // lines of the file
  try
    try
      L.Add(ExifCacheVersion);  // version line
      for Pass := 0 to 1 do  // used entries first, then the others while there is room
        for I := 0 to ExifCache.Count - 1 do  // every entry
        begin
          if L.Count > ExifCacheMax then Break;  // the cache is full
          E := TExifCacheEntry(ExifCache.Objects[I]);  // current entry
          if E.Used = (Pass = 0) then L.Add(ExifCache[I] + #9 + E.Data);  // key and data
        end;
      L.SaveToFile(ExifCacheFile);  // write the file
      ExifCacheDirty := False;  // same as the file now
    except
      // the cache is only a speed-up
    end;
  finally
    L.Free;  // free the lines
  end;
end;

{ Turns EXIF fields into the cache data text; False when a text holds a tab or line break. }
function ExifToData(Res: Boolean; const Info: TExifInfo; out Data: string): Boolean;
var
  D: Double;  // D: capture time, so its exact bits can be stored
  I, Tabs: Integer;  // I: character position; Tabs: tabs counted
begin
  D := Info.DateTaken;  // capture time
  Data := IntToStr(Ord(Res)) + #9 + IntToStr(Ord(Info.Valid)) + #9 + Info.Make + #9 + Info.Model + #9 +  // result and texts
    Info.Artist + #9 + Info.Owner + #9 + Info.Serial + #9 + IntToStr(Ord(Info.HasDate)) + #9 +
    IntToHex(PInt64(@D)^, 16) + #9 + IntToStr(Info.ISO) + #9 + IntToStr(Info.Orientation);  // date (exact) and numbers
  Result := False;  // assume an unusable text
  Tabs := 0;  // no tab yet
  for I := 1 to Length(Data) do  // every character
  begin
    if Data[I] in [#10, #13] then Exit;  // a line break would split the line
    if Data[I] = #9 then Inc(Tabs);  // count the separators
  end;
  Result := Tabs = 10;  // a tab inside a text would add a field
end;

{ Turns the cache data text back into EXIF fields; False when it is broken. }
function DataToExif(const Data: string; out Res: Boolean; out Info: TExifInfo): Boolean;
var
  F: TStringArray;  // F: the fields
  Bits: Int64;  // Bits: stored bits of the capture time
  D: Double;  // D: capture time
begin
  Result := False;  // assume broken data
  Res := False;  // no EXIF data
  Info.Valid := False;  // clear the fields
  Info.Make := ''; Info.Model := ''; Info.Artist := ''; Info.Owner := ''; Info.Serial := '';
  Info.DateTaken := 0; Info.HasDate := False; Info.ISO := 0; Info.Orientation := 0;
  F := Data.Split([#9]);  // split into fields
  if Length(F) <> 11 then Exit;  // wrong number of fields
  if not TryStrToInt64('$' + F[8], Bits) then Exit;  // broken date
  D := PDouble(@Bits)^;  // the exact capture time
  Res := F[0] = '1';  // result of ReadExifFromFile
  Info.Valid := F[1] = '1';  // valid flag
  Info.Make := F[2]; Info.Model := F[3]; Info.Artist := F[4]; Info.Owner := F[5]; Info.Serial := F[6];  // texts
  Info.HasDate := F[7] = '1';  // date flag
  Info.DateTaken := D;  // capture time
  Info.ISO := StrToIntDef(F[9], 0);  // ISO speed
  Info.Orientation := StrToIntDef(F[10], 0);  // orientation
  Result := True;  // success
end;

{ ReadExifFromFile through the cache: a file with the same path, size and time is not read again. }
function CachedExif(const FullPath: string; Size: Int64; Time: LongInt; out Info: TExifInfo): Boolean;
var
  Key, Data: string;  // Key: cache key; Data: cached fields
  I: Integer;  // I: position in the cache
  E: TExifCacheEntry;  // E: cache entry
begin
  if ExifCache = nil then LoadExifCache;  // load the cache on the first scan
  Key := ExifCacheKey(FullPath, Size, Time);  // key of this file
  if ExifCache.Find(Key, I) then  // the file was read before
  begin
    E := TExifCacheEntry(ExifCache.Objects[I]);  // its entry
    if DataToExif(E.Data, Result, Info) then  // usable data
    begin
      E.Used := True;  // seen in this session
      Exit;  // done without reading the file
    end;
  end;
  Result := ReadExifFromFile(FullPath, Info);  // read the file (an exception skips the cache)
  if ExifToData(Result, Info, Data) then  // fields that fit in one line
  begin
    if ExifCache.Find(Key, I) then  // replace broken data
      TExifCacheEntry(ExifCache.Objects[I]).Data := Data
    else
    begin
      E := TExifCacheEntry.Create;  // new entry
      E.Data := Data;  // its fields
      E.Used := True;  // seen in this session
      ExifCache.AddObject(Key, E);  // add it
    end;
    ExifCacheDirty := True;  // save it after the scan
  end;
end;

{ Scans one folder and its subfolders for image files. }
procedure ScanDir(const Dir: string; Items: TObjectList; var Cnt: Integer;
  Progress: TScanProgress);
var
  SR: TSearchRec;  // SR: directory entry
  Full: string;  // Full: complete path of the entry
  It: TImageItem;  // It: new item
  Info: TExifInfo;  // Info: EXIF data of the file
  MovCreated: TDateTime;  // MovCreated: creation time stored in a video
  MovHasDate: Boolean;  // MovHasDate: True when the video has a usable creation time
  MovLen: Double;  // MovLen: length of a video in seconds
  Cat: TLrCatInfo;  // Cat: what the Lightroom catalog knows about a .lrprev file
begin
  if FindFirstUTF8(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) <> 0 then Exit;  // start the search; stop if the folder is empty
  try
    repeat
      // report progress for every entry, not only for pictures: folders with thousands of
      // non-picture files (a Lightroom preview cache, for example) otherwise freeze the window
      // and the Cancel button for a long time
      if Assigned(Progress) and (GetTickCount64 - LastProgTick >= 80) then  // report progress at most every 80 ms
      begin
        LastProgTick := GetTickCount64;  // remember the time
        ScanCurrentDir := Dir;  // folder being read
        Progress(Cnt);  // report the count (lets the window update and Cancel work)
      end;
      if ScanAbort then Break;  // stop when the scan was aborted
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then Continue;  // skip dot entries and hidden names
      Full := IncludeTrailingPathDelimiter(Dir) + SR.Name;  // complete path
      if (SR.Attr and faDirectory) <> 0 then  // folder entry
      begin
        // skip hidden/system folders such as $RECYCLE.BIN and System Volume Information
        // also skip Lightroom preview folders unless they are wanted: they hold only .lrprev files,
        // often in tens of thousands of small folders that take long to walk through
        if ((SR.Attr and (AttrHidden or AttrSystem)) = 0) and  // skip hidden and system folders
           not (ScanSkipLrData and SameText(ExtractFileExt(SR.Name), '.lrdata')) then  // and unwanted .lrdata folders
          ScanDir(Full, Items, Cnt, Progress);  // scan the subfolder
      end
      else if IsImageFile(SR.Name) then  // file with an image extension
      begin
        It := TImageItem.Create;  // create the item
        It.FullPath := Full;  // complete path
        It.FileName := SR.Name;  // file name
        It.SourceDir := Dir;  // folder
        It.Size := SR.Size;  // file size
        try
          It.FileTime := FileDateToDateTime(SR.Time);  // file modification time
        except
          It.FileTime := Now;  // use the current time if invalid
        end;
        It.IsReadOnly := (SR.Attr and faReadOnly) <> 0;  // read-only attribute
        It.CaptureTime := It.FileTime;  // use the file time unless EXIF has a date
        // A file that opens but cannot be read (a cloud placeholder, a damaged or locked file, a file that
        // shrank) raises a stream read error. Such a file is still listed, with its file time, and the scan goes on.
        try
          if Pos(';' + LowerCase(ExtractFileExt(SR.Name)) + ';', ExifExts) > 0 then  // file type may carry EXIF data
            if CachedExif(Full, SR.Size, SR.Time, Info) then  // read the EXIF data (from the cache when the file is unchanged)
            begin
              if Info.HasDate then It.CaptureTime := Info.DateTaken;  // capture date
              It.Camera := Info.Model;  // camera model
              It.Make := Info.Make;  // camera maker
              It.Serial := Info.Serial;  // camera serial number
              It.ISO := Info.ISO;  // ISO speed
              It.Orientation := Info.Orientation;  // orientation
              if Info.Owner <> '' then It.Owner := Info.Owner else It.Owner := Info.Artist;  // owner, or the artist when there is none
            end;
        except
          on E: Exception do  // unreadable metadata: keep the file time and the empty camera fields
            LogThumb(Full + ': metadata could not be read: ' + E.Message);  // note it in the log
        end;
        // a Lightroom preview: date, camera and the photo's file name from the Lightroom catalog
        if Pos(';' + LowerCase(ExtractFileExt(SR.Name)) + ';', LrPrevExts) > 0 then  // .lrprev file
          if LrCatLookup(Full, Cat) then  // its photo is in the catalog
          begin
            It.CatalogName := Cat.OrigName;  // file name of the photo
            if Cat.HasDate then It.CaptureTime := Cat.CaptureTime;  // capture date
            It.Camera := Cat.Camera;  // camera model
            It.Serial := Cat.Serial;  // camera serial number
            It.ISO := Cat.ISO;  // ISO speed
          end;
        try
          if It.IsVideo then  // MP4, MOV or LRV: read the movie header
            if ReadMovieHeader(Full, MovCreated, MovHasDate, MovLen) then  // creation time and length
            begin
              It.Duration := MovLen;  // length for the thumbnail badge
              if MovHasDate then It.CaptureTime := PickMovieTime(MovCreated, It.FileTime, MovLen);  // capture date
            end;
        except
          on E: Exception do  // unreadable movie header: keep the file time
            LogThumb(Full + ': movie header could not be read: ' + E.Message);  // note it in the log
        end;
        Items.Add(It);  // add the item to the list
        Inc(Cnt);  // count the item
      end;
    until FindNextUTF8(SR) <> 0;  // next directory entry
  finally
    FindCloseUTF8(SR);  // close the search
  end;
end;

{ Scans the source: the DCIM folder when there is one, otherwise the whole root. }
procedure ScanFolder(const Root: string; S: TAppSettings; Items: TObjectList;
  Progress: TScanProgress);
var
  Cnt, I: Integer;  // Cnt: files found; I: loop counter
  Dcim: string;  // Dcim: path of the DCIM folder
begin
  Items.Clear;  // empty the list
  if LoggedMsgs <> nil then LoggedMsgs.Clear;  // a new scan may log each message again
  Cnt := 0;  // nothing found yet
  ScanAbort := False;  // clear the abort flag
  Dcim := IncludeTrailingPathDelimiter(Root) + 'DCIM';  // path of the DCIM folder
  LrCatReset;  // read the Lightroom catalogs anew, so changes made in Lightroom are seen
  ScanSkipLrData := not S.ScanLrData;  // Lightroom preview folders only when wanted
  try
    if (not S.ScanWholeDisk) and DirectoryExistsUTF8(Dcim) then  // use DCIM unless the whole disk is to be scanned
      ScanDir(Dcim, Items, Cnt, Progress)  // scan DCIM
    else
      ScanDir(Root, Items, Cnt, Progress);  // scan the whole root
  finally
    SaveExifCache;  // keep what was read for the next scan (also after Cancel)
    if LrCatMessages <> '' then LogThumb(Trim(LrCatMessages));  // Lightroom catalogs that could not be read
  end;
  Items.Sort(@CompareItems);  // sort by capture time
  for I := 0 to Items.Count - 1 do  // number the items
    ItemAt(Items, I).Index := I + 1;  // set the grid number
end;

{ ---- tokens ---- }

{ Replaces characters that are not allowed in file names with underscores. }
function SanitizePart(const V: string): string;
var
  I: Integer;  // I: character index
begin
  Result := V;  // start with the original text
  for I := 1 to Length(Result) do  // every character
    if WinSafeNamesOn then  // Windows rules apply
    begin
      if Result[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then  // forbidden characters
        Result[I] := '_';  // replace with underscore
    end
    else if Result[I] in ['/', #0] then      // Linux only forbids the path separator
      Result[I] := '_';  // replace with underscore
end;

{ Converts the separators of a mask to the ones of this system. }
function NormMask(const M: string): string;
begin
  Result := StringReplace(M, '\', PathDelim, [rfReplaceAll]);  // backslash to the system separator
  if PathDelim <> '/' then Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);  // slash to the system separator when it is not a slash
end;

{ Token r: the longest run of digits in the original name (the last one on a tie),
  or the whole original name when it has no digits, so unnumbered files stay unique. }
function ImageNumberOf(const Base: string): string;
var
  I, J: Integer;  // I, J: character positions
  Run: string;  // Run: digits found
begin
  Result := '';  // nothing found yet
  I := 1;  // start at the first character
  while I <= Length(Base) do  // walk through the name
  begin
    if Base[I] in ['0'..'9'] then  // a digit starts a run
    begin
      J := I;  // end of the run
      while (J <= Length(Base)) and (Base[J] in ['0'..'9']) do Inc(J);  // find the end of the run
      Run := Copy(Base, I, J - I);  // the digits of the run
      if Length(Run) >= Length(Result) then Result := Run;  // keep the longest run (the last on a tie)
      I := J;  // continue after the run
    end
    else
      Inc(I);  // next character
  end;
  if Result = '' then Result := Base;  // no digits: use the whole name
end;

{ Returns the T8 or T9 mapping value for a camera. }
function MapValue(S: TAppSettings; const Camera: string; Which: Integer): string;
var
  I: Integer;  // I: loop counter
  N, A, B, Raw: string;  // N: camera name; A, B: the two token values; Raw: chosen value
begin
  Raw := '{T1}';  // default value
  if S.Mappings.Count > 0 then  // mappings exist
  begin
    MapSplit(S.Mappings[0], N, A, B);  // split the default mapping
    if Which = 8 then Raw := A else Raw := B;  // first token takes the first value, second token the second
  end;
  for I := 1 to S.Mappings.Count - 1 do  // look for a mapping of this camera
  begin
    MapSplit(S.Mappings[I], N, A, B);  // split the entry
    if SameText(N, Camera) then  // camera name matches
    begin
      if Which = 8 then Raw := A else Raw := B;  // take the value
      Break;  // stop searching
    end;
  end;
  Result := StringReplace(Raw, '{T1}', Camera, [rfReplaceAll, rfIgnoreCase]);  // insert the camera name for the T1 placeholder
end;

{ Returns the extension the saved file gets (with the dot, case as in the original name):
  .jpe becomes .jpg when requested, a Lightroom preview saved as a picture becomes .jpg. }
function SavedExt(S: TAppSettings; Item: TImageItem): string;
begin
  Result := ExtractFileExt(Item.FileName);  // original extension
  if S.RenameJpe and SameText(Result, '.jpe') then Result := '.jpg';  // rename .jpe to .jpg when requested
  if LrPrevJpgOnly(S, Item) then Result := '.jpg';  // a Lightroom preview saved as a .jpg
end;

{ Returns the text of one token for an item; Known is False for an unknown token. }
function TokenValue(const Tok: string; Item: TImageItem; const Job: string;
  SeqDown, SeqSess: Integer; S: TAppSettings; out Known: Boolean): string;
var
  DT: TDateTime;  // DT: capture time
  H, W, I: Integer;  // H: hour; W: width of the sequence number; I: character index
  Base: string;  // Base: file name without extension
begin
  Known := True;  // assume the token is valid
  DT := Item.CaptureTime;  // capture time of the item
  Base := ChangeFileExt(Item.FileName, '');  // file name without extension
  // a Lightroom preview is named after its photo in the catalog when that is known
  if Item.CatalogName <> '' then Base := ChangeFileExt(Item.CatalogName, '');  // catalog name without extension
  case Tok of
    'd': Result := FormatDateTime('yyyymmdd', DT);  // date as yyyymmdd
    'y': Result := FormatDateTime('yy', DT);  // two-digit year
    'Y': Result := FormatDateTime('yyyy', DT);  // four-digit year
    'm': Result := FormatDateTime('mm', DT);  // month number
    'b': Result := FormatDateTime('mmm', DT);  // short month name
    'B': Result := FormatDateTime('mmmm', DT);  // full month name
    'D': Result := FormatDateTime('dd', DT);  // day of the month
    'a': Result := FormatDateTime('ddd', DT);  // short weekday name
    'A': Result := FormatDateTime('dddd', DT);  // full weekday name
    'W': Result := Format('%.2d', [WeekOf(DT)]);  // week number
    't': Result := FormatDateTime('hhnnss', DT);  // time as hhmmss
    'H': Result := FormatDateTime('hh', DT);  // hour (00-23)
    'I':
      begin
        H := HourOf(DT) mod 12;  // hour on a 12-hour clock
        if H = 0 then H := 12;  // midnight and noon are 12
        Result := Format('%.2d', [H]);  // two digits
      end;
    'M': Result := FormatDateTime('nn', DT);  // minutes
    'S': Result := FormatDateTime('ss', DT);  // seconds
    'q': Result := ExtractFileName(ExcludeTrailingPathDelimiter(Item.SourceDir));  // name of the folder the picture came from
    'r': Result := ImageNumberOf(Base);  // number from the original file name
    'o': Result := Base;  // original file name
    'f':
      begin
        I := 1;  // start at the first character
        while (I <= Length(Base)) and not (Base[I] in ['0'..'9']) do Inc(I);  // find the first digit
        Result := Copy(Base, 1, I - 1);  // letters before the number
      end;
    'O': Result := Item.Owner;  // owner
    'i': Result := IntToStr(Item.ISO);  // ISO speed
    'c': Result := Item.Serial;  // camera serial number
    'T', 'T1': Result := Item.Camera;  // camera model
    'T8': Result := MapValue(S, Item.Camera, 8);  // first custom token of the camera
    'T9': Result := MapValue(S, Item.Camera, 9);  // second custom token of the camera
    'J': Result := Job;  // job code
    'E': Result := UpperCase(Copy(SavedExt(S, Item), 2, MaxInt));  // file extension in upper case, without the dot
    'e': Result := LowerCase(Copy(SavedExt(S, Item), 2, MaxInt));  // file extension in lower case, without the dot
    'ea': Result := Copy(SavedExt(S, Item), 2, MaxInt);  // file extension as it is, without the dot
    'seq#': Result := IntToStr(SeqDown);  // download sequence number
  else
    if (Length(Tok) = 2) and (Tok[1] = 'n') and (Tok[2] in ['1'..'9']) then  // n1 to n9: sequence number of this session
    begin
      W := Ord(Tok[2]) - Ord('0');  // number of digits
      Result := IntToStr(SeqSess);  // sequence number as text
      while Length(Result) < W do Result := '0' + Result;  // pad with zeros
    end
    else
    begin
      Known := False;  // unknown token
      Result := '';  // no text
    end;
  end;
end;

{ Replaces every token in a mask by its value. }
function ExpandTokens(const Mask: string; Item: TImageItem; const Job: string;
  SeqDown, SeqSess: Integer; S: TAppSettings): string;
var
  I, J: Integer;  // I: position in the mask; J: position of the closing brace
  Tok, V: string;  // Tok: token name; V: token value
  Known: Boolean;  // True when the token is known
begin
  Result := '';  // nothing yet
  I := 1;  // start at the first character
  while I <= Length(Mask) do  // walk through the mask
  begin
    if Mask[I] = '{' then  // a brace starts a token
    begin
      J := PosEx('}', Mask, I + 1);  // find the closing brace
      if J > 0 then  // closing brace found
      begin
        Tok := Copy(Mask, I + 1, J - I - 1);  // token name
        V := TokenValue(Tok, Item, Job, SeqDown, SeqSess, S, Known);  // token value
        if Known then
          Result := Result + SanitizePart(V)  // add the value without forbidden characters
        else
          Result := Result + Copy(Mask, I, J - I + 1);   // e.g. the literal {Job Name}
        I := J + 1;  // continue after the token
        Continue;  // next character
      end;
    end;
    Result := Result + Mask[I];  // plain character
    Inc(I);  // next character
  end;
end;

{ Returns the job code of an item (the one stored for its date, or the current one). }
function JobCodeFor(S: TAppSettings; Item: TImageItem): string;
begin
  Result := S.DateJobCodes.Values[Item.DateKey];  // code stored for the date of the picture
  if Result = BlankJobMark then
    Result := ''                    // this date was given a blank job code on purpose
  else if Result = '' then
    Result := S.JobCode;  // use the current job code
end;

{ A blank job code leaves separators behind ("2026-10-25-"); remove them. }
function TidyBlankJob(const S: string): string;
var
  I: Integer;  // I: loop counter
begin
  Result := S;  // start with the original text
  for I := 1 to 3 do  // repeat a few times
  begin
    Result := StringReplace(Result, '--', '-', [rfReplaceAll]);  // double hyphen
    Result := StringReplace(Result, '__', '_', [rfReplaceAll]);  // double underscore
    Result := StringReplace(Result, ' -', '-', [rfReplaceAll]);  // blank before a hyphen
    Result := StringReplace(Result, '- ', '-', [rfReplaceAll]);  // blank after a hyphen
    Result := StringReplace(Result, '-' + PathDelim, PathDelim, [rfReplaceAll]);  // hyphen before a folder separator
    Result := StringReplace(Result, '_' + PathDelim, PathDelim, [rfReplaceAll]);  // underscore before a folder separator
    Result := StringReplace(Result, PathDelim + '-', PathDelim, [rfReplaceAll]);  // hyphen after a folder separator
    Result := StringReplace(Result, PathDelim + '_', PathDelim, [rfReplaceAll]);  // underscore after a folder separator
  end;
  while (Result <> '') and (Result[Length(Result)] in ['-', '_', ' ']) do  // remove trailing separators
    Delete(Result, Length(Result), 1);  // remove the last character
  while (Result <> '') and (Result[1] in ['-', '_', ' ']) do  // remove leading separators
    Delete(Result, 1, 1);  // remove the first character
end;

{ Builds the destination path from the folder mask, the file name mask and the job code. }
function BuildDest(S: TAppSettings; Item: TImageItem; const DirMask, NameMask, Job: string;
  SeqDown, SeqSess: Integer): string;
var
  Dir, Nm, Ext: string;  // Dir: folder; Nm: file name; Ext: extension
begin
  Dir := ExpandTokens(NormMask(DirMask), Item, Job, SeqDown, SeqSess, S);  // folder with tokens replaced
  Nm := ExpandTokens(NormMask(NameMask), Item, Job, SeqDown, SeqSess, S);  // file name with tokens replaced
  if Job = '' then  // blank job code
  begin
    Dir := TidyBlankJob(Dir);  // tidy the folder
    Nm := TidyBlankJob(Nm);  // tidy the file name
  end;
  Ext := SavedExt(S, Item);  // extension of the saved file
  if S.LowerExt then Ext := LowerCase(Ext);  // lower case extension when requested
  if S.LowerName then Nm := LowerCase(Nm);  // lower case name when requested
  if Dir <> '' then Dir := IncludeTrailingPathDelimiter(Dir);  // add the separator
  Result := Dir + Nm + Ext;  // complete path
end;

{ Builds the destination path of an item from the settings. }
function ComputeDest(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer): string;
begin
  Result := BuildDest(S, Item, S.DownloadDir, S.FileNameMask, JobCodeFor(S, Item),  // use the settings masks and the job code of the item
    SeqDown, SeqSess);
end;

{ Builds an example destination path from a sample picture. }
function ExampleDest(S: TAppSettings; const DirMask, NameMask, Job: string): string;
var
  It: TImageItem;  // It: sample item
begin
  It := TImageItem.Create;  // create the sample
  try
    It.FileName := '_DSC0123.JPG';  // sample file name
    It.SourceDir := 'DCIM' + PathDelim + '100NCD700';  // sample folder
    It.CaptureTime := Now;  // current time
    It.Camera := 'NIKON D700';  // sample camera
    It.Serial := '1234567';  // sample serial number
    It.Owner := 'Owner';  // sample owner
    It.ISO := 200;  // sample ISO
    Result := BuildDest(S, It, DirMask, NameMask, Job, S.SeqNext, 1);  // build the example path
  finally
    It.Free;  // free the sample
  end;
end;

{ Adds -1, -2 ... (or " (1)", " (2)" ... when NStyle is True) to a path until no file with that name exists. }
function UniqueName(const Dest: string; NStyle: Boolean = False): string;
var
  N: Integer;  // N: number added to the name
  Base, Ext: string;  // Base: path without extension; Ext: extension
begin
  Ext := ExtractFileExt(Dest);  // extension
  Base := Copy(Dest, 1, Length(Dest) - Length(Ext));  // path without extension
  N := 1;  // first number
  repeat
    if NStyle then
      Result := Base + ' (' + IntToStr(N) + ')' + Ext  // try the "(1)" style name
    else
      Result := Base + '-' + IntToStr(N) + Ext;  // try the "-1" style name
    Inc(N);  // next number
  until not FileExistsUTF8(Result);
end;

{ ---- status ---- }

{ Sets the status and destination of every item and finds duplicates and name clashes. }
procedure EvaluateItems(Items: TObjectList; S: TAppSettings);
var
  I, P, J: Integer;  // I: item index; P: position in a list; J: number of the first item with a name
  It: TImageItem;  // It: current item
  Dups, Groups, Firsts: TStringList;  // Dups: keys of pictures seen; Groups: destinations with counts; Firsts: first item per destination
  Key: string;  // Key: duplicate key
  Taken: TStringList;  // Taken: destination names already planned for other files
  DestDirs: TStringList;  // DestDirs: destination folders listed so far; each object is a list of its file names with sizes

  { Returns the size of the file at Path, or -1 when there is none. Each destination folder is listed
    once, which is much faster than asking for every file (above all on a network drive). }
  function DestSize(const Path: string): Int64;
  var
    Dir: string;  // Dir: folder of the file
    P, Q: Integer;  // P: position of the folder; Q: position of the file
    Names: TStringList;  // Names: files in the folder, sizes in the objects
    SR: TSearchRec;  // SR: directory entry
  begin
    Result := -1;  // no such file
    Dir := ExtractFilePath(Path);  // folder of the file
    if not DestDirs.Find(Dir, P) then  // folder not listed yet
    begin
      Names := TStringList.Create;  // files of the folder
      Names.OwnsObjects := False;  // the objects are sizes, not objects
      {$IFDEF WINDOWS}
      Names.CaseSensitive := False;  // Windows file names ignore case (also for letters such as accented ones)
      {$ELSE}
      Names.CaseSensitive := True;  // Linux file names are case-sensitive
      Names.UseLocale := False;  // compare the bytes, not by language rules
      {$ENDIF}
      if FindFirstUTF8(Dir + '*', faAnyFile, SR) = 0 then  // list the folder (nothing when it does not exist)
      try
        repeat
          if (SR.Attr and faDirectory) = 0 then  // files only, like FileExistsUTF8
            Names.AddObject(SR.Name, TObject(PtrInt(SR.Size)));  // name and size
        until FindNextUTF8(SR) <> 0;  // next entry
      finally
        FindCloseUTF8(SR);  // close the search
      end;
      Names.Sorted := True;  // sort once for fast lookups
      DestDirs.AddObject(Dir, Names);  // remember the folder
      DestDirs.Find(Dir, P);  // its position in the sorted list
    end;
    Names := TStringList(DestDirs.Objects[P]);  // files of the folder
    if Names.Find(ExtractFileName(Path), Q) then Result := PtrInt(Names.Objects[Q]);  // size of the file
  end;

  { Returns a free "name (1).ext" style name next to Dest: not on disk and not planned for another file. }
  function FreeName(const Dest: string): string;
  var
    N: Integer;  // N: number added to the name
    Ext, Base: string;  // Ext: extension; Base: path without extension
  begin
    Ext := ExtractFileExt(Dest);  // extension
    Base := Copy(Dest, 1, Length(Dest) - Length(Ext));  // path without extension
    N := 1;  // first number
    repeat
      Result := Base + ' (' + IntToStr(N) + ')' + Ext;  // try the "(1)" style name
      Inc(N);  // next number
    until (DestSize(Result) < 0) and (Taken.IndexOf(Result) < 0);  // stop at a name nobody uses
    Taken.Add(Result);  // reserve it
  end;

begin
  Dups := TStringList.Create;  // keys of pictures seen
  Taken := TStringList.Create;  // names planned for files
  Taken.Sorted := True;  // keep the list sorted
  Taken.CaseSensitive := False;  // ignore case
  Groups := TStringList.Create;  // destinations with counts
  Firsts := TStringList.Create;  // first item per destination
  DestDirs := TStringList.Create;  // destination folders listed so far
  DestDirs.OwnsObjects := True;  // the name lists are freed with it
  DestDirs.CaseSensitive := True;  // folders compare exactly
  DestDirs.UseLocale := False;  // compare the bytes, not by language rules
  DestDirs.Sorted := True;  // keep the list sorted
  try
    Dups.Sorted := True;  // keep the list sorted
    Dups.CaseSensitive := False;  // ignore case
    Groups.Sorted := True;  // keep the list sorted
    Groups.CaseSensitive := False;  // ignore case
    Firsts.Sorted := True;  // keep the list sorted
    Firsts.CaseSensitive := False;  // ignore case

    // pass 1: destination names, duplicates and per-destination counts
    for I := 0 to Items.Count - 1 do  // every item
    begin
      It := ItemAt(Items, I);  // current item
      It.DateKey := FormatDateTime('yyyy"/"mm"/"dd', It.CaptureTime);  // date used for job codes
      It.DestPath := ComputeDest(S, It, S.SeqNext + I, I + 1);  // planned destination
      It.ClashInfo := '';  // no clash information yet
      // the same photo found twice (copies in other folders, renamed copies):
      // identical size, capture time and camera
      Key := IntToStr(It.Size) + '|' + FloatToStr(It.CaptureTime) + '|' + It.Camera;  // key from size, capture time and camera
      if Dups.IndexOf(Key) >= 0 then  // the picture was seen before
        It.Status := isDuplicate  // mark it as a duplicate
      else
      begin
        Dups.Add(Key);  // remember the key
        It.Status := isNew;  // new file for now
        P := Groups.IndexOf(It.DestPath);  // find the destination in the list
        if P < 0 then
          begin
            Groups.AddObject(It.DestPath, TObject(PtrInt(1)));  // first use of this destination
            Firsts.AddObject(It.DestPath, TObject(PtrInt(It.Index)));  // remember the first item
          end
        else
          Groups.Objects[P] := TObject(PtrInt(PtrInt(Groups.Objects[P]) + 1));  // count another use of this destination
      end;
    end;

    for I := 0 to Groups.Count - 1 do Taken.Add(Groups[I]);  // every planned destination name is taken

    // pass 2: compare with what is already on disk
    for I := 0 to Items.Count - 1 do  // every item
    begin
      It := ItemAt(Items, I);  // current item
      if It.Status = isDuplicate then  // a duplicate keeps its status
      begin
        // with "Download duplicates as (1), (2) ..." the planned name already carries the number
        if S.RenameDuplicates and ((DestSize(It.DestPath) >= 0) or (Taken.IndexOf(It.DestPath) >= 0)) then
          It.DestPath := FreeName(It.DestPath)  // name is taken by a file or by another planned file
        else
          Taken.Add(It.DestPath);  // reserve the name for this duplicate
        Continue;  // duplicates are done
      end;
      if DestSize(It.DestPath) >= 0 then  // a file with the destination name exists
      begin
        // a .lrprev saved as .jpg never has the size of the original, so the name alone decides
        if S.IgnoreSizeCheck or (DestSize(It.DestPath) = It.Size) or LrPrevJpgOnly(S, It) then  // same size (or size check ignored)
          It.Status := isDownloaded  // already downloaded
        else
          begin
            It.Status := isNameClash;  // different file with the same name
            It.ClashInfo := 'a different file with this name already exists';  // reason
          end;
      end
      else
      begin
        P := Groups.IndexOf(It.DestPath);  // find the destination in the list
        if (P >= 0) and (PtrInt(Groups.Objects[P]) > 1) then  // used by more than one item
        begin
          It.Status := isNameClash;  // name clash
          J := PtrInt(Firsts.Objects[Firsts.IndexOf(It.DestPath)]);  // number of the first item with this destination
          if J = It.Index then  // this is the first one
            It.ClashInfo := 'same new name as other files'  // reason
          else if (J >= 1) and (J <= Items.Count) then  // first one is another item
            It.ClashInfo := 'same new name (' + ExtractFileName(It.DestPath) + ') as #' + IntToStr(J) +  // reason with the name and number of the other item
              ' ' + ItemAt(Items, J - 1).FullPath
          else
            It.ClashInfo := 'same new name as #' + IntToStr(J);  // reason with the number of the other item
        end;
      end;
      if S.AutoRenameClash and (It.Status = isNameClash) then  // clashes are renamed automatically
      begin
        It.Status := isNew;  // not a problem: shown as a new file that gets a new name
        J := 0;  // number of the first item with this destination (0 = not a clash between new files)
        P := Firsts.IndexOf(It.DestPath);  // find the destination in the list
        if (P >= 0) and (DestSize(It.DestPath) < 0) then J := PtrInt(Firsts.Objects[P]);  // clash only between new files
        if (J > 0) and (J = It.Index) then
          It.ClashInfo := ''  // the first of them keeps its name
        else
          It.DestPath := FreeName(It.DestPath);  // the others (or a file that meets an existing one) get "(1)", "(2)" ...
      end;
    end;
  finally
    DestDirs.Free;  // free the folder lists
    Taken.Free;  // free the list
    Dups.Free;  // free the list
    Groups.Free;  // free the list
    Firsts.Free;  // free the list
  end;
end;

{ ---- thumbnails ---- }

{ Turns a bitmap upright according to the EXIF orientation (2 to 8). }
procedure OrientBitmap(var Bmp: TBitmap; Orient: Integer);
var
  Nb: TBitmap;  // Nb: new bitmap
  X, Y, W, H, NW, NH, NX, NY: Integer;  // X, Y: source pixel; W, H: source size; NW, NH: new size; NX, NY: new pixel
begin
  if (Bmp = nil) or (Orient < 2) or (Orient > 8) then Exit;  // nothing to do
  W := Bmp.Width;  // width
  H := Bmp.Height;  // height
  if (W <= 0) or (H <= 0) then Exit;  // invalid size
  OrientDims(Orient, W, H, NW, NH);  // size after turning
  Nb := TBitmap.Create;  // create the new bitmap
  try
    Nb.SetSize(NW, NH);  // set its size
    for Y := 0 to H - 1 do  // every row
      for X := 0 to W - 1 do  // every column
      begin
        OrientPoint(Orient, W, H, X, Y, NX, NY);  // new position of the pixel
        Nb.Canvas.Pixels[NX, NY] := Bmp.Canvas.Pixels[X, Y];  // copy the pixel
      end;
  except
    Nb.Free;  // free the new bitmap on failure
    Exit;
  end;
  Bmp.Free;  // free the old bitmap
  Bmp := Nb;  // use the new bitmap
end;

{ appends a line to thumbnail.log in the settings folder (diagnostics for unreadable previews) }
procedure LogThumb(const Msg: string);
var
  FN, Line: string;  // FN: log file name; Line: text to write
  Strm: TFileStream;  // Strm: log file stream
begin
  if not LogEnabled then Exit;  // logging is off
  if LoggedMsgs = nil then  // first message of the session
  begin
    LoggedMsgs := TStringList.Create;  // list of the messages written so far
    LoggedMsgs.Sorted := True;  // keep it sorted for fast searching
    LoggedMsgs.CaseSensitive := True;  // compare exactly
  end;
  if LoggedMsgs.IndexOf(Msg) >= 0 then Exit;  // this message was written already
  if LoggedMsgs.Count < 20000 then LoggedMsgs.Add(Msg);  // remember it (the list is capped)
  try
    FN := ConfigDir + 'thumbnail.log';  // log file in the settings folder
    if FileExistsUTF8(FN) then  // log file exists
    begin
      if FileSizeUtf8(FN) > 200000 then Exit;  // stop when the log is large
      Strm := TFileStream.Create(FN, fmOpenWrite or fmShareDenyNone);  // open for appending
      Strm.Position := Strm.Size;  // go to the end
    end
    else
      Strm := TFileStream.Create(FN, fmCreate);  // create the log file
    try
      Line := FormatDateTime('hh:nn:ss', Now) + ' ' + Msg + LineEnding;  // time and message
      Strm.WriteBuffer(Line[1], Length(Line));  // write the line
    finally
      Strm.Free;  // close the file
    end;
  except
    // logging must never disturb the program
  end;
end;

type
  TBmpFileHdr = packed record  // BMP file header
    bfType: Word;  // BM signature
    bfSize, bfReserved, bfOffBits: LongWord;  // file size, reserved, offset of the pixels
  end;
  TBmpInfoHdr = packed record  // BMP info header
    biSize: LongWord;  // size of the header
    biWidth, biHeight: LongInt;  // width and height
    biPlanes, biBitCount: Word;  // planes and bits per pixel
    biCompression, biSizeImage: LongWord;  // compression and image size
    biXPels, biYPels: LongInt;  // resolution
    biClrUsed, biClrImportant: LongWord;  // colors
  end;

{ True when the plain TIFF picture has more pixels than W x H. }
function TiffRgbIsLarger(const FileName: string; W, H: Integer): Boolean;
var
  R: TTiffRgb;  // R: description of the plain picture
begin
  Result := FindTiffRgb(FileName, R) and (Int64(R.W) * R.H > Int64(W) * H);  // find the picture and compare the sizes
end;

{ Builds a thumbnail bitmap from the uncompressed picture of a TIFF or DNG file. }
function LoadTiffBitmap(const FileName: string; MaxSide: Integer; Bmp: TBitmap): Boolean;
var
  R: TTiffRgb;  // R: description of the plain picture
  Strm: TFileStream;  // Strm: the open file
  Ms: TMemoryStream;  // Ms: BMP built in memory
  FH: TBmpFileHdr;  // FH: BMP file header
  IH: TBmpInfoHdr;  // IH: BMP info header
  Sc: Double;  // Sc: scale factor
  NW, NH, X, Y, SX, SY, Bps, Hi, P, LineLen: Integer;  // NW, NH: thumbnail size; X, Y: pixel; SX, SY: source pixel; Bps: bytes per sample; Hi: index of the most significant byte; P: byte offset; LineLen: bytes per BMP line
  Row, Line: TBytes;  // Row: source row; Line: BMP line
  G: Byte;  // G: gray value
begin
  Result := False;  // assume failure
  Row := nil;  // release any old array
  Line := nil;  // release any old array
  if not FindTiffRgb(FileName, R) then Exit;  // find the plain picture
  Bps := R.Bits div 8;  // bytes per sample
  if Max(R.W, R.H) > MaxSide then Sc := MaxSide / Max(R.W, R.H) else Sc := 1;  // scale factor, never enlarge
  NW := Max(1, Round(R.W * Sc));  // thumbnail width
  NH := Max(1, Round(R.H * Sc));  // thumbnail height
  // index of the most significant byte of a sample
  if R.Big then Hi := 0 else Hi := Bps - 1;  // position of the most significant byte
  LineLen := ((NW * 3 + 3) div 4) * 4;  // BMP lines are padded to 4 bytes
  SetLength(Line, LineLen);  // reserve one line

  FH.bfType := $4D42;  // BM signature
  FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;  // file size
  FH.bfReserved := 0;  // reserved, must be zero
  FH.bfOffBits := SizeOf(FH) + SizeOf(IH);  // where the pixels start
  IH.biSize := SizeOf(IH);  // size of the info header
  IH.biWidth := NW;  // width
  IH.biHeight := NH;                 // positive height: rows are stored bottom-up
  IH.biPlanes := 1;  // one plane
  IH.biBitCount := 24;  // 24 bits per pixel
  IH.biCompression := 0;  // no compression
  IH.biSizeImage := LineLen * NH;  // size of the pixel data
  IH.biXPels := 2835;  // horizontal resolution (72 dpi)
  IH.biYPels := 2835;  // vertical resolution (72 dpi)
  IH.biClrUsed := 0;  // no palette
  IH.biClrImportant := 0;  // all colors important

  Ms := TMemoryStream.Create;  // stream for the BMP
  try
    try
      Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
      try
        Ms.WriteBuffer(FH, SizeOf(FH));  // write the file header
        Ms.WriteBuffer(IH, SizeOf(IH));  // write the info header
        for Y := NH - 1 downto 0 do  // BMP stores the bottom line first
        begin
          SY := Y * R.H div NH;  // source row
          if not ReadTiffRgbRow(Strm, R, SY, Row) then Exit;  // read the source row
          FillChar(Line[0], LineLen, 0);  // clear the line
          for X := 0 to NW - 1 do  // every thumbnail column
          begin
            SX := X * R.W div NW;  // source column
            P := SX * R.Spp * Bps + Hi;  // byte offset of the sample
            if R.Spp = 3 then  // three samples per pixel
            begin
              Line[X * 3 + 2] := Row[P];              // red
              Line[X * 3 + 1] := Row[P + Bps];        // green
              Line[X * 3] := Row[P + 2 * Bps];        // blue
            end
            else
            begin
              G := Row[P];  // gray sample
              if R.Photo = 0 then G := 255 - G;       // WhiteIsZero
              Line[X * 3] := G;  // blue
              Line[X * 3 + 1] := G;  // green
              Line[X * 3 + 2] := G;  // red
            end;
          end;
          Ms.WriteBuffer(Line[0], LineLen);  // write the line
        end;
      finally
        Strm.Free;  // close the file
      end;
      Ms.Position := 0;  // rewind
      Bmp.LoadFromStream(Ms);  // let the bitmap read it
      Result := (Bmp.Width > 0) and (Bmp.Height > 0);  // success when the picture is not empty
    except
      Result := False;  // failure
    end;
  finally
    Ms.Free;  // free the stream
  end;
end;

{ Chooses the JPEG decoding scale for a picture of W x H and a target box. }
function PickScale(W, H, Box: Integer): TJPEGScale;
var
  Ratio: Integer;  // Ratio: how much larger the picture is than the box
begin
  Ratio := Max(W, H) div Max(1, Box);  // ratio of the long side to the box
  if Ratio >= 8 then Result := jsEighth  // 8 or more: decode at 1/8 size
  else if Ratio >= 4 then Result := jsQuarter  // 4 or more: decode at 1/4 size
  else if Ratio >= 2 then Result := jsHalf  // 2 or more: decode at half size
  else Result := jsFullSize;  // otherwise full size
end;

const
  { Change when the decoders change so that thumbnails kept from an older version are rebuilt }
  ThumbCacheVersion = '3';  // version of the thumbnail cache (3: all file types, orientation in the key)
  ThumbCacheMaxBytes = 500 * 1024 * 1024;  // largest size of the thumbnail cache (about 40,000 photos)

{ Returns the file name of the cached thumbnail of an item. }
function ThumbCacheName(Item: TImageItem; Box: Integer): string;
begin
  // the orientation is part of the key, so a file that was turned upright never shows its old thumbnail
  Result := CacheDir + 'thumbcache' + PathDelim + MD5Print(MD5String(  // name from a hash of the version, path, size, date, orientation and box
    ThumbCacheVersion + '|' + LowerCase(Item.FullPath) + '|' + IntToStr(Item.Size) + '|' +
    FloatToStr(Item.FileTime) + '|' + IntToStr(Item.Orientation) + '|' + IntToStr(Box))) + '.jpg';
end;

type
  { One file of the thumbnail cache, for PruneThumbCache }
  TCacheFile = record
    Name: string;  // file name
    Size: Int64;  // size in bytes
    Time: LongInt;  // modification time (file date format)
  end;

{ Sort helper for PruneThumbCache: oldest first. }
procedure SortCacheFiles(var F: array of TCacheFile; Lo, Hi: Integer);
var
  I, J: Integer;  // I, J: positions moving toward each other
  Mid: LongInt;  // Mid: time of the middle element
  T: TCacheFile;  // T: swap helper
begin
  repeat
    I := Lo;
    J := Hi;
    Mid := F[(Lo + Hi) div 2].Time;  // pivot
    repeat
      while F[I].Time < Mid do Inc(I);
      while F[J].Time > Mid do Dec(J);
      if I <= J then
      begin
        T := F[I]; F[I] := F[J]; F[J] := T;  // swap
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if Lo < J then SortCacheFiles(F, Lo, J);  // sort the left part
    Lo := I;  // continue with the right part
  until I >= Hi;
end;

procedure PruneThumbCache;
var
  Dir: string;  // Dir: cache folder
  SR: TSearchRec;  // SR: directory entry
  F: array of TCacheFile;  // F: cache files
  N, I: Integer;  // N: number of files; I: loop counter
  Total: Int64;  // Total: bytes in the cache
begin
  try
    Dir := CacheDir + 'thumbcache' + PathDelim;  // cache folder
    F := nil;
    N := 0;
    Total := 0;
    if FindFirstUTF8(Dir + '*.jpg', faAnyFile, SR) = 0 then  // list the cache files
    try
      repeat
        if (SR.Attr and faDirectory) <> 0 then Continue;  // files only
        if N >= Length(F) then SetLength(F, Max(1024, N * 2));  // make room
        F[N].Name := SR.Name;
        F[N].Size := SR.Size;
        F[N].Time := SR.Time;
        Inc(Total, SR.Size);  // add its size
        Inc(N);
      until FindNextUTF8(SR) <> 0;
    finally
      FindCloseUTF8(SR);
    end;
    if Total <= ThumbCacheMaxBytes then Exit;  // small enough
    SortCacheFiles(F, 0, N - 1);  // oldest first
    I := 0;
    while (I < N) and (Total > ThumbCacheMaxBytes div 10 * 8) do  // delete down to 80%, so this does not run every time
    begin
      if DeleteFileUTF8(Dir + F[I].Name) then Dec(Total, F[I].Size);  // delete the oldest file
      Inc(I);
    end;
  except
    // the cache is only a speed-up
  end;
end;

{ Loads the cached thumbnail of an item; False when there is none. }
function LoadCachedThumb(Item: TImageItem; Box: Integer): Boolean;
var
  FN: string;  // FN: cache file name
  J: TJPEGImage;  // J: the cached JPEG
  B: TBitmap;  // B: bitmap for the thumbnail
begin
  Result := False;  // assume failure
  FN := ThumbCacheName(Item, Box);  // cache file name
  if not FileExistsUTF8(FN) then Exit;  // no cache file
  J := TJPEGImage.Create;  // create the JPEG
  try
    try
      J.LoadFromFile(FN);  // read the cache file
      if J.Empty then Exit;  // empty picture
      B := TBitmap.Create;  // create the bitmap
      B.SetSize(J.Width, J.Height);  // set its size
      B.Canvas.Draw(0, 0, J);  // draw the JPEG on it
      Item.Thumb := B;  // give the bitmap to the item
      Result := True;  // success
    except
      Result := False;  // failure
    end;
  finally
    J.Free;  // free the JPEG
  end;
end;

{ Saves the thumbnail of an item in the cache. }
procedure SaveCachedThumb(Item: TImageItem; Box: Integer);
var
  J: TJPEGImage;  // J: JPEG made from the thumbnail
begin
  try
    ForceDirectoriesUTF8(CacheDir + 'thumbcache');  // make sure the cache folder exists
    J := TJPEGImage.Create;  // create the JPEG
    try
      J.Assign(Item.Thumb);  // copy the thumbnail
      J.CompressionQuality := 88;  // quality 88
      J.SaveToFile(ThumbCacheName(Item, Box));  // save the cache file
    finally
      J.Free;  // free the JPEG
    end;
  except
    // the cache is only a speed-up
  end;
end;

{ 1 = TIFF, 2 = JPEG, 3 = PNG, 4 = BMP, 5 = GIF, 6 = WebP, 7 = HEIC/AVIF (ISO base media),
  0 = anything else, judged by the first bytes of the file }
function SniffFileKind(const FileName: string): Integer;
var
  F: TFileStream;  // F: the open file
  B: array[0..11] of Byte;  // B: first 12 bytes
begin
  Result := 0;  // unknown by default
  {$PUSH}{$HINTS OFF}FillChar(B, SizeOf(B), 0);{$POP}  // clear the buffer
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
    try
      if F.Read(B[0], 12) < 4 then Exit;  // too short
    finally
      F.Free;
    end;
    if ((B[0] = $49) and (B[1] = $49) and (B[2] = $2A) and (B[3] = 0)) or  // TIFF signature (II or MM)
       ((B[0] = $4D) and (B[1] = $4D) and (B[2] = 0) and (B[3] = $2A)) then
      Result := 1  // TIFF
    else if (B[0] = $FF) and (B[1] = $D8) then  // JPEG signature
      Result := 2  // JPEG
    else if (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and (B[3] = $47) then  // PNG signature
      Result := 3  // PNG
    else if (B[0] = $42) and (B[1] = $4D) then  // BM signature
      Result := 4  // BMP
    else if (B[0] = $47) and (B[1] = $49) and (B[2] = $46) and (B[3] = $38) then  // GIF signature
      Result := 5  // GIF
    else if (B[0] = $52) and (B[1] = $49) and (B[2] = $46) and (B[3] = $46) and  // RIFF container with WEBP
            (B[8] = $57) and (B[9] = $45) and (B[10] = $42) and (B[11] = $50) then
      Result := 6  // WebP
    else if (B[4] = $66) and (B[5] = $74) and (B[6] = $79) and (B[7] = $70) then  // ftyp box
      Result := 7;  // HEIC or AVIF
  except
    Result := 0;  // unknown
  end;
end;

{ The first bytes of a file as hex text, for the log (shows what a file that will not open really is) }
function HeaderNote(const FileName: string): string;
var
  F: TFileStream;  // F: the open file
  B: array[0..11] of Byte;  // B: first 12 bytes
  N, I: Integer;  // N: bytes read; I: loop counter
begin
  Result := '';  // empty by default
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
    try
      {$PUSH}{$HINTS OFF}N := F.Read(B[0], 12);{$POP}  // read the first bytes
    finally
      F.Free;  // close the file
    end;
    for I := 0 to N - 1 do  // every byte
      Result := Result + IntToHex(B[I], 2) + ' ';  // add its hex value
    Result := ' [file starts with: ' + Trim(Result) + ']';  // build the note

  except
    Result := '';  // no note on failure
  end;
end;

{ True if the file starts with plain text instead of picture data (for example a link stub that
  Git leaves on Windows) }
function LooksLikeText(const FileName: string): Boolean;
var
  F: TFileStream;  // F: the open file
  B: array[0..11] of Byte;  // B: first 12 bytes
  N, I: Integer;  // N: bytes read; I: loop counter
begin
  Result := False;  // not text by default
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
    try
      {$PUSH}{$HINTS OFF}N := F.Read(B[0], 12);{$POP}  // read the first bytes
    finally
      F.Free;  // close the file
    end;
    Result := N >= 4;  // at least four bytes are needed
    for I := 0 to N - 1 do
      if ((B[I] < 32) and not (B[I] in [9, 10, 13])) or (B[I] > 126) then Result := False;  // control characters (except tab, LF and CR) and bytes above 126 are not text
  except
    Result := False;  // not text on failure
  end;
end;

{ PNG, BMP or GIF content under another file extension: the graphic class is chosen from the content }
function LoadByContent(const FileName: string; Kind: Integer): TPicture;
var
  FS: TFileStream;  // FS: the open file
  Fix: TMemoryStream;  // Fix: copy of a PNG with repaired checksums
  Ext: string;  // Ext: extension that selects the loader
  Retry: Boolean;  // Retry: True when the first PNG attempt failed
  FirstErr: string;  // FirstErr: text of that first error
begin
  case Kind of
    3: Ext := '.png';  // PNG
    4: Ext := '.bmp';  // BMP
  else
    Ext := '.gif';  // GIF
  end;
  Result := TPicture.Create;  // new picture
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
    try
      Retry := False;  // no retry yet
      FirstErr := '';  // no error yet
      try
        Result.LoadFromStreamWithFileExt(FS, Ext);  // load with the matching loader
      except
        on E: Exception do
        begin
          if Kind <> 3 then raise;  // only PNG files are repaired
          Retry := True;  // try again after the repair
          FirstErr := E.ClassName + ' ' + E.Message;  // remember the first error
        end;
      end;
      if Retry then
      begin
        // PNG with wrong chunk checksums (oscilloscope screenshots): repair a copy and retry
        Fix := TMemoryStream.Create;
        try
          LoadFileToMemory(FileName, Fix);  // read the file into memory
          if not RepairPngCrc(Fix) then raise Exception.Create(FirstErr);  // repair the checksums or report the first error
          Fix.Position := 0;  // rewind
          Result.Clear;  // clear the picture
          Result.LoadFromStreamWithFileExt(Fix, Ext);  // load the repaired copy
        finally
          Fix.Free;  // free the copy
        end;
      end;
    finally
      FS.Free;  // close the file
    end;
  except
    Result.Free;  // free the picture on failure
    raise;
  end;
end;

{ WebP picture (see uWebP) -> thumbnail; kept in the thumbnail cache because decoding is slow }
function TryWebPThumb(Item: TImageItem; Box: Integer; Cache: Boolean): Boolean;
var
  Bmp: TBitmap;  // Bmp: thumbnail bitmap
  Err: string;  // Err: reason of a failure
begin
  Result := False;  // assume failure
  Bmp := TBitmap.Create;  // create the bitmap
  try
    Err := '';  // no error yet
    if LoadWebPThumb(Item.FullPath, Box, Bmp, Err) then  // decode the picture
    begin
      Item.Thumb := Bmp;  // give the bitmap to the item
      Bmp := nil;  // do not free it below
      if Cache then SaveCachedThumb(Item, Box);  // save in the cache when asked
      Result := True;  // success
    end
    else
      LogThumb(Item.FullPath + ': WebP picture could not be decoded: ' + Err);  // write the reason to the log
  finally
    Bmp.Free;  // free the bitmap if it was not used
  end;
end;

{ Creates the thumbnail of an item from a JPEG, raw preview, TIFF, HEIC, WebP or other picture. }
var
  LastVideoErr: string = '';  // last reason a video frame could not be made (logged once)

{ Returns the .thm file that belongs to a video (same name, camera thumbnail), or ''. }
function FindVideoSidecar(const VideoPath: string): string;
var
  Base: string;  // Base: video path without its extension
begin
  Result := '';  // none found yet
  Base := ChangeFileExt(VideoPath, '');  // path without extension
  if FileExistsUTF8(Base + '.thm') then Result := Base + '.thm'  // lower case extension
  else if FileExistsUTF8(Base + '.THM') then Result := Base + '.THM';  // upper case extension (Linux is case sensitive)
end;

{ True when the row (Horiz) or column of B at position At is close to black (sampled). }
function LineIsDark(B: TBitmap; At: Integer; Horiz: Boolean): Boolean;
var
  I, N, X, Y, Sum: Integer;  // I: sample; N: samples; X, Y: pixel; Sum: brightness total
  C: TColor;  // C: pixel color
begin
  N := 16;  // samples along the line
  Sum := 0;
  for I := 0 to N - 1 do
  begin
    if Horiz then
    begin
      X := (B.Width - 1) * I div (N - 1);  // spread along the row
      Y := At;
    end
    else
    begin
      X := At;
      Y := (B.Height - 1) * I div (N - 1);  // spread along the column
    end;
    C := ColorToRGB(B.Canvas.Pixels[X, Y]);  // pixel color
    Sum := Sum + Red(C) + Green(C) + Blue(C);  // add its brightness
  end;
  Result := Sum < N * 3 * 24;  // average channel below 24: black bar
end;

{ Makes a bitmap from a small embedded thumbnail (EXIF thumbnail, small RAW preview). Some
  cameras store it in a fixed shape (160x120) and add black bars when the photo (RefW x RefH)
  has another shape: those bars are cut off. nil when it cannot be used: smaller than Box, or
  of another shape without bars (cropped or squeezed by the camera). }
function SmallThumbBitmap(Src: TGraphic; RefW, RefH, Box: Integer): TBitmap;
var
  B, Cut: TBitmap;  // B: the whole thumbnail; Cut: without bars
  W, H, CW, CH, Off: Integer;  // W, H: thumbnail size; CW, CH: size without bars; Off: bar thickness
begin
  Result := nil;
  W := Src.Width;
  H := Src.Height;
  if (W <= 0) or (H <= 0) or (Max(W, H) < Box) then Exit;  // too small for the box
  B := TBitmap.Create;
  try
    B.PixelFormat := pf24bit;  // plain RGB
    B.SetSize(W, H);
    B.Canvas.Draw(0, 0, Src);  // decode into the bitmap
    CW := W;  // assume no bars
    CH := H;
    if (RefW > 0) and (RefH > 0) and (Abs(Int64(W) * RefH - Int64(H) * RefW) * 50 > Int64(W) * RefH) then  // shapes differ by more than 2%
    begin
      if Int64(RefW) * H > Int64(RefH) * W then  // the photo is wider: bars at top and bottom
      begin
        CH := Max(1, Round(W * RefH / RefW));  // picture height inside the bars
        Off := (H - CH) div 2;  // bar thickness
        if (Off >= 2) and not (LineIsDark(B, Off div 2, True) and LineIsDark(B, H - 1 - Off div 2, True)) then Exit;  // no bars: shape changed some other way
      end
      else
      begin
        CW := Max(1, Round(H * RefW / RefH));  // picture width inside the bars
        Off := (W - CW) div 2;  // bar thickness
        if (Off >= 2) and not (LineIsDark(B, Off div 2, False) and LineIsDark(B, W - 1 - Off div 2, False)) then Exit;  // no bars
      end;
      if Off >= 2 then  // cut the bars off
      begin
        if Max(CW, CH) < Box then Exit;  // too small without the bars
        Cut := TBitmap.Create;
        Cut.PixelFormat := pf24bit;
        Cut.SetSize(CW, CH);
        Cut.Canvas.CopyRect(Rect(0, 0, CW, CH), B.Canvas,
          Rect((W - CW) div 2, (H - CH) div 2, (W - CW) div 2 + CW, (H - CH) div 2 + CH));  // the middle part
        Result := Cut;
        Exit;
      end;
    end;
    Result := B;  // use the whole thumbnail
    B := nil;  // do not free it below
  finally
    B.Free;
  end;
end;

procedure EnsureThumbCore(Item: TImageItem; Box: Integer);
var
  Heavy: Boolean;  // Heavy: True for types that are slow to decode
  Ext: string;  // Ext: file extension
  Jpg: TJPEGImage;  // Jpg: JPEG being decoded
  Pic: TPicture;  // Pic: generic picture
  Mem: TMemoryStream;  // Mem: memory stream with an embedded preview
  G: TGraphic;  // G: graphic that is drawn into the thumbnail
  W, H, NW, NH, Rank, Attempt: Integer;  // W, H: picture size; NW, NH: thumbnail size; Rank: preview number; Attempt: decode attempt
  Deep: Boolean;  // Deep: True when the whole file is searched for previews
  Sc: Double;  // Sc: scale factor
  Bmp: TBitmap;  // Bmp: thumbnail bitmap
  TiffErr: string;  // TiffErr: reason of a TIFF failure
  Sniff: Integer;  // Sniff: file kind from the first bytes
  VBmp: TBitmap;  // VBmp: frame of a video supplied by the operating system
  VErr, Side: string;  // VErr: reason the system gave no frame; Side: sidecar file next to a video
  IsPng: Boolean;  // IsPng: True when a video cover is a PNG
  LrInfo: TLrPrevInfo;  // LrInfo: header values of a Lightroom preview file
  LrErr: string;  // LrErr: reason a Lightroom preview file could not be read
  Small: TBitmap;  // Small: bitmap made from a small embedded thumbnail
  RefW, RefH: Integer;  // RefW, RefH: size of the photo (or its largest preview), for the shape check
  K: Integer;  // K: smallest preview side wanted
begin
  Small := nil;  // nothing created yet
  W := 0;  // no width yet
  H := 0;  // no height yet
  Deep := True;  // search the whole file
  TiffErr := '';  // no TIFF error yet
  if Item.ThumbTried then Exit;  // already tried
  Item.ThumbTried := True;  // remember the attempt
  Ext := LowerCase(ExtractFileExt(Item.FileName));  // extension in lower case
  // slow-to-decode types are kept in a small on-disk cache
  Heavy := (Pos(';' + Ext + ';', HeicExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0) or  // HEIC, TIFF, DNG and WebP are slow to decode
    (Ext = '.webp') or (Pos(';' + Ext + ';', VideoExts) > 0);  // so is asking the system for a video frame
  // every thumbnail is kept in the disk cache: reading one small file from the cache folder is
  // much faster than reading the photo again from a hard disk, a memory card or a network share
  if LoadCachedThumb(Item, Box) then Exit;  // use the cache
  VBmp := nil;  // nothing created yet
  Jpg := nil;  // nothing created yet
  Pic := nil;  // nothing created yet
  Mem := nil;  // nothing created yet
  G := nil;  // nothing created yet
  Bmp := nil;  // nothing created yet
  try
    try
      if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') then
      begin
        Sniff := SniffFileKind(Item.FullPath);  // kind of file from its content
        if Sniff in [3, 4, 5] then  // PNG, BMP or GIF
        begin
          // not a JPEG at all: a PNG, BMP or GIF with a .jpg name
          Pic := LoadByContent(Item.FullPath, Sniff);  // load by content
          G := Pic.Graphic;  // graphic of the picture
        end
        else if Sniff = 6 then
        begin
          // a WebP picture with another name
          if TryWebPThumb(Item, Box, False) then Exit;  // use the WebP decoder
        end
        else if Sniff = 7 then
        begin
          Pic := TPicture.Create;  // generic picture for the HEIC decoder
          if LoadHeicPicture(Item.FullPath, Pic, Box * 2, True) then  // decode the HEIC or AVIF file
            G := Pic.Graphic  // take its graphic
          else
            LogThumb(Item.FullPath + ': HEIC/AVIF file with a wrong extension could not be decoded: ' + HeicLastError);  // log the reason
        end
        else if Sniff = 1 then
        begin
          Bmp := TBitmap.Create;  // bitmap for the TIFF reader
          if LoadTiffThumb(Item.FullPath, Box, Bmp, TiffErr) then  // decode the TIFF
          begin
            Item.Thumb := Bmp;  // give the bitmap to the item
            Bmp := nil;  // do not free it below
            Exit;
          end;
          FreeAndNil(Bmp);  // free the bitmap
          LogThumb(Item.FullPath + ': this is a TIFF file with a wrong extension (' + TiffErr + ')');  // log the reason
        end
        else
        begin
          // fast path: the small thumbnail the camera stored in the EXIF data (first 64 KB of
          // the file, about 15 times faster than decoding the photo, more from a memory card)
          Mem := TMemoryStream.Create;  // memory for the EXIF thumbnail
          if ExtractExifThumb(Item.FullPath, Mem, W, H, RefW, RefH) then
          begin
            Jpg := TJPEGImage.Create;  // create the JPEG
            try
              Mem.Position := 0;  // rewind
              Jpg.LoadFromStream(Mem);  // decode the thumbnail
              Small := SmallThumbBitmap(Jpg, RefW, RefH, Box);  // check its size and shape, cut black bars
            except
              FreeAndNil(Small);  // a broken thumbnail: decode the photo below
            end;
            FreeAndNil(Jpg);  // done with the JPEG
          end;
          if Small <> nil then
            G := Small  // use the EXIF thumbnail
          else
          begin
            // the photo itself, decoded at reduced size
            Jpg := TJPEGImage.Create;  // create the JPEG
            if ReadJpegDims(Item.FullPath, W, H) then  // read the picture size
              Jpg.Scale := PickScale(W, H, Box)  // choose the decoding scale
            else
              Jpg.Scale := jsQuarter;  // quarter size when the size is unknown
            Jpg.Performance := jpBestSpeed;  // fastest decoding
            Jpg.LoadFromFile(Item.FullPath);  // load the file
            G := Jpg;  // use it as the graphic
          end;
        end;
      end
      else if (Pos(';' + Ext + ';', RawExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0) then
      begin
        // RAW, TIFF and DNG: use an embedded JPEG preview when there is one. TIFF and
        // DNG files are not searched beyond the first 4 MB (they can be very large).
        Deep := Pos(';' + Ext + ';', TiffExts) = 0;  // TIFF and DNG are not searched completely
        Mem := TMemoryStream.Create;  // memory for the preview
        for Rank := 0 to 2 do  // try up to three previews
        begin
          Mem.Clear;  // empty the memory
          // RAW: the smallest preview that is big enough comes first (a 160 to 1600 pixel preview
          // decodes far faster than a full-size one). TIFF/DNG keep the largest first, because
          // TiffRgbIsLarger compares it with the plain picture in the file.
          if Deep then K := Box else K := 0;  // smallest long side wanted
          if not ExtractEmbeddedJpegEx(Item.FullPath, Rank, Deep, K, Mem, W, H, RefW, RefH) then Break;  // extract the next preview
          // the plain image in the file is bigger than this preview: build the thumbnail from it
          if (not Deep) and TiffRgbIsLarger(Item.FullPath, W, H) then Break;  // use the plain picture instead of a smaller preview
          // attempt 0: reduced-size fast decode; attempt 1: decoder defaults
          for Attempt := 0 to 1 do
          begin
            Mem.Position := 0;  // rewind
            Jpg := TJPEGImage.Create;  // create the JPEG
            try
              if Attempt = 0 then
              begin  // reduced-size decode
                Jpg.Scale := PickScale(W, H, Box);  // choose the decoding scale
                Jpg.Performance := jpBestSpeed;  // fastest decoding
              end;
              Jpg.LoadFromStream(Mem);  // decode the preview
              G := Jpg;  // use it as the graphic
              Break;  // stop trying
            except
              on E: Exception do
              begin
                LogThumb(Item.FullPath + ': preview #' + IntToStr(Rank) + ' (' + IntToStr(W) +  // log the failure
                  'x' + IntToStr(H) + ') attempt ' + IntToStr(Attempt) + ' failed: ' +
                  E.ClassName + ' ' + E.Message);
                FreeAndNil(Jpg);  // free the failed JPEG
              end;
            end;
          end;
          if (G <> nil) and Deep and (Max(W, H) < Max(RefW, RefH)) then  // a smaller preview than the largest one
          begin
            Small := SmallThumbBitmap(Jpg, RefW, RefH, Box);  // check its size and shape, cut black bars
            FreeAndNil(Jpg);  // done with the JPEG
            G := Small;  // nil: try the next preview
          end;
          if G <> nil then Break;  // stop when a preview worked
        end;
        if (G = nil) and (not Deep) then
        begin
          // TIFF / DNG without a usable JPEG: build the thumbnail from the image data itself
          Bmp := TBitmap.Create;  // bitmap for the plain picture
          if LoadTiffBitmap(Item.FullPath, Box, Bmp) then  // decode the plain picture
          begin
            if Pos(';' + Ext + ';', HeicExts) = 0 then OrientBitmap(Bmp, Item.Orientation);  // turn it upright (HEIC decoders do that themselves)
            Item.Thumb := Bmp;  // give the bitmap to the item
            Bmp := nil;  // do not free it below
            if Heavy then SaveCachedThumb(Item, Box);  // keep slow thumbnails in the cache
            Exit;
          end;
          FreeAndNil(Bmp);  // free the bitmap
          // compressed or 1-bit TIFF (scans, LZW, fax ...): the general TIFF reader
          Bmp := TBitmap.Create;  // bitmap for the general TIFF reader
          TiffErr := '';  // no error yet
          if LoadTiffThumb(Item.FullPath, Box, Bmp, TiffErr) then  // decode with the general TIFF reader
          begin
            if Pos(';' + Ext + ';', HeicExts) = 0 then OrientBitmap(Bmp, Item.Orientation);  // turn it upright
            Item.Thumb := Bmp;  // give the bitmap to the item
            Bmp := nil;  // do not free it below
            if Heavy then SaveCachedThumb(Item, Box);  // keep slow thumbnails in the cache
            Exit;
          end;
          FreeAndNil(Bmp);  // free the bitmap
        end;
        if G = nil then
          LogThumb(Item.FullPath + ': no usable preview or thumbnail image found' +  // log that nothing usable was found
            IfThen(TiffErr <> '', ' (' + TiffErr + ')', ''));  // add the TIFF reason when there is one
      end
      else if (Ext = '.png') or (Ext = '.bmp') or (Ext = '.gif') then
      begin
        Sniff := SniffFileKind(Item.FullPath);  // kind of file from its content
        if Sniff = 1 then  // TIFF
        begin
          // a TIFF with a .png/.bmp name
          Bmp := TBitmap.Create;  // bitmap for the TIFF reader
          if LoadTiffThumb(Item.FullPath, Box, Bmp, TiffErr) then  // decode the TIFF
          begin
            Item.Thumb := Bmp;  // give the bitmap to the item
            Bmp := nil;  // do not free it below
            Exit;
          end;
          FreeAndNil(Bmp);  // free the bitmap
          LogThumb(Item.FullPath + ': this is a TIFF file with a wrong extension (' + TiffErr + ')');  // log the reason
        end
        else if Sniff = 2 then
        begin
          // a JPEG with a .png/.bmp name
          Jpg := TJPEGImage.Create;  // create the JPEG
          Jpg.LoadFromFile(Item.FullPath);  // load the file
          G := Jpg;  // use it as the graphic
        end
        else if Sniff in [3, 4, 5] then
        begin
          // the content decides, not the extension (for example a PNG named .bmp)
          Pic := LoadByContent(Item.FullPath, Sniff);  // load by content
          G := Pic.Graphic;  // graphic of the picture
        end
        else if Sniff = 6 then
        begin
          // a WebP picture with another name
          if TryWebPThumb(Item, Box, False) then Exit;  // use the WebP decoder
        end
        else if Sniff = 7 then
        begin
          Pic := TPicture.Create;  // generic picture for the HEIC decoder
          if LoadHeicPicture(Item.FullPath, Pic, Box * 2, True) then  // decode the HEIC or AVIF file
            G := Pic.Graphic  // take its graphic
          else
            LogThumb(Item.FullPath + ': HEIC/AVIF file with a wrong extension could not be decoded: ' + HeicLastError);  // log the reason
        end
        else
        begin
          Pic := TPicture.Create;  // generic picture
          Pic.LoadFromFile(Item.FullPath);  // load the file
          G := Pic.Graphic;  // take its graphic
        end;
      end
      else if Ext = '.webp' then
      begin
        Sniff := SniffFileKind(Item.FullPath);  // kind of file from its content
        if Sniff in [3, 4, 5] then  // PNG, BMP or GIF
        begin
          Pic := LoadByContent(Item.FullPath, Sniff);       // the content decides, not the name
          G := Pic.Graphic;  // graphic of the picture
        end
        else if Sniff = 2 then
        begin
          Jpg := TJPEGImage.Create;  // create the JPEG
          Jpg.Scale := jsQuarter;  // quarter size
          Jpg.Performance := jpBestSpeed;  // fastest decoding
          Jpg.LoadFromFile(Item.FullPath);  // load the file
          G := Jpg;  // use it as the graphic
        end
        else if TryWebPThumb(Item, Box, Heavy) then  // WebP: decode with the WebP decoder
          Exit;
      end
      else if Pos(';' + Ext + ';', VideoExts) > 0 then
      begin
        // video: first a frame from the operating system (Windows Shell, or ffmpeg on Linux) ...
        VBmp := TBitmap.Create;  // bitmap for the frame
        if LoadVideoThumb(Item.FullPath, Box, VBmp, VErr) then
          G := VBmp  // use the frame as the graphic
        else
        begin
          if VErr <> LastVideoErr then  // log a given reason only once, not for every video
          begin
            LastVideoErr := VErr;  // remember the reason
            LogThumb(Item.FullPath + ': no system thumbnail (' + VErr + '); trying the cover or .thm file');  // log it
          end;
          // ... then a cover picture stored in the file, or a .thm file next to it
          Mem := TMemoryStream.Create;  // memory for the cover
          if ExtractMovieCover(Item.FullPath, Mem, IsPng) then
          begin
            Mem.Position := 0;  // rewind
            if IsPng then
            begin
              Pic := TPicture.Create;  // generic picture
              Pic.PNG.LoadFromStream(Mem);  // read the PNG cover
              G := Pic.Graphic;  // take its graphic
            end
            else
            begin
              Jpg := TJPEGImage.Create;  // create the JPEG
              Jpg.LoadFromStream(Mem);  // read the JPEG cover
              G := Jpg;  // use it as the graphic
            end;
          end
          else
          begin
            Side := FindVideoSidecar(Item.FullPath);  // .thm file with the same name
            if Side <> '' then
            begin
              Jpg := TJPEGImage.Create;  // create the JPEG
              Jpg.LoadFromFile(Side);  // read the .thm file (a small JPEG)
              G := Jpg;  // use it as the graphic
            end;
          end;
        end;
      end
      else if Pos(';' + Ext + ';', LrPrevExts) > 0 then
      begin
        // Lightroom preview file: the JPEG of its largest level (already upright)
        Mem := TMemoryStream.Create;  // memory for the JPEG
        if LrPrevExtract(Item.FullPath, Mem, LrInfo, LrErr) then
        begin
          Jpg := TJPEGImage.Create;  // create the JPEG
          Jpg.LoadFromStream(Mem);  // decode the preview
          G := Jpg;  // use it as the graphic
        end
        else
          LogThumb(Item.FullPath + ': Lightroom preview could not be read: ' + LrErr);  // log the reason
      end
      else if Pos(';' + Ext + ';', HeicExts) > 0 then
      begin
        // HEIC / HEIF / AVIF: bundled decoder (see uHeic); the placeholder stays if it cannot decode
        Pic := TPicture.Create;  // generic picture for the HEIC decoder
        if LoadHeicPicture(Item.FullPath, Pic, Box * 2, True) then  // decode the HEIC or AVIF file
          G := Pic.Graphic  // take its graphic
        else if HeicEnabled then
          LogThumb(Item.FullPath + ': HEIC/AVIF decode failed: ' + HeicLastError)  // log the reason
        else
          LogThumb(Item.FullPath + ': HEIC preview is not compiled in');  // log the reason
      end;
      if G = nil then Exit;  // no graphic: leave the placeholder
      if G.Empty then  // empty picture
      begin
        LogThumb(Item.FullPath + ': the decoder returned an empty picture (file size ' + Item.SizeText + ')');  // log the reason
        Exit;
      end;
      W := G.Width;  // picture width
      H := G.Height;  // picture height
      if (W <= 0) or (H <= 0) then Exit;  // invalid size
      Sc := Box / Max(W, H);  // scale factor to fit the box
      if Sc > 1 then Sc := 1;  // never enlarge
      NW := Max(1, Round(W * Sc));  // thumbnail width
      NH := Max(1, Round(H * Sc));  // thumbnail height
      Bmp := TBitmap.Create;  // create the thumbnail bitmap
      Bmp.SetSize(NW, NH);  // set its size
      Bmp.Canvas.StretchDraw(Rect(0, 0, NW, NH), G);  // draw the picture scaled
      // HEIC decoders normally apply the file's own rotation; HeicExtraOrientation checks that
      if Pos(';' + Ext + ';', HeicExts) = 0 then
        OrientBitmap(Bmp, Item.Orientation)  // turn it upright
      else
        OrientBitmap(Bmp, HeicExtraOrientation(Item.FullPath, W, H, Item.Orientation));  // turn it upright after the decoder's own rotation
      Item.Thumb := Bmp;  // give the bitmap to the item
      Bmp := nil;  // do not free it below
      SaveCachedThumb(Item, Box);  // keep the thumbnail in the cache
    except
      on E: Exception do
        if (Pos('Wrong image format', E.Message) > 0) and LooksLikeText(Item.FullPath) then  // an unreadable text file
          LogThumb(Item.FullPath + ': not an image (text file)' + HeaderNote(Item.FullPath))  // log that it is a text file
        else
          LogThumb(Item.FullPath + ': ' + E.ClassName + ' ' + E.Message + HeaderNote(Item.FullPath));  // log the error with the first bytes
    end;
  finally
    Bmp.Free;  // free the bitmap
    VBmp.Free;  // free the video frame
    Jpg.Free;  // free the JPEG
    Pic.Free;  // free the picture
    Mem.Free;  // free the preview memory
    Small.Free;  // free the small thumbnail bitmap
  end;
end;

{ ---- file copy ---- }

{ True for file types that are slow to decode. }
function ThumbIsHeavy(const FileName: string): Boolean;
var
  Ext: string;  // Ext: file extension
begin
  Ext := LowerCase(ExtractFileExt(FileName));  // extension in lower case
  Result := (Pos(';' + Ext + ';', HeicExts) > 0) or (Pos(';' + Ext + ';', TiffExts) > 0) or  // HEIC, TIFF, DNG and WebP are slow
    (Ext = '.webp') or (Pos(';' + Ext + ';', VideoExts) > 0);  // so are video frames
end;

{ Frees the thumbnail of an item so that it is made again when needed. }
procedure ReleaseThumb(Item: TImageItem);
begin
  if ThumbLru <> nil then ThumbLru.Remove(Item);  // remove the item from the thumbnail list
  FreeAndNil(Item.Thumb);  // free the thumbnail
  Item.ThumbTried := False;  // allow a new attempt
end;

{ Makes the thumbnail of an item and keeps track of the newest ones. }
procedure EnsureThumb(Item: TImageItem; Box: Integer);
var
  Old: TImageItem;  // Old: oldest item with a thumbnail
begin
  if Item.ThumbTried then Exit;  // already tried
  EnsureThumbCore(Item, Box);  // create the thumbnail
  if Item.Thumb = nil then Exit;  // no thumbnail
  if ThumbLru = nil then ThumbLru := TList.Create;  // create the list on first use
  ThumbLru.Add(Item);  // add the item to the list
  while ThumbLru.Count > Max(300, ThumbKeepMax * 160 div Max(160, Box)) do  // too many thumbnails kept (fewer when they are larger)
  begin
    Old := TImageItem(ThumbLru[0]);  // oldest item
    ReleaseThumb(Old);  // free its thumbnail
  end;
end;

function LrPrevJpgOnly(S: TAppSettings; Item: TImageItem): Boolean;
begin
  Result := S.LrPrevAsJpg and (not S.LrPrevKeepBoth) and  // .jpg wanted instead of the .lrprev file
    (Pos(';' + LowerCase(ExtractFileExt(Item.FileName)) + ';', LrPrevExts) > 0);  // and this is a .lrprev file
end;

function SaveLrPrevJpg(const Src, Dst: string; Verify: Boolean; out Hash: string;
  out Err: string): TCopyResult;
var
  Mem: TMemoryStream;  // Mem: the preview picture
  Info: TLrPrevInfo;  // Info: header values of the preview file
begin
  Result := crFailed;  // assume failure
  Hash := '';  // no hash yet
  Err := '';  // no error yet
  Mem := TMemoryStream.Create;  // buffer for the picture
  try
    try
      if not LrPrevExtract(Src, Mem, Info, Err) then Exit;  // not a usable .lrprev file (Err tells why)
      Mem.SaveToFile(Dst);  // write the .jpg
      Hash := MD5Print(MD5Buffer(Mem.Memory^, Mem.Size));  // MD5 of the picture
      if Verify and (HashOfFile(Dst) <> Hash) then  // the file on disk differs
      begin
        DeleteFileUTF8(Dst);  // remove the bad file
        Err := 'the .jpg read back differs from the preview picture';  // reason
        Result := crVerifyFailed;  // report it
        Exit;
      end;
      Result := crOk;  // success
    except
      on E: Exception do
      begin
        Err := E.Message;  // reason
        if FileExistsUTF8(Dst) then DeleteFileUTF8(Dst);  // no half-written file
      end;
    end;
  finally
    Mem.Free;  // free the buffer
  end;
end;

{ Copies a file in 256 KB blocks; False (and no destination file) on failure. }
function CopyFileStream(const Src, Dst: string): Boolean;
const
  BufSize = 262144;  // size of the copy buffer
var
  FI, FO: TFileStream;  // FI: source file; FO: destination file
  Buf: Pointer;  // Buf: copy buffer
  N: LongInt;  // N: bytes read
begin
  Result := False;  // assume failure
  GetMem(Buf, BufSize);  // reserve the buffer
  try
    try
      FI := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);  // open the source
      try
        FO := TFileStream.Create(Dst, fmCreate);  // create the destination
        try
          repeat
            N := FI.Read(Buf^, BufSize);  // read a block
            if N > 0 then FO.WriteBuffer(Buf^, N);  // write the block
          until N <= 0;  // until the end of the file
        finally
          FO.Free;  // close the destination
        end;
      finally
        FI.Free;  // close the source
      end;
      Result := FileSizeUtf8(Dst) = FileSizeUtf8(Src);  // success when the sizes match
    except
      Result := False;  // failure
    end;
  finally
    FreeMem(Buf);  // free the buffer
  end;
  if not Result then
    DeleteFileUTF8(Dst);  // remove an incomplete copy
end;

{ Returns the MD5 of a file as 32 hex characters, or an empty text. }
function HashOfFile(const FileName: string): string;
const
  BufSize = 262144;  // size of the read buffer
var
  F: TFileStream;  // F: the open file
  Buf: Pointer;  // Buf: read buffer
  N: LongInt;  // N: bytes read
  Ctx: TMD5Context;  // Ctx: MD5 state
  Dig: TMD5Digest;  // Dig: MD5 result
begin
  Result := '';  // empty by default
  GetMem(Buf, BufSize);  // reserve the buffer
  try
    try
      F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
      try
        MD5Init(Ctx);  // start the MD5
        repeat
          N := F.Read(Buf^, BufSize);  // read a block
          if N > 0 then MD5Update(Ctx, Buf^, N);  // add it to the MD5
          if Assigned(CopyPump) then CopyPump;  // let the window update
          if CopyAbort then Exit;  // stop when canceled
        until N <= 0;
        MD5Final(Ctx, Dig);  // finish the MD5
        Result := MD5Print(Dig);  // convert to hex text
      finally
        F.Free;  // close the file
      end;
    except
      Result := '';  // failure
    end;
  finally
    FreeMem(Buf);  // free the buffer
  end;
end;

{ Copies a file and computes the MD5 of the source; with Verify the copy is read back and compared. }
function CopyFileChecked(const Src, Dst: string; Verify: Boolean; out Hash: string;
  out Err: string): TCopyResult;
const
  BufSize = 262144;  // size of the copy buffer
var
  FI, FO: TFileStream;  // FI: source file; FO: destination file
  Buf: Pointer;  // Buf: copy buffer
  N: LongInt;  // N: bytes read
  Ctx: TMD5Context;  // Ctx: MD5 state
  Dig: TMD5Digest;  // Dig: MD5 result
  Back: string;  // Back: MD5 of the copy
begin
  Result := crFailed;  // assume failure
  Hash := '';  // no hash yet
  Err := '';  // no error yet
  GetMem(Buf, BufSize);  // reserve the buffer
  try
    try
      FI := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);  // open the source
      try
        FO := TFileStream.Create(Dst, fmCreate);  // create the destination
        try
          MD5Init(Ctx);  // start the MD5
          repeat
            N := FI.Read(Buf^, BufSize);  // read a block
            if N > 0 then
            begin
              MD5Update(Ctx, Buf^, N);  // add it to the MD5
              FO.WriteBuffer(Buf^, N);  // write the block
            end;
            if Assigned(CopyPump) then CopyPump;  // let the window update
            if CopyAbort then  // canceled by the user
            begin
              Result := crCanceled;  // report cancellation
              Break;  // stop copying
            end;
          until N <= 0;  // until the end of the file
          MD5Final(Ctx, Dig);  // finish the MD5
          Hash := MD5Print(Dig);  // hash of the source as hex text
        finally
          FO.Free;  // close the destination
        end;
      finally
        FI.Free;  // close the source
      end;
      if Result = crCanceled then
        Err := 'canceled'  // reason
      else if FileSizeUtf8(Dst) <> FileSizeUtf8(Src) then  // compare the sizes
        Err := 'the copy has a different size than the original'  // reason
      else if Verify then
      begin
        Back := HashOfFile(Dst);  // MD5 of the copy
        if CopyAbort then  // canceled while reading back
          Result := crCanceled  // report cancellation
        else if Back = '' then  // the copy could not be read
        begin
          Result := crVerifyFailed;  // report the failure
          Err := 'the copy could not be read back';  // reason
        end
        else if Back <> Hash then  // checksums differ
        begin
          Result := crVerifyFailed;  // report the failure
          Err := 'checksum of the copy (' + Back + ') differs from the original (' + Hash + ')';  // reason
        end
        else
          Result := crOk;  // copy is good
      end
      else
        Result := crOk;  // copy is good
    except
      on E: Exception do
      begin
        Result := crFailed;  // report the failure
        Err := E.Message;  // reason
      end;
    end;
  finally
    FreeMem(Buf);  // free the buffer
  end;
  if Result <> crOk then
    DeleteFileUTF8(Dst);  // remove a bad or incomplete copy
end;

{ Returns the backup path of an item: backup folder from its own mask, file name of the main copy. }
function BackupDestFor(S: TAppSettings; Item: TImageItem; SeqDown, SeqSess: Integer;
  const MainDest: string): string;
var
  P: string;  // P: path built from the backup mask
begin
  P := BuildDest(S, Item, S.BackupDir, S.FileNameMask, JobCodeFor(S, Item), SeqDown, SeqSess);  // build the path from the backup folder
  Result := ExtractFilePath(P) + ExtractFileName(MainDest);  // folder of the backup with the file name of the main copy
end;

finalization
  FreeAndNil(ThumbLru);  // free the thumbnail list
  FreeAndNil(ExifCache);  // free the EXIF cache

end.
