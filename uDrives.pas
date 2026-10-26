unit uDrives;

{$mode objfpc}{$H+}

{ Kept separate from the LCL units because the Windows unit would shadow
  names such as TBitmap if it were mixed into them.

  Windows: drive letters, eject through PowerShell, Explorer.
  Linux:   mount points from /proc/mounts, eject with udisksctl (then gio / umount),
           xdg-open for the file manager. }

interface

uses
  Classes, SysUtils{$IFDEF WINDOWS}, Windows, ShellAPI{$ENDIF};

procedure ListRemovableDrives(L: TStrings);   // roots such as 'H:\' or '/media/user/CARD/'
function EjectDrive(const Root: string): Boolean;
procedure LaunchCommand(const CmdLine: string);
{ Opens the file manager with the file selected (Windows) or its folder open (Linux). }
function RevealFile(const FileName: string): Boolean;
{ The drive root (Windows, 'C:\') or the mount point (Linux, '/media/user/CARD/') that holds
  Path, with a trailing path delimiter; '' when it cannot be told. }
function MountPointOf(const Path: string): string;
{ True for a memory card or other removable storage (never for the system disk). }
function IsRemovableMount(const MountPoint: string): Boolean;

implementation

uses
  Process;

{$IFDEF UNIX}
type
  TMountInfo = record
    Dev, Dir, FsType: string;
  end;
  TMountList = array[0..255] of TMountInfo;

{ Names in /proc/mounts escape space, tab, newline and backslash as \040 \011 \012 \134 }
function UnescapeMount(const S: string): string;
begin
  Result := StringReplace(S, '\040', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '\011', #9, [rfReplaceAll]);
  Result := StringReplace(Result, '\012', #10, [rfReplaceAll]);
  Result := StringReplace(Result, '\134', '\', [rfReplaceAll]);
end;

procedure ReadMounts(var M: TMountList; out N: Integer);
var
  L, P: TStringList;
  I: Integer;
begin
  N := 0;
  L := TStringList.Create;
  P := TStringList.Create;
  try
    try
      L.LoadFromFile('/proc/mounts');
    except
      Exit;
    end;
    P.Delimiter := ' ';
    P.StrictDelimiter := True;
    for I := 0 to L.Count - 1 do
    begin
      P.DelimitedText := L[I];
      if (P.Count >= 3) and (N <= High(M)) then
      begin
        M[N].Dev := UnescapeMount(P[0]);
        M[N].Dir := UnescapeMount(P[1]);
        M[N].FsType := P[2];
        Inc(N);
      end;
    end;
  finally
    P.Free;
    L.Free;
  end;
end;

function RemovableByName(const Dev, Dir: string): Boolean;
begin
  Result := False;
  if Copy(Dev, 1, 9) = '/dev/loop' then Exit;          // snap packages and disk images
  if Copy(Dev, 1, 5) <> '/dev/' then Exit;             // network and virtual file systems
  Result := (Copy(Dir, 1, 7) = '/media/') or (Copy(Dir, 1, 11) = '/run/media/') or
            (Copy(Dir, 1, 5) = '/mnt/');
end;
{$ENDIF}

function MountPointOf(const Path: string): string;
{$IFDEF WINDOWS}
begin
  Result := ExtractFileDrive(Path);
  if Result <> '' then Result := IncludeTrailingPathDelimiter(Result);
end;
{$ELSE}
var
  M: TMountList;
  N, I: Integer;
  Full, D: string;
begin
  Result := '';
  Full := IncludeTrailingPathDelimiter(ExpandFileName(Path));
  ReadMounts(M, N);
  for I := 0 to N - 1 do
  begin
    D := IncludeTrailingPathDelimiter(M[I].Dir);
    if (Copy(Full, 1, Length(D)) = D) and (Length(D) > Length(Result)) then
      Result := D;                                      // the longest match is the real mount point
  end;
end;
{$ENDIF}

function IsRemovableMount(const MountPoint: string): Boolean;
{$IFDEF WINDOWS}
begin
  Result := (MountPoint <> '') and (GetDriveType(PChar(MountPoint)) = DRIVE_REMOVABLE);
end;
{$ELSE}
var
  M: TMountList;
  N, I: Integer;
  D: string;
begin
  Result := False;
  D := IncludeTrailingPathDelimiter(MountPoint);
  ReadMounts(M, N);
  for I := 0 to N - 1 do
    if IncludeTrailingPathDelimiter(M[I].Dir) = D then
      Result := RemovableByName(M[I].Dev, M[I].Dir);
end;
{$ENDIF}

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
var
  M: TMountList;
  N, I: Integer;
begin
  L.Clear;
  ReadMounts(M, N);
  for I := 0 to N - 1 do
    if RemovableByName(M[I].Dev, M[I].Dir) then
      L.Add(IncludeTrailingPathDelimiter(M[I].Dir));
end;
{$ENDIF}

function EjectDrive(const Root: string): Boolean;
{$IFDEF WINDOWS}
var
  Outp: string;
begin
  Result := RunCommand('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command',
     '(New-Object -comObject Shell.Application).Namespace(17).ParseName(''' +
       Copy(Root, 1, 2) + ''').InvokeVerb(''Eject'')'],
    Outp, [poNoConsole]);
end;
{$ELSE}
var
  Outp, Dev, Dir: string;
  M: TMountList;
  N, I: Integer;
begin
  Result := False;
  Dir := ExcludeTrailingPathDelimiter(Root);
  Dev := '';
  ReadMounts(M, N);
  for I := 0 to N - 1 do
    if ExcludeTrailingPathDelimiter(M[I].Dir) = Dir then Dev := M[I].Dev;
  if Dev <> '' then
    if RunCommand('udisksctl', ['unmount', '-b', Dev], Outp) then
    begin
      RunCommand('udisksctl', ['power-off', '-b', Dev], Outp);   // switches the reader off; failure is harmless
      Exit(True);
    end;
  if RunCommand('gio', ['mount', '-u', Dir], Outp) then Exit(True);
  Result := RunCommand('umount', [Dir], Outp);
end;
{$ENDIF}

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
var
  P: TProcess;
begin
  // most Linux file managers cannot select a file from the command line: open its folder
  Result := False;
  P := TProcess.Create(nil);
  try
    try
      P.Executable := 'xdg-open';
      P.Parameters.Add(ExtractFilePath(FileName));
      P.Options := [];
      P.Execute;
      Result := True;
    except
      Result := False;
    end;
  finally
    P.Free;
  end;
end;
{$ENDIF}

end.
