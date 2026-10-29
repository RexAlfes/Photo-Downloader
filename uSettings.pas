unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, LazFileUtils;

const
  AppTitle = 'Photo Downloader';
  AppVersion = '1.0';  // version text for the About window
  WebsiteURL = 'https://rexalfes.github.io/Photo-Downloader/';
  UpdatesURL = 'https://github.com/RexAlfes/Photo-Downloader/releases';
  DonatePayPalURL = 'https://paypal.me/PhotoDownLoader';
  DonateVenmoURL = 'https://venmo.com/u/RexAlfes';

const
  FileTypeCount = 20;  // number of file type groups in the filter
  { File type groups of the filter (View > File Types). Key = name in the ini file. }
  FileTypeKeys: array[0..FileTypeCount - 1] of string =  // ini key for each file type group
    ('Jpeg', 'Png', 'Bmp', 'Gif', 'Tiff', 'CanonRaw', 'NikonRaw', 'NikonNrw', 'SonyRaw', 'Dng', 'OtherRaw',
     'Heic', 'Avif', 'WebP', 'Mp4', 'Mov', 'Lrv', 'Audio', 'Thm', 'LrPrev');
  FileTypeNames: array[0..FileTypeCount - 1] of string =  // text shown for each group in the File Types dialog
    ('JPEG (.jpg .jpeg .jpe)', 'PNG (.png)', 'BMP (.bmp)', 'GIF (.gif)', 'TIFF (.tif .tiff)',
     'Canon RAW (.cr2 .cr3 .crw)', 'Nikon RAW (.nef)', 'Nikon Coolpix RAW (.nrw)', 'Sony RAW (.arw .srf .sr2)',
     'Adobe DNG (.dng)', 'Other RAW (.orf .raf .rw2 .pef .srw .raw)',
     'HEIC / HEIF (.heic .heif)', 'AVIF (.avif)', 'WebP (.webp)', 'Video MP4 (.mp4)', 'Video MOV (.mov)', 'Video LRV (.lrv)', 'Audio (.mp3)',
     'Camera thumbnail files (.thm)', 'Lightroom previews (.lrprev)');
  FileTypeExts: array[0..FileTypeCount - 1] of string =  // extensions (each between semicolons) that belong to each group
    (';.jpg;.jpeg;.jpe;', ';.png;', ';.bmp;', ';.gif;', ';.tif;.tiff;', ';.cr2;.cr3;.crw;', ';.nef;', ';.nrw;',
     ';.arw;.srf;.sr2;', ';.dng;', ';.orf;.raf;.rw2;.pef;.srw;.raw;', ';.heic;.heif;', ';.avif;', ';.webp;',
     ';.mp4;', ';.mov;', ';.lrv;', ';.mp3;', ';.thm;', ';.lrprev;');

var
  { False while logging is switched off (Help > Logging) }
  LogEnabled: Boolean = True;  // logging switched on/off
  { True: characters Windows does not allow in file names are replaced by _ (Linux option "Windows-safe names") }
  WinSafeNamesOn: Boolean = True;  // replace characters Windows cannot store in file names

{ Index of the file type group an extension (with dot, any case) belongs to, or -1 }
function FileTypeIndex(const Ext: string): Integer;
{ True when file type group I is switched on in the application defaults (all except .thm, .mp3 and .lrprev) }
function FileTypeDefaultOn(I: Integer): Boolean;

