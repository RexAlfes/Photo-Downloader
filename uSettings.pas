unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, LazFileUtils;

const
  AppTitle = 'Photo Downloader';
  AppVersion = '1.0';
  WebsiteURL = 'https://rexalfes.github.io/Photo-Downloader/';
  UpdatesURL = 'https://github.com/RexAlfes/Photo-Downloader/releases';
  DonatePayPalURL = 'https://paypal.me/PhotoDownLoader';
  DonateVenmoURL = 'https://venmo.com/u/RexAlfes';

const
  FileTypeCount = 15;
  { File type groups of the filter (View > File Types). Key = name in the ini file. }
  FileTypeKeys: array[0..FileTypeCount - 1] of string =
    ('Jpeg', 'Png', 'Bmp', 'Tiff', 'CanonRaw', 'NikonRaw', 'NikonNrw', 'SonyRaw', 'Dng', 'OtherRaw',
     'Heic', 'Avif', 'Video', 'Audio', 'Thm');
  FileTypeNames: array[0..FileTypeCount - 1] of string =
    ('JPEG (.jpg .jpeg .jpe)', 'PNG (.png)', 'BMP (.bmp)', 'TIFF (.tif .tiff)',
     'Canon RAW (.cr2 .cr3 .crw)', 'Nikon RAW (.nef)', 'Nikon Coolpix RAW (.nrw)', 'Sony RAW (.arw .srf .sr2)',
     'Adobe DNG (.dng)', 'Other RAW (.orf .raf .rw2 .pef .srw .raw)',
     'HEIC / HEIF (.heic .heif)', 'AVIF (.avif)', 'Video (.mp4 .mov .lrv)', 'Audio (.mp3)',
     'Camera thumbnail files (.thm)');
  FileTypeExts: array[0..FileTypeCount - 1] of string =
    (';.jpg;.jpeg;.jpe;', ';.png;', ';.bmp;', ';.tif;.tiff;', ';.cr2;.cr3;.crw;', ';.nef;', ';.nrw;',
     ';.arw;.srf;.sr2;', ';.dng;', ';.orf;.raf;.rw2;.pef;.srw;.raw;', ';.heic;.heif;', ';.avif;',
     ';.mp4;.mov;.lrv;', ';.mp3;', ';.thm;');

var
  { False while logging is switched off (Help > Logging) }
  LogEnabled: Boolean = True;

{ Index of the file type group an extension (with dot, any case) belongs to, or -1 }
function FileTypeIndex(const Ext: string): Integer;

type
  TSourceMode = (smAuto, smCamera, smCardReader);

  { TAppSettings - every option shown on the Preferences tabs, plus view state }
  TAppSettings = class
  public
    // Download Path tab
    DownloadDir, FileNameMask, JobCode: string;
    PromptJobCode: Boolean;
    SeqStart, SeqNext: Integer;
    JobHistory: TStringList;
    DateJobCodes: TStringList;      // 'yyyy/mm/dd=job code'
    // General tab
    SourceMode: TSourceMode;
    DriveLetters: string;
    DisablePTP, SaveReadOnly, PreserveReadOnly, PromptProfile, IgnoreSizeCheck,
    AutoRotate, RenameJpe, LowerName, LowerExt, UseCaptureTime, SaveDateJobCodes,
    WriteExifText, AutoEject, ScanWholeDisk, AddIptc, PromptIptc, WriteIptcIIM,
    WriteIptcNef: Boolean;
    WriteExifOwner: Boolean;        // write author/copyright into EXIF on copy
    ExifAuthor, ExifCopyright: string;
    FirstRunDone: Boolean;          // False until the first start has completed
    SingleInstance: Boolean;        // only one copy of the program may run
    LoadLastAtStartup: Boolean;     // reload the last used source folder when the program starts
    LastSource: string;             // last folder opened as image source
    // Automation tab
    AutoAtStartup, AutoMenu, AutoPrompt, AutoDownload, AutoDelete, AutoSoftEject,
    AutoLaunch, AutoExit: Boolean;
    // Custom button tab
    CustomEnabled: Boolean;
    CustomCaption, CustomCmd: string;
    // Mapping tab: lines 'Camera|T8|T9'; line 0 is the default mapping
    Mappings: TStringList;
    IdentifyBySerial, PromptNewCamera: Boolean;
    // Plug-ins tab: 'Name=0/1' in display order; PluginOpts: 'Name=value'
    Plugins: TStringList;
    PluginOpts: TStringList;
    // IPTC / XMP fields: 'Creator=..' etc.
    Iptc: TStringList;
    // View state
    ShowDownloaded, ShowDuplicates, ShowDateSelector: Boolean;
    ViewMode: Integer;              // 0 list, 1 small thumbs, 2 large thumbs
    LoggingOn: Boolean;             // write thumbnail.log (Help > Logging)
    TypeOn: array[0..FileTypeCount - 1] of Boolean;   // file type filter (all on by default)
    function TypeShown(const FileName: string): Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure SetDefaults;
    procedure LoadFrom(Ini: TCustomIniFile);
    procedure SaveTo(Ini: TCustomIniFile);
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    function PluginEnabled(const AName: string): Boolean;
  end;

