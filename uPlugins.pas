unit uPlugins;

{$mode objfpc}{$H+}

{ Plug-in libraries: DLL files on Windows, .so files on Linux, kept in a "plugins" folder next to
  the settings file or next to the program.

  A library adds tokens to the folder and file name templates and can ask for values in a window
  that the program draws from the library's field list (so a library needs no window code).
  The interface uses plain C types only (cdecl, UTF-8 text, key=value lines, buffers owned by the
  program), so libraries can be written in any language. See docs/Plugin_Developer_Manual.md.

  Each library is listed on the Plug-ins tab under the key "<file name>" without "lib" prefix and
  extension. A new library is switched off and is not loaded at all until the user switches it on
  (the switch-on asks for confirmation, showing the full path). Libraries are never loaded from
  the image source. When a library cannot be loaded it is switched off and the reason is reported. }

interface

uses
  Classes, SysUtils, Math, dynlibs, FileUtil, LazFileUtils, uSettings, uItems;

const
  PluginApiVersion = 1;  // interface version this program understands

type
  { Exported functions of a plug-in library (all cdecl; text is UTF-8) }
  TPdApiVersion = function: Integer; cdecl;  // returns the interface version
  TPdText = function(Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;  // pd_info: returns the needed length
  TPdToken = function(Token, Context: PAnsiChar; Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;  // -1 = no value
  TPdCheck = function(Values: PAnsiChar; Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;  // checks prompt values
  TPdLogo = function(Buf: PByte; BufLen: Integer): Integer; cdecl;  // returns the size of the PNG logo

  { One field of a plug-in's prompt window }
  TPluginField = record
    Key: string;  // value name
    Kind: string;  // choice, combo or text
    Caption: string;  // label shown in front of the control
    Values, Labels: TStringArray;  // list entries: value and the text shown for it
    Default: string;  // value used when none is stored yet
    Upper: Boolean;  // flag "upper": typed text is shown and kept in capitals
    FolderTokens: string;  // check fields, flag "folder=A;B": when checked, {A} is the last folder of the download path (B ... are removed there)
  end;

  { A plug-in library found in a plugins folder }
  TLibPlugin = class
  private
    FLib: TLibHandle;  // library handle (NilHandle = not loaded)
    FToken: TPdToken;  // pd_token
    FCheck: TPdCheck;  // pd_check (may be nil)
  public
    Key: string;  // key on the Plug-ins tab and in the settings
    FileName: string;  // full path of the library
    Loaded: Boolean;  // True when the library is loaded and usable
    Info: TStringList;  // key=value lines from pd_info
    Tokens: TStringList;  // token names the library gives (sorted, case-insensitive)
    Fields: array of TPluginField;  // fields of the prompt window
    Logo: TMemoryStream;  // PNG logo (nil = none)
    constructor Create(const AKey, AFileName: string);
    destructor Destroy; override;
    function Load(out Err: string): Boolean;  // loads the library and reads its information
    function DisplayName: string;  // name shown on the Plug-ins tab
    function Description: string;  // description shown on the Plug-ins tab
    function Token(const Tok, Context: string; out Value: string): Boolean;  // value of one token
    function Check(const Values: string): string;  // checks prompt values; returns result lines
  end;

{ Looks for plug-in libraries, lists new ones (switched off) in S.Plugins and loads the switched-on
  ones. Returns the problems found (one line each, '' = none); failed libraries are switched off. }
function LoadPlugins(S: TAppSettings): string;
{ The library plug-in with this key, or nil }
function FindLibPlugin(const Key: string): TLibPlugin;
{ The folders searched for plug-in libraries (for messages and the manual) }
function PluginFolders: string;
{ Stored prompt values of a plug-in as key=value lines (Opts: the plug-in options, S.PluginOpts) }
function PluginValues(Opts: TStrings; const Key: string): string;
{ Stores the prompt values of a plug-in (key=value lines) in the plug-in options }
procedure SetPluginValues(Opts: TStrings; const Key, Values: string);
{ The value of one key in key=value lines }
function LineValue(const Lines, Key: string): string;
{ Switched-on library plug-ins that have prompt fields }
function PromptPlugins(S: TAppSettings): TList;

implementation

var
  Libs: TList = nil;  // every library found (TLibPlugin)
  TokenSettings: TAppSettings = nil;  // settings the token lookup uses (set by LoadPlugins)

{ ---- small helpers ---- }

{ Splits Text at Sep into an array (empty text gives an empty array). }
function SplitText(const Text: string; Sep: Char): TStringArray;
begin
  Result := nil;  // nothing yet
  if Text = '' then
    Result := nil  // nothing to split
  else
    Result := Text.Split([Sep]);  // split at the separator
end;

{ Calls a text function of the library until the buffer is large enough; returns the text. }
function CallText(F: TPdText): string;
var
  N: Integer;  // N: needed length
begin
  Result := '';  // nothing yet
  SetLength(Result, 4096);  // first try with 4 KB
  N := F(PAnsiChar(Result), Length(Result) + 1);  // ask for the text
  if N < 0 then Exit('');  // no text
  if N > Length(Result) then  // buffer too small
  begin
    SetLength(Result, N);  // make room for all of it
    N := F(PAnsiChar(Result), Length(Result) + 1);  // ask again
    if N < 0 then Exit('');  // no text
  end;
  SetLength(Result, Min(N, Length(Result)));  // cut to the real length
end;

{ The value of one key in key=value lines. }
function LineValue(const Lines, Key: string): string;
var
  L: TStringList;  // L: the lines
begin
  L := TStringList.Create;  // create the list
  try
    L.Text := Lines;  // split into lines
    Result := L.Values[Key];  // value of the key
  finally
    L.Free;  // free the list
  end;
end;

{ Escapes the characters that separate values in the settings file. }
function EscapeValue(const V: string): string;
begin
  Result := StringReplace(V, '%', '%25', [rfReplaceAll]);  // percent first
  Result := StringReplace(Result, ';', '%3B', [rfReplaceAll]);  // value separator
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);  // no line breaks
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);  // no line breaks
end;

{ Undoes EscapeValue. }
function UnescapeValue(const V: string): string;
begin
  Result := StringReplace(V, '%3B', ';', [rfReplaceAll, rfIgnoreCase]);  // value separator
  Result := StringReplace(Result, '%25', '%', [rfReplaceAll]);  // percent last
end;

{ ---- TLibPlugin ---- }

{ Creates the entry of a library that has not been loaded yet. }
constructor TLibPlugin.Create(const AKey, AFileName: string);
begin
  inherited Create;  // run the inherited constructor
  Key := AKey;  // key on the Plug-ins tab
  FileName := AFileName;  // full path
  FLib := NilHandle;  // not loaded
  Info := TStringList.Create;  // information lines
  Tokens := TStringList.Create;  // token names
  Tokens.Sorted := True;  // fast lookup
  Tokens.CaseSensitive := False;  // {UAS.Dist} and {uas.dist} are the same
end;

{ Frees the information; the library stays loaded until the program ends. }
destructor TLibPlugin.Destroy;
begin
  Info.Free;  // free the information
  Tokens.Free;  // free the token names
  Logo.Free;  // free the logo (may be nil)
  inherited Destroy;  // run the inherited destructor
end;

{ Loads the library, checks its interface version and reads its information, fields and logo. }
function TLibPlugin.Load(out Err: string): Boolean;
var
  ApiVer: TPdApiVersion;  // ApiVer: pd_api_version
  InfoF: TPdText;  // InfoF: pd_info
  LogoF: TPdLogo;  // LogoF: pd_logo
  I, N, F: Integer;  // I: line index; N: logo size; F: field index
  Parts: TStringArray;  // Parts: parts of a Field= line
  Items, Pair: TStringArray;  // Items: list entries; Pair: value and label of one entry
  T: string;  // T: one token name
begin
  Err := '';  // no error yet
  if Loaded then Exit(True);  // already loaded
  FLib := LoadLibrary(FileName);  // load the library
  if FLib = NilHandle then
  begin
    Err := 'the library cannot be loaded (wrong system, 32-bit, or a missing library it needs)';  // explain
    Exit(False);
  end;
  ApiVer := TPdApiVersion(GetProcedureAddress(FLib, 'pd_api_version'));  // interface version
  InfoF := TPdText(GetProcedureAddress(FLib, 'pd_info'));  // information
  FToken := TPdToken(GetProcedureAddress(FLib, 'pd_token'));  // token values
  FCheck := TPdCheck(GetProcedureAddress(FLib, 'pd_check'));  // prompt check (optional)
  LogoF := TPdLogo(GetProcedureAddress(FLib, 'pd_logo'));  // logo (optional)
  if (ApiVer = nil) or (InfoF = nil) then  // not a Photo Downloader plug-in
    Err := 'not a Photo Downloader plug-in (pd_api_version or pd_info missing)'
  else if ApiVer() <> PluginApiVersion then  // made for another interface version
    Err := Format('made for plug-in interface %d; this program supports %d', [ApiVer(), PluginApiVersion]);
  if Err <> '' then
  begin
    UnloadLibrary(FLib);  // give the library back
    FLib := NilHandle;  // not loaded
    Exit(False);
  end;
  Info.Text := CallText(InfoF);  // read the information lines
  Tokens.Clear;  // start with no tokens
  for T in SplitText(Info.Values['Tokens'], ';') do  // every token name
    if Trim(T) <> '' then Tokens.Add(Trim(T));  // add it
  SetLength(Fields, 0);  // no fields yet
  for I := 0 to Info.Count - 1 do  // look for Field= lines (there can be several)
    if Info.Names[I] = 'Field' then
    begin
      Parts := Info.ValueFromIndex[I].Split(['|']);  // key|kind|label|entries|default|flags
      if Length(Parts) < 3 then Continue;  // not a usable field
      F := Length(Fields);  // index of the new field
      SetLength(Fields, F + 1);  // add the field
      Fields[F].Key := Parts[0];  // value name
      Fields[F].Kind := LowerCase(Parts[1]);  // control type
      Fields[F].Caption := Parts[2];  // label
      if Length(Parts) > 4 then Fields[F].Default := Parts[4];  // default value
      if Length(Parts) > 5 then  // flags, separated by commas
        for T in Parts[5].Split([',']) do
          if SameText(Trim(T), 'upper') then Fields[F].Upper := True  // capitals only
          else if SameText(Copy(Trim(T), 1, 7), 'folder=') then Fields[F].FolderTokens := Copy(Trim(T), 8, MaxInt);  // folder tokens
      Items := nil;  // no entries yet
      if Length(Parts) > 3 then Items := SplitText(Parts[3], ',');  // entries: value or value:label
      SetLength(Fields[F].Values, Length(Items));  // room for the values
      SetLength(Fields[F].Labels, Length(Items));  // room for the labels
      for N := 0 to High(Items) do  // every entry
      begin
        Pair := Items[N].Split([':'], 2);  // value and label
        Fields[F].Values[N] := Pair[0];  // value
        if Length(Pair) > 1 then Fields[F].Labels[N] := Pair[1] else Fields[F].Labels[N] := Pair[0];  // label (or the value)
      end;
    end;
  if LogoF <> nil then  // the library has a logo
  begin
    N := LogoF(nil, 0);  // size of the logo
    if (N > 0) and (N < 4 * 1024 * 1024) then  // a sensible size
    begin
      Logo := TMemoryStream.Create;  // create the stream
      Logo.SetSize(N);  // make room
      if LogoF(PByte(Logo.Memory), N) <> N then FreeAndNil(Logo);  // read it; drop it when the size changed
    end;
  end;
  Loaded := FToken <> nil;  // usable when it gives token values
  if not Loaded then Err := 'pd_token missing';  // tell why not
  Result := Loaded;  // done
end;

{ Name shown on the Plug-ins tab: the library's own name, or the file name before loading. }
function TLibPlugin.DisplayName: string;
begin
  if Loaded and (Info.Values['Name'] <> '') then
    Result := Info.Values['Name'] + ' (library ' + Key + ')'  // name from the library
  else
    Result := Key + ' (library)';  // not loaded yet
end;

{ Description shown on the Plug-ins tab. }
function TLibPlugin.Description: string;
begin
  if Loaded then
    Result := Info.Values['Description'] + #13#10 + 'Version ' + Info.Values['Version'] +  // the library's own text
      '. Tokens: {' + StringReplace(Info.Values['Tokens'], ';', '} {', [rfReplaceAll]) + '}'
  else
    Result := 'Plug-in library, not loaded. Switch it on to load it.';  // not loaded yet
  Result := Result + #13#10 + 'File: ' + FileName;  // where it is
end;

{ Asks the library for the value of one token; False when it has none. }
function TLibPlugin.Token(const Tok, Context: string; out Value: string): Boolean;
var
  N: Integer;  // N: needed length
begin
  Value := '';  // no value yet
  Result := False;  // assume none
  if not Loaded then Exit;  // library not usable
  SetLength(Value, 256);  // values are short
  N := FToken(PAnsiChar(Tok), PAnsiChar(Context), PAnsiChar(Value), Length(Value) + 1);  // ask the library
  if N < 0 then Exit;  // no value
  if N > Length(Value) then  // buffer too small
  begin
    SetLength(Value, N);  // make room
    N := FToken(PAnsiChar(Tok), PAnsiChar(Context), PAnsiChar(Value), Length(Value) + 1);  // ask again
    if N < 0 then Exit;  // no value
  end;
  SetLength(Value, Min(N, Length(Value)));  // cut to the real length
  Result := True;  // value found
end;

{ Lets the library check prompt values; returns its result lines (Preview=, Error=, Set.<key>=). }
function TLibPlugin.Check(const Values: string): string;
var
  N: Integer;  // N: needed length
begin
  Result := '';  // nothing yet
  if (not Loaded) or (FCheck = nil) then Exit;  // no check function
  SetLength(Result, 4096);  // first try with 4 KB
  N := FCheck(PAnsiChar(Values), PAnsiChar(Result), Length(Result) + 1);  // ask the library
  if N < 0 then Exit('');  // nothing returned
  if N > Length(Result) then  // buffer too small
  begin
    SetLength(Result, N);  // make room
    N := FCheck(PAnsiChar(Values), PAnsiChar(Result), Length(Result) + 1);  // ask again
    if N < 0 then Exit('');  // nothing returned
  end;
  SetLength(Result, Min(N, Length(Result)));  // cut to the real length
end;

{ ---- stored values ---- }

{ Stored prompt values of a plug-in as key=value lines (stored as key=value;key=value). }
function PluginValues(Opts: TStrings; const Key: string): string;
var
  P: string;  // P: one key=value pair
begin
  Result := '';  // nothing yet
  for P in SplitText(Opts.Values[Key], ';') do  // every pair
    if P <> '' then Result := Result + UnescapeValue(P) + LineEnding;  // one line each
end;

{ Stores the prompt values of a plug-in (key=value lines). }
procedure SetPluginValues(Opts: TStrings; const Key, Values: string);
var
  L: TStringList;  // L: the lines
  I: Integer;  // I: line index
  V: string;  // V: stored text
begin
  L := TStringList.Create;  // create the list
  try
    L.Text := Values;  // split into lines
    V := '';  // nothing yet
    for I := 0 to L.Count - 1 do  // every line
      if Pos('=', L[I]) > 1 then  // a key=value line
      begin
        if V <> '' then V := V + ';';  // separator
        V := V + EscapeValue(L[I]);  // add the pair
      end;
    Opts.Values[Key] := V;  // store it ('' removes the entry)
  finally
    L.Free;  // free the list
  end;
end;

{ ---- finding and loading ---- }

{ The folders searched for plug-in libraries. }
function PluginFolderList: TStringArray;
begin
  Result := nil;  // nothing yet
  SetLength(Result, 2);  // two places
  Result[0] := ConfigDir + 'plugins' + PathDelim;  // next to the settings file
  Result[1] := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'plugins' + PathDelim;  // next to the program
end;

{ The folders searched for plug-in libraries, one per line. }
function PluginFolders: string;
var
  F: string;  // F: one folder
begin
  Result := '';  // nothing yet
  for F in PluginFolderList do Result := Result + F + LineEnding;  // add each folder
end;

{ The library plug-in with this key, or nil. }
function FindLibPlugin(const Key: string): TLibPlugin;
var
  I: Integer;  // I: list index
begin
  Result := nil;  // not found yet
  if Libs = nil then Exit;  // nothing loaded
  for I := 0 to Libs.Count - 1 do  // every library
    if SameText(TLibPlugin(Libs[I]).Key, Key) then Exit(TLibPlugin(Libs[I]));  // found
end;

{ Key of a library file: its name without "lib" prefix (Linux) and extension. }
function LibKey(const FileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(FileName), '');  // name without extension
  {$IFDEF UNIX}
  if (Length(Result) > 3) and (Copy(Result, 1, 3) = 'lib') then Delete(Result, 1, 3);  // libname.so -> name
  {$ENDIF}
end;

{ Value of a plug-in token for an item (installed as uItems.PluginTokenHook). }
function LibTokenValue(const Tok: string; Item: TImageItem; out Value: string): Boolean;
var
  I: Integer;  // I: list index
  P: TLibPlugin;  // P: one library
  Ctx: string;  // Ctx: file details and stored values as key=value lines
begin
  Result := False;  // no value yet
  Value := '';  // nothing yet
  if (Libs = nil) or (TokenSettings = nil) then Exit;  // no plug-ins
  for I := 0 to Libs.Count - 1 do  // every library
  begin
    P := TLibPlugin(Libs[I]);  // the library
    if not (P.Loaded and TokenSettings.PluginEnabled(P.Key)) then Continue;  // only switched-on, loaded libraries
    if P.Tokens.IndexOf(Tok) < 0 then Continue;  // not one of its tokens
    Ctx := PluginValues(TokenSettings.PluginOpts, P.Key);  // the stored prompt values
    if Item <> nil then  // details of the file
      Ctx := Ctx +
        'FileName=' + Item.FileName + LineEnding +  // original file name
        'Path=' + Item.FullPath + LineEnding +  // full path, so the plug-in can read the file itself
        'Size=' + IntToStr(Item.Size) + LineEnding +  // file size in bytes
        'Ext=' + LowerCase(ExtractFileExt(Item.FileName)) + LineEnding +  // extension, lower case, with the dot
        'IsVideo=' + IntToStr(Ord(Item.IsVideo)) + LineEnding +  // 1 for a video
        'Camera=' + Item.Camera + LineEnding +  // camera model
        'Serial=' + Item.Serial + LineEnding +  // camera serial number
        'Date=' + FormatDateTime('yyyymmdd', Item.CaptureTime) + LineEnding;  // capture date
    Result := P.Token(Tok, Ctx, Value);  // ask the library
    if Result then Exit;  // value found
  end;
end;

{ True for the names of the plug-ins built into the program. }
function IsBuiltInPlugin(const Name: string): Boolean;
var
  I: Integer;  // I: list index
begin
  Result := False;  // not found yet
  for I := Low(DefaultPlugins) to High(DefaultPlugins) do
    if SameText(DefaultPlugins[I], Name) then Exit(True);  // a built-in plug-in
end;

{ Looks for plug-in libraries and loads the switched-on ones; returns the problems found. }
function LoadPlugins(S: TAppSettings): string;
var
  Dir, Ext, Err: string;  // Dir: plug-in folder; Ext: library extension; Err: load error
  Found: TStringList;  // Found: library files in one folder
  I: Integer;  // I: file index
  P: TLibPlugin;  // P: one library
begin
  Result := '';  // no problems yet
  TokenSettings := S;  // token lookups use these settings
  if Libs = nil then Libs := TList.Create;  // the list of libraries
  {$IFDEF WINDOWS}
  Ext := '*.dll';  // Windows libraries
  {$ELSE}
  Ext := '*.so';  // Linux libraries
  {$ENDIF}
  for Dir in PluginFolderList do  // every plug-in folder
  begin
    if not DirectoryExistsUTF8(Dir) then Continue;  // no such folder
    Found := FindAllFiles(Dir, Ext, False);  // library files (no subfolders)
    try
      for I := 0 to Found.Count - 1 do  // every library file
        if FindLibPlugin(LibKey(Found[I])) = nil then  // the first file of a key wins
          Libs.Add(TLibPlugin.Create(LibKey(Found[I]), Found[I]));  // add the entry
    finally
      Found.Free;  // free the file list
    end;
  end;
  // a library whose file was removed leaves the Plug-ins list (its values stay in [PluginOpts], so
  // they are back when it is installed again); built-in plug-ins always stay
  for I := S.Plugins.Count - 1 downto 0 do
    if (not IsBuiltInPlugin(S.Plugins.Names[I])) and (FindLibPlugin(S.Plugins.Names[I]) = nil) then
    begin
      LogThumb('plug-in ' + S.Plugins.Names[I] + ': library file not found, removed from the list');  // log it
      S.Plugins.Delete(I);  // remove the entry
    end;
  // every library known must be on the Plug-ins list, also when the settings were replaced by a user
  // profile saved before the library was installed: missing ones are added, switched off
  for I := 0 to Libs.Count - 1 do
    if S.Plugins.IndexOfName(TLibPlugin(Libs[I]).Key) < 0 then
      S.Plugins.Add(TLibPlugin(Libs[I]).Key + '=0');  // listed, switched off
  for I := 0 to Libs.Count - 1 do  // load the switched-on libraries
  begin
    P := TLibPlugin(Libs[I]);  // the library
    if S.PluginEnabled(P.Key) and not P.Loaded then  // switched on, not loaded yet
      if P.Load(Err) then
        LogThumb('plug-in ' + P.Key + ': loaded ' + P.FileName)  // log the success
      else
      begin
        S.Plugins.Values[P.Key] := '0';  // switch it off (decision: a failed plug-in is switched off)
        Result := Result + P.Key + ': ' + Err + ' (' + P.FileName + ') - switched off.' + LineEnding;  // report it
        LogThumb('plug-in ' + P.Key + ': ' + Err + ' - switched off');  // log it
      end;
  end;
  PluginTokenHook := @LibTokenValue;  // plug-in tokens work from now on
end;

{ Switched-on, loaded library plug-ins that have prompt fields, in list order (caller frees the list). }
function PromptPlugins(S: TAppSettings): TList;
var
  I: Integer;  // I: list index
  P: TLibPlugin;  // P: one library
begin
  Result := TList.Create;  // the list
  for I := 0 to S.Plugins.Count - 1 do  // in the order of the Plug-ins tab
  begin
    P := FindLibPlugin(S.Plugins.Names[I]);  // library with this key
    if (P <> nil) and P.Loaded and S.PluginEnabled(P.Key) and (Length(P.Fields) > 0) then
      Result.Add(P);  // it asks for values
  end;
end;

{ Frees the library entries when the program ends. }
procedure FreeLibs;
var
  I: Integer;  // I: list index
begin
  if Libs = nil then Exit;  // nothing to free
  for I := 0 to Libs.Count - 1 do TLibPlugin(Libs[I]).Free;  // free every entry
  FreeAndNil(Libs);  // free the list
end;

finalization
  PluginTokenHook := nil;  // no more plug-in tokens
  FreeLibs;  // free the entries
end.
