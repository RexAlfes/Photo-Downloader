unit uExtPlugin;

{$mode objfpc}{$H+}

(* External-program plug-ins: a small text file "<key>.plugin.ini" in a plugins folder describes a
  program that is run on each downloaded file, for example Adobe DNG Converter or dnglab. No code of
  the plug-in is loaded into Photo Downloader; the program is started as a separate process, without a
  shell, with its arguments passed one by one (so a file name cannot run other commands).

  [Plugin]
  Name=DNG Converter (Adobe)            shown on the Plug-ins tab
  Description=...                       shown below the list
  Version=1.0.0
  Hook=AfterFile                        run after each file is downloaded (the only hook so far)
  FileTypes=.nef;.cr2;...               extensions it works on ('' = every file)
  Platforms=windows;linux               systems it is offered on ('' = every system)
  [Run]
  Windows=C:\Program Files\...\x.exe    program on Windows (a bare name is searched on the PATH)
  Linux=dnglab                          program on Linux
  Args=-c -d "{folder}" "{file}"        arguments; quotes keep a path with blanks together
  Output={folder}{sep}{name}.dng        optional: the file the program makes (checked afterwards;
                                        when it already exists the step is skipped)
  TimeoutSec=300                        the program is stopped after this time (failed)

  Placeholders: {file} the downloaded file, {folder} its folder (no closing separator), {name} its
  name without extension, {ext} its extension without the dot, {source} the original file on the
  card, {sep} the folder separator of this system. Exit code 0 means success. *)

interface

uses
  Classes, SysUtils;

type
  { One external-program plug-in, read from its .plugin.ini file }
  TExtPlugin = class
  public
    Key: string;  // file name without ".plugin.ini": the key on the Plug-ins tab and in the settings
    FileName: string;  // full path of the .plugin.ini file
    Name, Description, Version, Hook: string;  // [Plugin] values
    FileTypes, Platforms: string;  // ';ext;ext;' and ';windows;linux;' in lower case ('' = all)
    ProgWindows, ProgLinux, Args, Output: string;  // [Run] values
    TimeoutSec: Integer;  // longest run time in seconds
    constructor Create(const AKey, AFileName: string);  // reads the file
    function Available: Boolean;  // True when the plug-in is offered on this system
    function ProgramPath(const Opts: string): string;  // the program to run ('' = not found)
    function ProgramSetting(const Opts: string): string;  // the program as set (for messages)
    function Handles(const AFileName: string): Boolean;  // True for the file types it works on
    function Expand(const S, AFile, ASource: string): string;  // fills in the placeholders
    { Runs the program on DestFile. Opts: the plug-in options (key=value lines, Program= overrides the
      program). Pump is called every few milliseconds to keep the window alive. Returns 1 = done,
      0 = skipped (Msg says why), -1 = failed (Msg says why). OutFile: the file the program made. }
    function Run(const Opts, DestFile, SourceFile: string; Pump: TThreadMethod;
      out OutFile, Msg: string): Integer;
  end;

{ Splits a command line into arguments: blanks separate them, double quotes keep blanks inside one. }
function SplitArgs(const S: string): TStringArray;

implementation

uses
  IniFiles, Process, FileUtil, LazFileUtils;

{ Lower-case list ';a;b;' from 'a;b' or 'a,b' ('' stays ''). }
function NormList(const S: string): string;
var
  T: string;  // T: the cleaned text
begin
  T := LowerCase(StringReplace(StringReplace(S, ',', ';', [rfReplaceAll]), ' ', '', [rfReplaceAll]));  // one separator, no blanks
  if T = '' then Exit('');  // empty: all
  Result := ';' + T + ';';  // with separators at both ends
end;

{ The value of one key in key=value lines. }
function OptValue(const Lines, Key: string): string;
var
  L: TStringList;  // L: the lines
begin
  L := TStringList.Create;  // create the list
  try
    L.Text := Lines;  // split into lines
    Result := L.Values[Key];  // the value
  finally
    L.Free;  // free the list
  end;
end;