function ConfigDir: string;
function SettingsFileName: string;
function ProfilesDir: string;
{ Reads only the single/multi instance option; used before the main form exists. }
function SingleInstanceWanted: Boolean;
procedure MapSplit(const Line: string; out CamName, T8, T9: string);
function MapJoin(const CamName, T8, T9: string): string;

const
  DefaultPlugins: array[0..4] of string =
    ('JPEG auto profile', 'Backup', 'Directory Maker', 'DNG Converter', 'JPEG resolution');

implementation

function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
  ForceDirectoriesUTF8(Result);
end;

function SettingsFileName: string;
begin
  Result := ConfigDir + 'PhotoDownloader.ini';
end;

function ProfilesDir: string;
begin
  Result := ConfigDir + 'profiles' + PathDelim;
  ForceDirectoriesUTF8(Result);
end;

function SingleInstanceWanted: Boolean;
var
  Ini: TMemIniFile;
begin
  Result := True;                      // default: single instance
  if not FileExistsUTF8(SettingsFileName) then Exit;
  Ini := TMemIniFile.Create(SettingsFileName);
  try
    Result := Ini.ReadBool('General', 'SingleInstance', True);
  finally
    Ini.Free;
  end;
end;

procedure MapSplit(const Line: string; out CamName, T8, T9: string);
var
  P1, P2: Integer;
begin
  P1 := Pos('|', Line);
  if P1 = 0 then
  begin
    CamName := Line; T8 := '{T1}'; T9 := '{T1}'; Exit;
  end;
  CamName := Copy(Line, 1, P1 - 1);
  P2 := Pos('|', Copy(Line, P1 + 1, MaxInt));
  if P2 = 0 then
  begin
    T8 := Copy(Line, P1 + 1, MaxInt); T9 := '{T1}';
  end
  else
  begin
    T8 := Copy(Line, P1 + 1, P2 - 1);
    T9 := Copy(Line, P1 + P2 + 1, MaxInt);
  end;
end;

function MapJoin(const CamName, T8, T9: string): string;
begin
  Result := CamName + '|' + T8 + '|' + T9;
end;

procedure SaveList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  I: Integer;
begin
  Ini.EraseSection(Sec);
  Ini.WriteInteger(Sec, 'Count', L.Count);
  for I := 0 to L.Count - 1 do
    Ini.WriteString(Sec, 'Item' + IntToStr(I), L[I]);
end;

procedure LoadList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  I, N: Integer;
begin
  L.Clear;
  N := Ini.ReadInteger(Sec, 'Count', 0);
  for I := 0 to N - 1 do
    L.Add(Ini.ReadString(Sec, 'Item' + IntToStr(I), ''));
end;

{ TAppSettings }

constructor TAppSettings.Create;
begin
  inherited Create;
  JobHistory := TStringList.Create;
  DateJobCodes := TStringList.Create;
  Mappings := TStringList.Create;
  Plugins := TStringList.Create;
  PluginOpts := TStringList.Create;
  Iptc := TStringList.Create;
  SetDefaults;
end;

destructor TAppSettings.Destroy;
begin
  JobHistory.Free;
  DateJobCodes.Free;
  Mappings.Free;
  Plugins.Free;
  PluginOpts.Free;
  Iptc.Free;
  inherited Destroy;
end;

procedure TAppSettings.SetDefaults;
var
  I: Integer;