type
  TSourceMode = (smAuto, smCamera, smCardReader);  // where pictures come from: automatic, camera or card reader

  { TAppSettings - every option shown on the Preferences tabs, plus view state }
  TAppSettings = class
  public
    // Download Path tab
    DownloadDir, FileNameMask, JobCode: string;  // destination folder template, file name template, job code
    PromptJobCode: Boolean;  // ask for the job code when starting
    SafeDeleteFolder: string;       // name of the hidden trash folder used on cards
    SafeDelete: Boolean;            // deleting from the source moves files to the Recycle Bin / holding folder
    VerifyCopy: Boolean;            // read every copy back and compare checksums
    BackupOn: Boolean;              // also save a second copy to BackupDir
    BackupDir: string;              // backup folder template (same tokens as DownloadDir)
    SeqStart, SeqNext: Integer;  // first and next sequence numbers
    JobHistory: TStringList;  // recently used job codes
    DateJobCodes: TStringList;      // 'yyyy/mm/dd=job code'
    // General tab
    SourceMode: TSourceMode;
    DriveLetters: string;  // drive letters to scan as image sources
    DisablePTP, SaveReadOnly, PreserveReadOnly, PromptProfile, IgnoreSizeCheck, AutoRenameClash, RenameDuplicates, IgnoreDuplicates,  // General tab check boxes
    AutoRotate, RenameJpe, LowerName, LowerExt, UseCaptureTime, SaveDateJobCodes,
    WriteExifText, AutoEject, ScanWholeDisk, AddIptc, PromptIptc, WriteIptcIIM,
    WriteIptcNef: Boolean;
    LrPrevAsJpg: Boolean;           // download .lrprev files as .jpg (the largest preview picture)
    LrPrevKeepBoth: Boolean;        // with LrPrevAsJpg: also keep the .lrprev file
    WriteExifOwner: Boolean;        // write author/copyright into EXIF on copy
    ExifAuthor, ExifCopyright: string;  // author and copyright text
    FirstRunDone: Boolean;          // False until the first start has completed
    SingleInstance: Boolean;        // only one copy of the program may run
    WinSafeNames: Boolean;          // replace characters that Windows file names cannot hold (matters on Linux)
    LoadLastAtStartup: Boolean;     // reload the last used source folder when the program starts
    LastSource: string;             // last folder opened as image source
    // Automation tab
    AutoAtStartup, AutoMenu, AutoPrompt, AutoDownload, AutoDelete, AutoSoftEject,
    AutoLaunch, AutoExit: Boolean;
    // Custom button tab
    CustomEnabled: Boolean;  // custom button on/off
    CustomCaption, CustomCmd: string;  // custom button caption and command
    // Mapping tab: lines 'Camera|T8|T9'; line 0 is the default mapping
    Mappings: TStringList;  // camera mapping lines 'Camera|T8|T9'
    IdentifyBySerial, PromptNewCamera: Boolean;  // camera identification options
    // Plug-ins tab: 'Name=0/1' in display order; PluginOpts: 'Name=value'
    Plugins: TStringList;  // plug-in names with 0/1 enabled flags
    PluginOpts: TStringList;  // plug-in option values
    // IPTC / XMP fields: 'Creator=..' etc.
    Iptc: TStringList;  // IPTC/XMP field values
    // View state
    ShowDownloaded, ShowDuplicates, ShowDateSelector: Boolean;  // which pictures the grid shows
    ViewMode: Integer;              // 0 list, 1 thumbnail cards
    FitWindow: Boolean;             // thumbnail view "Fit to Window" (default): cards share the window width, thumbnails at most 160 pixels
    ThumbSize: Integer;             // thumbnail box in pixels, 64..320 (presets: 64 small, 160 medium, 320 large)
    LoggingOn: Boolean;             // write thumbnail.log (Help > Logging)
    TypeOn: array[0..FileTypeCount - 1] of Boolean;   // file type filter (all on by default except .thm, .mp3 and .lrprev)
    function TypeShown(const FileName: string): Boolean;  // True when the file's type group is shown
    constructor Create;  // creates the settings with default values
    destructor Destroy; override;  // frees the lists
    procedure SetDefaults;  // restores every option to its default
    procedure LoadFrom(Ini: TCustomIniFile);  // reads the options from an ini file object
    procedure SaveTo(Ini: TCustomIniFile);  // writes the options to an ini file object
    procedure LoadFromFile(const AFileName: string);  // reads the options from a file
    procedure SaveToFile(const AFileName: string);  // writes the options to a file
    function PluginEnabled(const AName: string): Boolean;  // True when a plug-in is switched on
  end;

function ConfigDir: string;  // folder for the settings file
{ Folder for data that can be rebuilt (thumbnail cache): ~/.cache/PhotoDownloader/ on Linux, the settings folder on Windows }
function CacheDir: string;  // folder for rebuildable data such as thumbnails
function SettingsFileName: string;  // full path of the settings file
function ProfilesDir: string;  // folder for the user profile files
{ Reads only the single/multi instance option; used before the main form exists. }
function SingleInstanceWanted: Boolean;  // True when only one copy of the program may run
procedure MapSplit(const Line: string; out CamName, T8, T9: string);  // splits a camera mapping line into its three parts
function MapJoin(const CamName, T8, T9: string): string;  // joins camera name and two templates into one mapping line

const
  DefaultPlugins: array[0..4] of string =  // names of the built-in plug-ins
    ('JPEG auto profile', 'Backup', 'Directory Maker', 'DNG Converter', 'JPEG resolution');

implementation

{ Returns the settings folder (created if needed) with a trailing delimiter. }
function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));  // per-user application folder
  ForceDirectoriesUTF8(Result);  // make sure it exists
end;

{ Returns the folder for rebuildable data: ~/.cache/PhotoDownloader/ on Linux, the settings folder on Windows. }
function CacheDir: string;
begin
  {$IFDEF UNIX}
  Result := GetEnvironmentVariable('XDG_CACHE_HOME');  // cache location chosen by the user's desktop
  if Result = '' then Result := IncludeTrailingPathDelimiter(GetUserDir) + '.cache';  // default to ~/.cache
  Result := IncludeTrailingPathDelimiter(Result) + 'PhotoDownloader' + PathDelim;  // add the program's folder
  ForceDirectoriesUTF8(Result);  // make sure it exists
  {$ELSE}
  Result := ConfigDir;  // Windows keeps it with the settings
  {$ENDIF}