function SplitArgs(const S: string): TStringArray;
var
  I, N: Integer;  // I: character position; N: number of arguments
  Cur: string;  // Cur: the argument being collected
  InQ, Has: Boolean;  // InQ: inside quotes; Has: an argument has started
begin
  Result := nil;  // nothing yet
  N := 0;  // no arguments
  Cur := '';  // empty
  InQ := False;  // outside quotes
  Has := False;  // no argument started
  for I := 1 to Length(S) + 1 do
  begin
    if (I > Length(S)) or ((S[I] = ' ') and not InQ) then  // end of an argument
    begin
      if Has then
      begin
        SetLength(Result, N + 1);  // room for it
        Result[N] := Cur;  // add it
        Inc(N);  // count it
      end;
      Cur := '';  // start again
      Has := False;  // no argument started
    end
    else if S[I] = '"' then
    begin
      InQ := not InQ;  // quotes on or off
      Has := True;  // "" is an empty argument
    end
    else
    begin
      Cur := Cur + S[I];  // part of the argument
      Has := True;  // started
    end;
  end;
end;

constructor TExtPlugin.Create(const AKey, AFileName: string);
var
  Ini: TMemIniFile;  // Ini: the .plugin.ini file
begin
  inherited Create;  // run the inherited constructor
  Key := AKey;  // key
  FileName := AFileName;  // path
  Ini := TMemIniFile.Create(AFileName);  // read the file
  try
    Name := Ini.ReadString('Plugin', 'Name', AKey);  // name shown
    Description := Ini.ReadString('Plugin', 'Description', '');  // text below the list
    Version := Ini.ReadString('Plugin', 'Version', '');  // version
    Hook := Ini.ReadString('Plugin', 'Hook', 'AfterFile');  // when it runs
    FileTypes := NormList(Ini.ReadString('Plugin', 'FileTypes', ''));  // extensions
    Platforms := NormList(Ini.ReadString('Plugin', 'Platforms', ''));  // systems
    ProgWindows := Ini.ReadString('Run', 'Windows', '');  // program on Windows
    ProgLinux := Ini.ReadString('Run', 'Linux', '');  // program on Linux
    Args := Ini.ReadString('Run', 'Args', '"{file}"');  // arguments
    Output := Ini.ReadString('Run', 'Output', '');  // file it makes
    TimeoutSec := Ini.ReadInteger('Run', 'TimeoutSec', 300);  // longest run time
  finally
    Ini.Free;  // close it
  end;
end;

function TExtPlugin.Available: Boolean;
begin
  {$IFDEF WINDOWS}
  Result := ((Platforms = '') or (Pos(';windows;', Platforms) > 0)) and (ProgWindows <> '');  // offered on Windows
  {$ELSE}
  Result := ((Platforms = '') or (Pos(';linux;', Platforms) > 0)) and (ProgLinux <> '');  // offered on Linux
  {$ENDIF}
end;

function TExtPlugin.ProgramSetting(const Opts: string): string;
begin
  Result := OptValue(Opts, 'Program');  // chosen in Setup...
  if Result = '' then
    {$IFDEF WINDOWS}
    Result := ProgWindows;  // from the .plugin.ini file
    {$ELSE}
    Result := ProgLinux;  // from the .plugin.ini file
    {$ENDIF}
end;

function TExtPlugin.ProgramPath(const Opts: string): string;
begin
  Result := ProgramSetting(Opts);  // as set
  if Result = '' then Exit;  // none
  if Pos(PathDelim, Result) = 0 then  // a bare name: look on the PATH
    Result := FindDefaultExecutablePath(Result)  // '' when not found
  else if not FileExistsUTF8(Result) then
    Result := '';  // not there
end;

function TExtPlugin.Handles(const AFileName: string): Boolean;
begin
  Result := (FileTypes = '') or (Pos(';' + LowerCase(ExtractFileExt(AFileName)) + ';', FileTypes) > 0);  // one of its types
end;