begin
  // generic default: the Pictures folder of whoever runs the program
  DownloadDir := IncludeTrailingPathDelimiter(GetUserDir) + 'Pictures' + PathDelim +
    'Photo Downloader' + PathDelim + '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim;
  FileNameMask := 'RA{Y}{m}{D}-{r}';
  JobCode := '{Job Name}';
  PromptJobCode := True;
  SeqStart := 1;
  SeqNext := 1;
  JobHistory.Clear;
  DateJobCodes.Clear;

  SourceMode := smAuto;
  DriveLetters := 'E';
  DisablePTP := True;
  SaveReadOnly := False;
  PreserveReadOnly := False;
  PromptProfile := False;
  IgnoreSizeCheck := True;
  AutoRotate := True;
  RenameJpe := False;
  LowerName := False;
  LowerExt := False;
  UseCaptureTime := True;
  SaveDateJobCodes := False;
  WriteExifText := False;
  AutoEject := True;
  ScanWholeDisk := True;
  AddIptc := False;
  PromptIptc := False;
  WriteIptcIIM := False;
  WriteIptcNef := True;
  WriteExifOwner := False;
  ExifAuthor := '';
  ExifCopyright := '';
  FirstRunDone := False;
  LoadLastAtStartup := False;
  SingleInstance := True;
  LastSource := '';

  AutoAtStartup := False;
  AutoMenu := False;
  AutoPrompt := True;
  AutoDownload := False;
  AutoDelete := False;
  AutoSoftEject := False;
  AutoLaunch := False;
  AutoExit := False;

  CustomEnabled := False;
  CustomCaption := 'C&ustom';
  CustomCmd := '';

  Mappings.Clear;
  Mappings.Add(MapJoin('Default', '{T1}', '{T1}'));
  IdentifyBySerial := False;
  PromptNewCamera := False;

  Plugins.Clear;
  for I := Low(DefaultPlugins) to High(DefaultPlugins) do
    Plugins.Add(DefaultPlugins[I] + '=0');
  PluginOpts.Clear;
  Iptc.Clear;

  ShowDownloaded := True;
  ShowDuplicates := True;
  ShowDateSelector := True;
  ViewMode := 2;
  for I := 0 to FileTypeCount - 1 do TypeOn[I] := True;
  // video, audio and camera thumbnail files are not verified yet: off until they are
  for I := 0 to FileTypeCount - 1 do
    if (FileTypeKeys[I] = 'Video') or (FileTypeKeys[I] = 'Audio') or (FileTypeKeys[I] = 'Thm') then
      TypeOn[I] := False;
  LoggingOn := True;
end;

function FileTypeIndex(const Ext: string): Integer;
var
  I: Integer;
  E: string;
begin
  E := ';' + LowerCase(Ext) + ';';
  for I := 0 to FileTypeCount - 1 do
    if Pos(E, FileTypeExts[I]) > 0 then Exit(I);
  Result := -1;
end;

function TAppSettings.TypeShown(const FileName: string): Boolean;
var
  I: Integer;
begin
  I := FileTypeIndex(ExtractFileExt(FileName));
  Result := (I < 0) or TypeOn[I];
end;

procedure TAppSettings.LoadFrom(Ini: TCustomIniFile);
var
  I: Integer;