end;

{ Returns the full path of the main settings file. }
function SettingsFileName: string;
begin
  Result := ConfigDir + 'PhotoDownloader.ini';  // settings folder + file name
end;

{ Returns the folder holding user profile files (created if needed). }
function ProfilesDir: string;
begin
  Result := ConfigDir + 'profiles' + PathDelim;  // profiles sub-folder
  ForceDirectoriesUTF8(Result);  // make sure it exists
end;

{ Reads just the single-instance option; used before the main form exists. }
function SingleInstanceWanted: Boolean;
var
  Ini: TMemIniFile;  // Ini: the settings file
begin
  Result := True;                      // default: single instance
  if not FileExistsUTF8(SettingsFileName) then Exit;  // no settings file yet: keep the default
  Ini := TMemIniFile.Create(SettingsFileName);  // open the settings file
  try
    Result := Ini.ReadBool('General', 'SingleInstance', True);  // read the option
  finally
    Ini.Free;  // free the file object
  end;
end;

// Splits 'Camera|T8|T9' into the camera name and two templates; missing parts default to {T1}.
procedure MapSplit(const Line: string; out CamName, T8, T9: string);
var
  P1, P2: Integer;  // P1 and P2: positions of the separators
begin
  P1 := Pos('|', Line);  // first separator
  if P1 = 0 then  // no separator at all
  begin
    CamName := Line; T8 := '{T1}'; T9 := '{T1}'; Exit;  // name only: both templates default
  end;
  CamName := Copy(Line, 1, P1 - 1);  // camera name is the text before the first separator
  P2 := Pos('|', Copy(Line, P1 + 1, MaxInt));  // second separator in the rest
  if P2 = 0 then  // only one separator
  begin
    T8 := Copy(Line, P1 + 1, MaxInt); T9 := '{T1}';  // T8 is everything after it
  end
  else
  begin
    T8 := Copy(Line, P1 + 1, P2 - 1);  // T8 is the text between the separators
    T9 := Copy(Line, P1 + P2 + 1, MaxInt);  // T9 is the rest
  end;
end;

{ Joins camera name and two templates into one mapping line. }
function MapJoin(const CamName, T8, T9: string): string;
begin
  Result := CamName + '|' + T8 + '|' + T9;  // three parts separated by |
end;

{ Writes a list into an ini section as Count and Item0, Item1, ... }
procedure SaveList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  I: Integer;  // I: item index
begin
  Ini.EraseSection(Sec);  // remove the old section
  Ini.WriteInteger(Sec, 'Count', L.Count);  // store the number of items
  for I := 0 to L.Count - 1 do  // each item
    Ini.WriteString(Sec, 'Item' + IntToStr(I), L[I]);  // store one item
end;

{ Reads a list back from an ini section written by SaveList. }
procedure LoadList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  I, N: Integer;  // I: item index, N: number of items
begin
  L.Clear;  // start with an empty list
  N := Ini.ReadInteger(Sec, 'Count', 0);  // how many items were stored
  for I := 0 to N - 1 do  // each item
    L.Add(Ini.ReadString(Sec, 'Item' + IntToStr(I), ''));  // add one item
end;

{ TAppSettings }

{ Creates the lists and sets every option to its default. }
constructor TAppSettings.Create;
begin
  inherited Create;  // run the base constructor
  JobHistory := TStringList.Create;  // recent job codes
  DateJobCodes := TStringList.Create;  // job codes per date
  Mappings := TStringList.Create;  // camera mappings
  Plugins := TStringList.Create;  // plug-in states
  PluginOpts := TStringList.Create;  // plug-in options
  Iptc := TStringList.Create;  // IPTC fields
  SetDefaults;  // fill in the default values
end;

{ Frees the lists. }
destructor TAppSettings.Destroy;
begin
  JobHistory.Free;  // free the lists
  DateJobCodes.Free;
  Mappings.Free;
  Plugins.Free;
  PluginOpts.Free;
  Iptc.Free;
  inherited Destroy;  // free the lists
end;  // run the base destructor

{ Sets every option to its default value. }
procedure TAppSettings.SetDefaults;
var
  I: Integer;  // I: loop index
