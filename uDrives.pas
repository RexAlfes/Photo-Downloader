unit uDrives;

{$mode objfpc}{$H+}

{ Kept separate from the LCL units because the Windows unit would shadow
  names such as TBitmap if it were mixed into them. }

interface

uses
  Classes, SysUtils{$IFDEF WINDOWS}, Windows, ShellAPI{$ENDIF};

procedure ListRemovableDrives(L: TStrings);   // roots such as 'H:\'
function EjectDrive(const Root: string): Boolean;
procedure LaunchCommand(const CmdLine: string);
{ Opens the file manager with the file selected (Windows). False if not supported here. }
function RevealFile(const FileName: string): Boolean;

implementation

uses
  Process;

procedure ListRemovableDrives(L: TStrings);
{$IFDEF WINDOWS}
var
  C: Char;
  Root: string;
begin
  L.Clear;
  for C := 'A' to 'Z' do
  begin
    Root := C + ':\';
    if GetDriveType(PChar(Root)) = DRIVE_REMOVABLE then
      L.Add(Root);
  end;
end;
{$ELSE}
begin
  L.Clear;  // other platforms: use File > Open Source Directory
end;
{$ENDIF}

function EjectDrive(const Root: string): Boolean;
var
  Outp: string;
begin
  {$IFDEF WINDOWS}
  Result := RunCommand('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command',
     '(New-Object -comObject Shell.Application).Namespace(17).ParseName(''' +
       Copy(Root, 1, 2) + ''').InvokeVerb(''Eject'')'],
    Outp, [poNoConsole]);
  {$ELSE}
  Result := RunCommand('eject', [Root], Outp, [poNoConsole]);
  {$ENDIF}
end;

procedure LaunchCommand(const CmdLine: string);
var
  P: TProcess;
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  P := TProcess.Create(nil);
  try
    CommandToList(CmdLine, Parts);
    if Parts.Count = 0 then Exit;
    P.Executable := Parts[0];
    for I := 1 to Parts.Count - 1 do
      P.Parameters.Add(Parts[I]);
    P.Options := [];
    P.Execute;
  finally
    P.Free;
    Parts.Free;
  end;
end;

function RevealFile(const FileName: string): Boolean;
{$IFDEF WINDOWS}
var
  Params: UnicodeString;
begin
  Params := UTF8Decode('/select,"' + FileName + '"');
  Result := ShellExecuteW(0, 'open', 'explorer.exe', PWideChar(Params), nil, SW_SHOWNORMAL) > 32;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

end.