function TExtPlugin.Expand(const S, AFile, ASource: string): string;
begin
  Result := StringReplace(S, '{file}', AFile, [rfReplaceAll, rfIgnoreCase]);  // the downloaded file
  Result := StringReplace(Result, '{folder}', ExcludeTrailingPathDelimiter(ExtractFilePath(AFile)), [rfReplaceAll, rfIgnoreCase]);  // its folder
  Result := StringReplace(Result, '{name}', ChangeFileExt(ExtractFileName(AFile), ''), [rfReplaceAll, rfIgnoreCase]);  // its name
  Result := StringReplace(Result, '{ext}', Copy(ExtractFileExt(AFile), 2, MaxInt), [rfReplaceAll, rfIgnoreCase]);  // its extension
  Result := StringReplace(Result, '{source}', ASource, [rfReplaceAll, rfIgnoreCase]);  // the original on the card
  Result := StringReplace(Result, '{sep}', PathDelim, [rfReplaceAll, rfIgnoreCase]);  // folder separator
end;

function TExtPlugin.Run(const Opts, DestFile, SourceFile: string; Pump: TThreadMethod;
  out OutFile, Msg: string): Integer;
var
  P: TProcess;  // P: the running program
  Prog, Outp, A, Chunk: string;  // Prog: program; Outp: what it printed; A: one argument; Chunk: one block read
  Buf: array[0..4095] of Char;  // Buf: read buffer
  N: Integer;  // N: bytes read
  T0: QWord;  // T0: start time

  { Reads what the program printed so far (so its output pipe never fills up). }
  procedure ReadOutput;
  begin
    while P.Output.NumBytesAvailable > 0 do
    begin
      N := P.Output.Read(Buf, SizeOf(Buf));  // read a block
      if N <= 0 then Break;
      SetString(Chunk, PChar(@Buf[0]), N);  // the bytes as text
      if Length(Outp) < 4000 then Outp := Outp + Chunk;  // keep the start of it
    end;
  end;

begin
  Result := -1;  // assume failure
  Msg := '';  // nothing yet
  Outp := '';  // nothing printed yet
  OutFile := '';  // no output file yet
  if Output <> '' then
  begin
    OutFile := Expand(Output, DestFile, SourceFile);  // the file the program makes
    if FileExistsUTF8(OutFile) then  // made before (for example an earlier download)
    begin
      Msg := ExtractFileName(OutFile) + ' already exists';  // why skipped
      Exit(0);
    end;
  end;
  Prog := ProgramPath(Opts);  // the program
  if Prog = '' then
  begin
    Msg := 'program not found: ' + ProgramSetting(Opts) + ' (choose it with Setup... on the Plug-ins tab)';  // why
    Exit;
  end;
  P := TProcess.Create(nil);  // the process
  try
    P.Executable := Prog;  // program
    for A in SplitArgs(Expand(Args, DestFile, SourceFile)) do P.Parameters.Add(A);  // arguments one by one
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];  // read its output, no console window
    P.ShowWindow := swoHide;  // no window
    try
      P.Execute;  // start it
    except
      on E: Exception do begin Msg := 'cannot start ' + Prog + ': ' + E.Message; Exit; end;
    end;
    T0 := GetTickCount64;  // start time
    while P.Running do  // wait, keeping the window alive
    begin
      ReadOutput;  // empty the pipe
      if Assigned(Pump) then Pump();  // let the window update
      if GetTickCount64 - T0 > QWord(TimeoutSec) * 1000 then  // runs too long
      begin
        P.Terminate(1);  // stop it
        Msg := Format('stopped after %d seconds (TimeoutSec)', [TimeoutSec]);  // why
        Exit;
      end;
      Sleep(20);  // do not keep the processor busy
    end;
    ReadOutput;  // the rest of the output
    if P.ExitCode <> 0 then  // the program reports an error
    begin
      Msg := Format('exit code %d: %s', [P.ExitCode, Trim(Copy(Outp, 1, 300))]);  // why
      Exit;
    end;
  finally
    P.Free;  // free the process
  end;
  if (OutFile <> '') and not FileExistsUTF8(OutFile) then  // the program did not make its file
  begin
    Msg := ExtractFileName(OutFile) + ' was not made: ' + Trim(Copy(Outp, 1, 300));  // why
    Exit;
  end;
  Result := 1;  // done
end;

end.