begin
  // generic default: the Pictures folder of whoever runs the program
  DownloadDir := IncludeTrailingPathDelimiter(GetUserDir) + 'Pictures' + PathDelim +  // default: destination folder template
    'Photo Downloader' + PathDelim + '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim;
  VerifyCopy := True;  // verify copies by default
  SafeDelete := True;  // safe delete on by default
  SafeDeleteFolder := '$trash.bin';  // default trash folder name
  BackupOn := False;  // backup off by default
  BackupDir := '';  // no backup folder
  FileNameMask := '{o}';  // file name is the original name
  JobCode := '{Job Name}';  // placeholder job code
  PromptJobCode := True;  // ask for the job code
  SeqStart := 1;  // sequence starts at 1
  SeqNext := 1;  // next sequence number is 1
  JobHistory.Clear;  // forget job code history
  DateJobCodes.Clear;  // forget job codes per date

  SourceMode := smAuto;  // automatic source selection
  DriveLetters := 'E';  // default drive letter
  DisablePTP := True;  // PTP downloads disabled
  SaveReadOnly := False;  // copies are not read-only
  PreserveReadOnly := False;  // do not keep the read-only flag
  PromptProfile := False;  // no profile prompt
  IgnoreSizeCheck := True;  // skip the size check
  AutoRenameClash := False;  // ask what to do with name clashes
  RenameDuplicates := False;  // do not download duplicates renamed
  IgnoreDuplicates := True;  // skip duplicate files
  AutoRotate := True;  // auto-rotate on
  RenameJpe := False;  // keep .jpe names
  LowerName := False;  // keep name case
  LowerExt := False;  // keep extension case
  LrPrevAsJpg := False;  // download .lrprev files as they are
  LrPrevKeepBoth := False;  // no second file
  UseCaptureTime := True;  // use the capture time
  SaveDateJobCodes := False;  // do not store job codes per date
  WriteExifText := False;  // do not write EXIF text
  AutoEject := True;  // eject the card when done
  ScanWholeDisk := True;  // scan the whole disk
  AddIptc := False;  // no IPTC by default
  PromptIptc := False;  // no IPTC prompt
  WriteIptcIIM := False;  // no IIM
  WriteIptcNef := True;  // write NEF IPTC
  WriteExifOwner := False;  // no EXIF owner
  ExifAuthor := '';  // no author
  ExifCopyright := '';  // no copyright
  FirstRunDone := False;  // first run not done yet
  LoadLastAtStartup := False;  // do not reload the last source
  SingleInstance := True;  // single instance
  WinSafeNames := True;  // Windows-safe names on
  LastSource := '';  // no last source

  AutoAtStartup := False;  // automation options all off except the prompt
  AutoMenu := False;  // automation menu off
  AutoPrompt := True;  // prompt on
  AutoDownload := False;  // manual download
  AutoDelete := False;  // keep the files on the card
  AutoSoftEject := False;  // no soft eject
  AutoLaunch := False;  // no launch
  AutoExit := False;  // no exit

  CustomEnabled := False;  // custom button off
  CustomCaption := 'C&ustom';  // default caption
  CustomCmd := '';  // no command

  Mappings.Clear;  // start with an empty mapping list
  Mappings.Add(MapJoin('Default', '{T1}', '{T1}'));  // add the default mapping
  IdentifyBySerial := False;  // identify cameras by name
  PromptNewCamera := False;  // do not ask about new cameras

  Plugins.Clear;  // start with an empty plug-in list
  for I := Low(DefaultPlugins) to High(DefaultPlugins) do  // add every built-in plug-in
    Plugins.Add(DefaultPlugins[I] + '=0');  // switched off
  PluginOpts.Clear;  // no plug-in options
  Iptc.Clear;  // no IPTC fields

  ShowDownloaded := True;  // show downloaded pictures
  ShowDuplicates := True;  // show duplicates
  ShowDateSelector := True;  // show the date selector
  ViewMode := 1;  // thumbnail cards
  ThumbSize := 160;  // medium thumbnails
  FitWindow := True;  // thumbnails fit the window width by default
  for I := 0 to FileTypeCount - 1 do TypeOn[I] := FileTypeDefaultOn(I);  // application default for each file type
  LoggingOn := True;  // logging on
end;

{ Application default of a file type group: on, except camera thumbnail (.thm) files (only helpers for
  videos), audio (.mp3) and Lightroom previews (.lrprev). }
function FileTypeDefaultOn(I: Integer): Boolean;
begin
  Result := not ((FileTypeKeys[I] = 'Thm') or (FileTypeKeys[I] = 'Audio') or (FileTypeKeys[I] = 'LrPrev'));
end;

{ Returns the index of the file type group that holds an extension, or -1. }
function FileTypeIndex(const Ext: string): Integer;
var
  I: Integer;  // I: group index
  E: string;  // E: extension in the search form ';.ext;'
begin
  E := ';' + LowerCase(Ext) + ';';  // lowercase with semicolons
  for I := 0 to FileTypeCount - 1 do  // search the groups
    if Pos(E, FileTypeExts[I]) > 0 then Exit(I);  // group found
  Result := -1;  // not found
end;