begin
  with Ini do
  begin
    DownloadDir := ReadString('Path', 'DownloadDir', DownloadDir);
    FileNameMask := ReadString('Path', 'FileNameMask', FileNameMask);
    JobCode := ReadString('Path', 'JobCode', JobCode);
    PromptJobCode := ReadBool('Path', 'PromptJobCode', PromptJobCode);
    SeqStart := ReadInteger('Path', 'SeqStart', SeqStart);
    SeqNext := ReadInteger('Path', 'SeqNext', SeqNext);

    I := ReadInteger('General', 'SourceMode', Ord(SourceMode));
    if (I < 0) or (I > Ord(High(TSourceMode))) then I := 0;
    SourceMode := TSourceMode(I);
    DriveLetters := ReadString('General', 'DriveLetters', DriveLetters);
    DisablePTP := ReadBool('General', 'DisablePTP', DisablePTP);
    SaveReadOnly := ReadBool('General', 'SaveReadOnly', SaveReadOnly);
    PreserveReadOnly := ReadBool('General', 'PreserveReadOnly', PreserveReadOnly);
    PromptProfile := ReadBool('General', 'PromptProfile', PromptProfile);
    IgnoreSizeCheck := ReadBool('General', 'IgnoreSizeCheck', IgnoreSizeCheck);
    AutoRotate := ReadBool('General', 'AutoRotate', AutoRotate);
    RenameJpe := ReadBool('General', 'RenameJpe', RenameJpe);
    LowerName := ReadBool('General', 'LowerName', LowerName);
    LowerExt := ReadBool('General', 'LowerExt', LowerExt);
    UseCaptureTime := ReadBool('General', 'UseCaptureTime', UseCaptureTime);
    SaveDateJobCodes := ReadBool('General', 'SaveDateJobCodes', SaveDateJobCodes);
    WriteExifText := ReadBool('General', 'WriteExifText', WriteExifText);
    AutoEject := ReadBool('General', 'AutoEject', AutoEject);
    ScanWholeDisk := ReadBool('General', 'ScanWholeDisk', ScanWholeDisk);
    AddIptc := ReadBool('General', 'AddIptc', AddIptc);
    PromptIptc := ReadBool('General', 'PromptIptc', PromptIptc);
    WriteIptcIIM := ReadBool('General', 'WriteIptcIIM', WriteIptcIIM);
    WriteIptcNef := ReadBool('General', 'WriteIptcNef', WriteIptcNef);
    WriteExifOwner := ReadBool('General', 'WriteExifOwner', WriteExifOwner);
    ExifAuthor := ReadString('General', 'ExifAuthor', ExifAuthor);
    ExifCopyright := ReadString('General', 'ExifCopyright', ExifCopyright);
    FirstRunDone := ReadBool('General', 'FirstRunDone', FirstRunDone);
    LoadLastAtStartup := ReadBool('General', 'LoadLastAtStartup', LoadLastAtStartup);
    SingleInstance := ReadBool('General', 'SingleInstance', SingleInstance);
    LastSource := ReadString('General', 'LastSource', LastSource);

    AutoAtStartup := ReadBool('Automation', 'AutoAtStartup', AutoAtStartup);
    AutoMenu := ReadBool('Automation', 'AutoMenu', AutoMenu);
    AutoPrompt := ReadBool('Automation', 'AutoPrompt', AutoPrompt);
    AutoDownload := ReadBool('Automation', 'AutoDownload', AutoDownload);
    AutoDelete := ReadBool('Automation', 'AutoDelete', AutoDelete);
    AutoSoftEject := ReadBool('Automation', 'AutoSoftEject', AutoSoftEject);
    AutoLaunch := ReadBool('Automation', 'AutoLaunch', AutoLaunch);
    AutoExit := ReadBool('Automation', 'AutoExit', AutoExit);

    CustomEnabled := ReadBool('Custom', 'Enabled', CustomEnabled);
    CustomCaption := ReadString('Custom', 'Caption', CustomCaption);
    CustomCmd := ReadString('Custom', 'Command', CustomCmd);

    IdentifyBySerial := ReadBool('Mapping', 'IdentifyBySerial', IdentifyBySerial);
    PromptNewCamera := ReadBool('Mapping', 'PromptNewCamera', PromptNewCamera);

    ShowDownloaded := ReadBool('View', 'ShowDownloaded', ShowDownloaded);
    ShowDuplicates := ReadBool('View', 'ShowDuplicates', ShowDuplicates);
    ShowDateSelector := ReadBool('View', 'ShowDateSelector', ShowDateSelector);
    ViewMode := ReadInteger('View', 'ThumbView', ViewMode);
    if (ViewMode < 0) or (ViewMode > 2) then ViewMode := 2;
    for I := 0 to FileTypeCount - 1 do
      TypeOn[I] := ReadBool('FileTypes', FileTypeKeys[I], TypeOn[I]);
    LoggingOn := ReadBool('General', 'Logging', LoggingOn);

    if SectionExists('JobHistory') then LoadList(Ini, 'JobHistory', JobHistory);
    if SectionExists('Mappings') then LoadList(Ini, 'Mappings', Mappings);
    if SectionExists('Plugins') then LoadList(Ini, 'Plugins', Plugins);
    if SectionExists('PluginOpts') then LoadList(Ini, 'PluginOpts', PluginOpts);
    if SectionExists('Iptc') then LoadList(Ini, 'Iptc', Iptc);
    if SaveDateJobCodes and SectionExists('DateJobCodes') then
      LoadList(Ini, 'DateJobCodes', DateJobCodes);
  end;
  if Mappings.Count = 0 then
    Mappings.Add(MapJoin('Default', '{T1}', '{T1}'));
  for I := Low(DefaultPlugins) to High(DefaultPlugins) do
    if Plugins.IndexOfName(DefaultPlugins[I]) < 0 then
      Plugins.Add(DefaultPlugins[I] + '=0');
end;

procedure TAppSettings.SaveTo(Ini: TCustomIniFile);
var
  I: Integer;