{ True if the file's type group is switched on in the filter (unknown types are shown). }
function TAppSettings.TypeShown(const FileName: string): Boolean;
var
  I: Integer;  // I: group index
begin
  I := FileTypeIndex(ExtractFileExt(FileName));  // find the group
  Result := (I < 0) or TypeOn[I];  // unknown or switched on
end;

{ Reads every option from an ini file; missing keys keep their current values. }
procedure TAppSettings.LoadFrom(Ini: TCustomIniFile);
var
  I: Integer;  // I: temporary number or loop index
begin
  with Ini do
  begin
    DownloadDir := ReadString('Path', 'DownloadDir', DownloadDir);  // load: destination folder template
    VerifyCopy := ReadBool('Path', 'VerifyCopy', VerifyCopy);  // load: verify copies by reading them back
    SafeDelete := ReadBool('Automation', 'SafeDelete', SafeDelete);  // load: safe delete on/off
    SafeDeleteFolder := ReadString('Automation', 'SafeDeleteFolder', SafeDeleteFolder);  // load: name of the hidden trash folder
    BackupOn := ReadBool('Path', 'BackupEnabled', BackupOn);  // load: backup copy on/off
    BackupDir := ReadString('Path', 'BackupDir', BackupDir);  // load: backup folder template
    FileNameMask := ReadString('Path', 'FileNameMask', FileNameMask);  // load: file name template
    JobCode := ReadString('Path', 'JobCode', JobCode);  // load: job code text
    PromptJobCode := ReadBool('Path', 'PromptJobCode', PromptJobCode);  // load: ask for the job code at start-up
    SeqStart := ReadInteger('Path', 'SeqStart', SeqStart);  // load: first sequence number
    SeqNext := ReadInteger('Path', 'SeqNext', SeqNext);  // load: next sequence number

    I := ReadInteger('General', 'SourceMode', Ord(SourceMode));  // stored source mode number
    if (I < 0) or (I > Ord(High(TSourceMode))) then I := 0;  // ignore invalid numbers
    SourceMode := TSourceMode(I);  // convert the number to the source mode
    DriveLetters := ReadString('General', 'DriveLetters', DriveLetters);  // load: drive letters to scan
    DisablePTP := ReadBool('General', 'DisablePTP', DisablePTP);  // load: disable PTP downloads
    SaveReadOnly := ReadBool('General', 'SaveReadOnly', SaveReadOnly);  // load: save copies as read-only
    PreserveReadOnly := ReadBool('General', 'PreserveReadOnly', PreserveReadOnly);  // load: keep the read-only flag of the original
    PromptProfile := ReadBool('General', 'PromptProfile', PromptProfile);  // load: ask for a user profile at start-up
    IgnoreSizeCheck := ReadBool('General', 'IgnoreSizeCheck', IgnoreSizeCheck);  // load: skip the size check
    AutoRenameClash := ReadBool('General', 'AutoRenameClash', AutoRenameClash);  // load: rename name clashes automatically
    RenameDuplicates := ReadBool('General', 'RenameDuplicates', RenameDuplicates);  // load: download duplicates renamed
    IgnoreDuplicates := ReadBool('General', 'IgnoreDuplicates', IgnoreDuplicates);  // load: skip duplicate files
    if RenameDuplicates then IgnoreDuplicates := False;  // renaming wins over ignoring
    AutoRotate := ReadBool('General', 'AutoRotate', AutoRotate);  // load: turn pictures upright by their EXIF orientation
    RenameJpe := ReadBool('General', 'RenameJpe', RenameJpe);  // load: rename .jpe to .jpg
    LowerName := ReadBool('General', 'LowerName', LowerName);  // load: lowercase file names
    LowerExt := ReadBool('General', 'LowerExt', LowerExt);  // load: lowercase extensions
    LrPrevAsJpg := ReadBool('General', 'LrPrevAsJpg', LrPrevAsJpg);  // load: .lrprev files as .jpg
    LrPrevKeepBoth := ReadBool('General', 'LrPrevKeepBoth', LrPrevKeepBoth);  // load: keep the .lrprev file as well
    UseCaptureTime := ReadBool('General', 'UseCaptureTime', UseCaptureTime);  // load: use the capture time for dates
    SaveDateJobCodes := ReadBool('General', 'SaveDateJobCodes', SaveDateJobCodes);  // load: remember a job code per date
    WriteExifText := ReadBool('General', 'WriteExifText', WriteExifText);  // load: write the job text into EXIF
    AutoEject := ReadBool('General', 'AutoEject', AutoEject);  // load: eject the card after download
    ScanWholeDisk := ReadBool('General', 'ScanWholeDisk', ScanWholeDisk);  // load: scan the whole disk, not only DCIM
    AddIptc := ReadBool('General', 'AddIptc', AddIptc);  // load: add IPTC/XMP details
    PromptIptc := ReadBool('General', 'PromptIptc', PromptIptc);  // load: ask for the IPTC details
    WriteIptcIIM := ReadBool('General', 'WriteIptcIIM', WriteIptcIIM);  // load: write IPTC IIM into JPEGs
    WriteIptcNef := ReadBool('General', 'WriteIptcNef', WriteIptcNef);  // load: write IPTC/XMP for NEF files
    WriteExifOwner := ReadBool('General', 'WriteExifOwner', WriteExifOwner);  // load: write author and copyright into EXIF
    ExifAuthor := ReadString('General', 'ExifAuthor', ExifAuthor);  // load: author name
    ExifCopyright := ReadString('General', 'ExifCopyright', ExifCopyright);  // load: copyright text
    FirstRunDone := ReadBool('General', 'FirstRunDone', FirstRunDone);  // load: first start completed
    LoadLastAtStartup := ReadBool('General', 'LoadLastAtStartup', LoadLastAtStartup);  // load: reload the last source at start-up
    SingleInstance := ReadBool('General', 'SingleInstance', SingleInstance);  // load: allow only one running copy
    WinSafeNames := ReadBool('General', 'WinSafeNames', WinSafeNames);  // load: replace characters Windows cannot store
    {$IFDEF WINDOWS}WinSafeNamesOn := True;{$ELSE}WinSafeNamesOn := WinSafeNames;{$ENDIF}  // on Windows names are always made safe; on other systems the option decides
    LastSource := ReadString('General', 'LastSource', LastSource);  // load: last used source folder

    AutoAtStartup := ReadBool('Automation', 'AutoAtStartup', AutoAtStartup);  // load: automation: run at start-up
    AutoMenu := ReadBool('Automation', 'AutoMenu', AutoMenu);  // load: automation: show a menu
    AutoPrompt := ReadBool('Automation', 'AutoPrompt', AutoPrompt);  // load: automation: ask before downloading
    AutoDownload := ReadBool('Automation', 'AutoDownload', AutoDownload);  // load: automation: download automatically
    AutoDelete := ReadBool('Automation', 'AutoDelete', AutoDelete);  // load: automation: delete after download
    AutoSoftEject := ReadBool('Automation', 'AutoSoftEject', AutoSoftEject);  // load: automation: eject after download
    AutoLaunch := ReadBool('Automation', 'AutoLaunch', AutoLaunch);  // load: automation: launch a program
    AutoExit := ReadBool('Automation', 'AutoExit', AutoExit);  // load: automation: exit when done

    CustomEnabled := ReadBool('Custom', 'Enabled', CustomEnabled);  // load: custom button on/off
    CustomCaption := ReadString('Custom', 'Caption', CustomCaption);  // load: custom button caption
    CustomCmd := ReadString('Custom', 'Command', CustomCmd);  // load: custom button command

    IdentifyBySerial := ReadBool('Mapping', 'IdentifyBySerial', IdentifyBySerial);  // load: identify cameras by serial number
    PromptNewCamera := ReadBool('Mapping', 'PromptNewCamera', PromptNewCamera);  // load: ask when a new camera is found

    ShowDownloaded := ReadBool('View', 'ShowDownloaded', ShowDownloaded);  // load: show already downloaded pictures
    ShowDuplicates := ReadBool('View', 'ShowDuplicates', ShowDuplicates);  // load: show duplicates
    ShowDateSelector := ReadBool('View', 'ShowDateSelector', ShowDateSelector);  // load: show the date selector
    ViewMode := ReadInteger('View', 'ThumbView', ViewMode);  // load: view mode (0 list, otherwise cards)
    if ViewMode < 0 then ViewMode := 1;  // keep the view mode in range
    if ValueExists('View', 'ThumbSize') then  // thumbnail size saved by this version
      ThumbSize := ReadInteger('View', 'ThumbSize', ThumbSize)
    else if ValueExists('View', 'ThumbView') then  // older settings file: the size came from the view mode
    begin
      if ViewMode = 1 then ThumbSize := 64  // 1 meant small thumbnails
      else if ViewMode > 1 then ThumbSize := 160;  // 2 meant the large thumbnails of that time (160 pixels)
    end;
    if ViewMode > 1 then ViewMode := 1;  // cards
    if ThumbSize < 64 then ThumbSize := 64;  // keep the size in range
    if ThumbSize > 320 then ThumbSize := 320;
    // a settings file from an older build has a fixed size: keep it; the Fit to Window default applies to new settings
    FitWindow := ReadBool('View', 'FitToWindow', FitWindow and not ValueExists('View', 'ThumbView'));  // load: Fit to Window
    for I := 0 to FileTypeCount - 1 do  // each file type group
      TypeOn[I] := ReadBool('FileTypes', FileTypeKeys[I], TypeOn[I]);
    if ValueExists('FileTypes', 'Video') then  // older settings file: one switch covered all video types
      for I := 0 to FileTypeCount - 1 do  // each file type group
        if ((FileTypeKeys[I] = 'Mp4') or (FileTypeKeys[I] = 'Mov') or (FileTypeKeys[I] = 'Lrv')) and  // a video group
           not ValueExists('FileTypes', FileTypeKeys[I]) then  // that has no setting of its own yet
          TypeOn[I] := ReadBool('FileTypes', 'Video', True);  // take over the old switch
    LoggingOn := ReadBool('General', 'Logging', LoggingOn);  // load: write the log file

    if SectionExists('JobHistory') then LoadList(Ini, 'JobHistory', JobHistory);  // read the job history
    if SectionExists('Mappings') then LoadList(Ini, 'Mappings', Mappings);  // read the camera mappings
    if SectionExists('Plugins') then LoadList(Ini, 'Plugins', Plugins);  // read the plug-in list
    if SectionExists('PluginOpts') then LoadList(Ini, 'PluginOpts', PluginOpts);  // read the plug-in options
    if SectionExists('Iptc') then LoadList(Ini, 'Iptc', Iptc);  // read the IPTC fields
    if SaveDateJobCodes and SectionExists('DateJobCodes') then  // read the per-date job codes when they are kept
      LoadList(Ini, 'DateJobCodes', DateJobCodes);  // read them
  end;
  if Mappings.Count = 0 then  // always keep at least the default mapping
    Mappings.Add(MapJoin('Default', '{T1}', '{T1}'));  // add it
  for I := Low(DefaultPlugins) to High(DefaultPlugins) do  // make sure every built-in plug-in is listed
    if Plugins.IndexOfName(DefaultPlugins[I]) < 0 then  // missing from the list
      Plugins.Add(DefaultPlugins[I] + '=0');  // add it switched off
end;

{ Writes every option to an ini file object. }
procedure TAppSettings.SaveTo(Ini: TCustomIniFile);
var
  I: Integer;  // I: loop index
begin
  with Ini do
  begin
    WriteString('Path', 'DownloadDir', DownloadDir);  // save: destination folder template
    WriteBool('Path', 'VerifyCopy', VerifyCopy);  // save: verify copies by reading them back
    WriteBool('Automation', 'SafeDelete', SafeDelete);  // save: safe delete on/off
    WriteString('Automation', 'SafeDeleteFolder', SafeDeleteFolder);  // save: name of the hidden trash folder
    WriteBool('Path', 'BackupEnabled', BackupOn);  // save: backup copy on/off
    WriteString('Path', 'BackupDir', BackupDir);  // save: backup folder template
    WriteString('Path', 'FileNameMask', FileNameMask);  // save: file name template
    WriteString('Path', 'JobCode', JobCode);  // save: job code text
    WriteBool('Path', 'PromptJobCode', PromptJobCode);  // save: ask for the job code at start-up
    WriteInteger('Path', 'SeqStart', SeqStart);  // save: first sequence number
    WriteInteger('Path', 'SeqNext', SeqNext);  // save: next sequence number

    WriteInteger('General', 'SourceMode', Ord(SourceMode));  // save: source mode number
    WriteString('General', 'DriveLetters', DriveLetters);  // save: drive letters to scan
    WriteBool('General', 'DisablePTP', DisablePTP);  // save: disable PTP downloads
    WriteBool('General', 'SaveReadOnly', SaveReadOnly);  // save: save copies as read-only
    WriteBool('General', 'PreserveReadOnly', PreserveReadOnly);  // save: keep the read-only flag of the original
    WriteBool('General', 'PromptProfile', PromptProfile);  // save: ask for a user profile at start-up
    WriteBool('General', 'IgnoreSizeCheck', IgnoreSizeCheck);  // save: skip the size check
    WriteBool('General', 'AutoRenameClash', AutoRenameClash);  // save: rename name clashes automatically
    WriteBool('General', 'RenameDuplicates', RenameDuplicates);  // save: download duplicates renamed
    WriteBool('General', 'IgnoreDuplicates', IgnoreDuplicates);  // save: skip duplicate files
    WriteBool('General', 'AutoRotate', AutoRotate);  // save: turn pictures upright by their EXIF orientation
    WriteBool('General', 'RenameJpe', RenameJpe);  // save: rename .jpe to .jpg
    WriteBool('General', 'LowerName', LowerName);  // save: lowercase file names
    WriteBool('General', 'LowerExt', LowerExt);  // save: lowercase extensions
    WriteBool('General', 'LrPrevAsJpg', LrPrevAsJpg);  // save: .lrprev files as .jpg
    WriteBool('General', 'LrPrevKeepBoth', LrPrevKeepBoth);  // save: keep the .lrprev file as well
    WriteBool('General', 'UseCaptureTime', UseCaptureTime);  // save: use the capture time for dates
    WriteBool('General', 'SaveDateJobCodes', SaveDateJobCodes);  // save: remember a job code per date
    WriteBool('General', 'WriteExifText', WriteExifText);  // save: write the job text into EXIF
    WriteBool('General', 'AutoEject', AutoEject);  // save: eject the card after download
    WriteBool('General', 'ScanWholeDisk', ScanWholeDisk);  // save: scan the whole disk, not only DCIM
    WriteBool('General', 'AddIptc', AddIptc);  // save: add IPTC/XMP details
    WriteBool('General', 'PromptIptc', PromptIptc);  // save: ask for the IPTC details
    WriteBool('General', 'WriteIptcIIM', WriteIptcIIM);  // save: write IPTC IIM into JPEGs
    WriteBool('General', 'WriteIptcNef', WriteIptcNef);  // save: write IPTC/XMP for NEF files
    WriteBool('General', 'WriteExifOwner', WriteExifOwner);  // save: write author and copyright into EXIF
    WriteString('General', 'ExifAuthor', ExifAuthor);  // save: author name
    WriteString('General', 'ExifCopyright', ExifCopyright);  // save: copyright text
    WriteBool('General', 'FirstRunDone', FirstRunDone);  // save: first start completed
    WriteBool('General', 'LoadLastAtStartup', LoadLastAtStartup);  // save: reload the last source at start-up
    WriteBool('General', 'SingleInstance', SingleInstance);  // save: allow only one running copy
    WriteBool('General', 'WinSafeNames', WinSafeNames);  // save: replace characters Windows cannot store
    WriteString('General', 'LastSource', LastSource);  // save: last used source folder

    WriteBool('Automation', 'AutoAtStartup', AutoAtStartup);  // save: automation: run at start-up
    WriteBool('Automation', 'AutoMenu', AutoMenu);  // save: automation: show a menu
    WriteBool('Automation', 'AutoPrompt', AutoPrompt);  // save: automation: ask before downloading
    WriteBool('Automation', 'AutoDownload', AutoDownload);  // save: automation: download automatically
    WriteBool('Automation', 'AutoDelete', AutoDelete);  // save: automation: delete after download
    WriteBool('Automation', 'AutoSoftEject', AutoSoftEject);  // save: automation: eject after download
    WriteBool('Automation', 'AutoLaunch', AutoLaunch);  // save: automation: launch a program
    WriteBool('Automation', 'AutoExit', AutoExit);  // save: automation: exit when done

    WriteBool('Custom', 'Enabled', CustomEnabled);  // save: custom button on/off
    WriteString('Custom', 'Caption', CustomCaption);  // save: custom button caption
    WriteString('Custom', 'Command', CustomCmd);  // save: custom button command

    WriteBool('Mapping', 'IdentifyBySerial', IdentifyBySerial);  // save: identify cameras by serial number
    WriteBool('Mapping', 'PromptNewCamera', PromptNewCamera);  // save: ask when a new camera is found

    WriteBool('View', 'ShowDownloaded', ShowDownloaded);  // save: show already downloaded pictures
    WriteBool('View', 'ShowDuplicates', ShowDuplicates);  // save: show duplicates
    WriteBool('View', 'ShowDateSelector', ShowDateSelector);  // save: show the date selector
    WriteInteger('View', 'ThumbView', ViewMode);  // save: view mode (0 list, 1 cards)
    WriteInteger('View', 'ThumbSize', ThumbSize);  // save: thumbnail size in pixels
    WriteBool('View', 'FitToWindow', FitWindow);  // save: Fit to Window
    for I := 0 to FileTypeCount - 1 do  // each file type group
      WriteBool('FileTypes', FileTypeKeys[I], TypeOn[I]);  // save: group on/off
    WriteBool('General', 'Logging', LoggingOn);  // save: write the log file11|program name shown in titles
  end;
  SaveList(Ini, 'JobHistory', JobHistory);  // save the job history
  SaveList(Ini, 'Mappings', Mappings);  // save the camera mappings
  SaveList(Ini, 'Plugins', Plugins);  // save the plug-in list
  SaveList(Ini, 'PluginOpts', PluginOpts);  // save the plug-in options
  SaveList(Ini, 'Iptc', Iptc);  // save the IPTC fields
  if SaveDateJobCodes then  // keep per-date job codes only if wanted
    SaveList(Ini, 'DateJobCodes', DateJobCodes)  // save them
  else
    Ini.EraseSection('DateJobCodes');  // otherwise remove the section
end;

{ Loads the options from a file; does nothing if the file does not exist. }
procedure TAppSettings.LoadFromFile(const AFileName: string);
var
  Ini: TMemIniFile;  // Ini: the file as an ini object
begin
  if not FileExistsUTF8(AFileName) then Exit;  // no file: keep the current values
  Ini := TMemIniFile.Create(AFileName);  // open the file
  try
    LoadFrom(Ini);  // read the options
  finally
    Ini.Free;  // free the file object
  end;
end;

{ Saves the options to a file. }
procedure TAppSettings.SaveToFile(const AFileName: string);
var
  Ini: TMemIniFile;  // Ini: the file as an ini object
begin
  Ini := TMemIniFile.Create(AFileName);  // open or create the ini object
  try
    SaveTo(Ini);  // collect the options
    Ini.UpdateFile;  // write the file to disk
  finally
    Ini.Free;  // free the ini object
  end;
end;

{ True if the named plug-in is switched on. }
function TAppSettings.PluginEnabled(const AName: string): Boolean;
begin
  Result := Plugins.Values[AName] = '1';  // '1' means enabled
end;

end.