begin
  with Ini do
  begin
    WriteString('Path', 'DownloadDir', DownloadDir);
    WriteString('Path', 'FileNameMask', FileNameMask);
    WriteString('Path', 'JobCode', JobCode);
    WriteBool('Path', 'PromptJobCode', PromptJobCode);
    WriteInteger('Path', 'SeqStart', SeqStart);
    WriteInteger('Path', 'SeqNext', SeqNext);

    WriteInteger('General', 'SourceMode', Ord(SourceMode));
    WriteString('General', 'DriveLetters', DriveLetters);
    WriteBool('General', 'DisablePTP', DisablePTP);
    WriteBool('General', 'SaveReadOnly', SaveReadOnly);
    WriteBool('General', 'PreserveReadOnly', PreserveReadOnly);
    WriteBool('General', 'PromptProfile', PromptProfile);
    WriteBool('General', 'IgnoreSizeCheck', IgnoreSizeCheck);
    WriteBool('General', 'AutoRotate', AutoRotate);
    WriteBool('General', 'RenameJpe', RenameJpe);
    WriteBool('General', 'LowerName', LowerName);
    WriteBool('General', 'LowerExt', LowerExt);
    WriteBool('General', 'UseCaptureTime', UseCaptureTime);
    WriteBool('General', 'SaveDateJobCodes', SaveDateJobCodes);
    WriteBool('General', 'WriteExifText', WriteExifText);
    WriteBool('General', 'AutoEject', AutoEject);
    WriteBool('General', 'ScanWholeDisk', ScanWholeDisk);
    WriteBool('General', 'AddIptc', AddIptc);
    WriteBool('General', 'PromptIptc', PromptIptc);
    WriteBool('General', 'WriteIptcIIM', WriteIptcIIM);
    WriteBool('General', 'WriteIptcNef', WriteIptcNef);
    WriteBool('General', 'WriteExifOwner', WriteExifOwner);
    WriteString('General', 'ExifAuthor', ExifAuthor);
    WriteString('General', 'ExifCopyright', ExifCopyright);
    WriteBool('General', 'FirstRunDone', FirstRunDone);
    WriteBool('General', 'LoadLastAtStartup', LoadLastAtStartup);
    WriteBool('General', 'SingleInstance', SingleInstance);
    WriteString('General', 'LastSource', LastSource);

    WriteBool('Automation', 'AutoAtStartup', AutoAtStartup);
    WriteBool('Automation', 'AutoMenu', AutoMenu);
    WriteBool('Automation', 'AutoPrompt', AutoPrompt);
    WriteBool('Automation', 'AutoDownload', AutoDownload);
    WriteBool('Automation', 'AutoDelete', AutoDelete);
    WriteBool('Automation', 'AutoSoftEject', AutoSoftEject);
    WriteBool('Automation', 'AutoLaunch', AutoLaunch);
    WriteBool('Automation', 'AutoExit', AutoExit);

    WriteBool('Custom', 'Enabled', CustomEnabled);
    WriteString('Custom', 'Caption', CustomCaption);
    WriteString('Custom', 'Command', CustomCmd);

    WriteBool('Mapping', 'IdentifyBySerial', IdentifyBySerial);
    WriteBool('Mapping', 'PromptNewCamera', PromptNewCamera);

    WriteBool('View', 'ShowDownloaded', ShowDownloaded);
    WriteBool('View', 'ShowDuplicates', ShowDuplicates);
    WriteBool('View', 'ShowDateSelector', ShowDateSelector);
    WriteInteger('View', 'ThumbView', ViewMode);
    for I := 0 to FileTypeCount - 1 do
      WriteBool('FileTypes', FileTypeKeys[I], TypeOn[I]);
    WriteBool('General', 'Logging', LoggingOn);
  end;
  SaveList(Ini, 'JobHistory', JobHistory);
  SaveList(Ini, 'Mappings', Mappings);
  SaveList(Ini, 'Plugins', Plugins);
  SaveList(Ini, 'PluginOpts', PluginOpts);
  SaveList(Ini, 'Iptc', Iptc);
  if SaveDateJobCodes then
    SaveList(Ini, 'DateJobCodes', DateJobCodes)
  else
    Ini.EraseSection('DateJobCodes');
end;

procedure TAppSettings.LoadFromFile(const AFileName: string);
var
  Ini: TMemIniFile;
begin
  if not FileExistsUTF8(AFileName) then Exit;
  Ini := TMemIniFile.Create(AFileName);
  try
    LoadFrom(Ini);
  finally
    Ini.Free;
  end;
end;

procedure TAppSettings.SaveToFile(const AFileName: string);
var
  Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create(AFileName);
  try
    SaveTo(Ini);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function TAppSettings.PluginEnabled(const AName: string): Boolean;
begin
  Result := Plugins.Values[AName] = '1';
end;

end.
