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
    Dev, Dir, FsType: string;  // Dev: device name, Dir: mount point, FsType: file system type
  end;
  TMountList = array of TMountInfo;  // list of mounted file systems (any number: snap packages can add hundreds)

{ Names in /proc/mounts escape space, tab, newline and backslash as \040 \011 \012 \134 }
function UnescapeMount(const S: string): string;
begin
  Result := StringReplace(S, '\040', ' ', [rfReplaceAll]);  // space
  Result := StringReplace(Result, '\011', #9, [rfReplaceAll]);  // tab
  Result := StringReplace(Result, '\012', #10, [rfReplaceAll]);  // newline
  Result := StringReplace(Result, '\134', '\', [rfReplaceAll]);  // backslash
end;

{ Reads /proc/mounts into M; N receives how many entries were stored. }
procedure ReadMounts(var M: TMountList; out N: Integer);
var
  L, P: TStringList;  // L: raw lines, P: the fields of one line
  I: Integer;  // I: line index
begin
  N := 0;  // no entries yet
  SetLength(M, 0);  // empty list
  L := TStringList.Create;  // list for the file's lines
  P := TStringList.Create;  // list used to split one line into fields
  try
    try
      L.LoadFromFile('/proc/mounts');  // read the mount table
    except
      Exit;  // cannot read it: report no mounts
    end;
    P.Delimiter := ' ';  // fields are separated by spaces
    P.StrictDelimiter := True;  // do not treat quotes specially
    SetLength(M, L.Count);  // room for one entry per line
    for I := 0 to L.Count - 1 do  // go through every line
    begin
      P.DelimitedText := L[I];  // split the line into fields
      if P.Count >= 3 then  // need device, mount point and type
      begin
        M[N].Dev := UnescapeMount(P[0]);  // device, unescaped
        M[N].Dir := UnescapeMount(P[1]);  // mount point, unescaped
        M[N].FsType := P[2];  // file system type
        Inc(N);  // count the stored entry
      end;
    end;
    SetLength(M, N);  // drop the unused room
  finally
    P.Free;  // free the field list
    L.Free;  // free the line list
  end;
end;

{ Linux: True if a mount looks like removable media, judged from its device and mount point names. }
function RemovableByName(const Dev, Dir: string): Boolean;
begin
  Result := False;  // assume it is not removable
  if Copy(Dev, 1, 9) = '/dev/loop' then Exit;          // snap packages and disk images
  if Copy(Dev, 1, 5) <> '/dev/' then Exit;             // network and virtual file systems
  Result := (Copy(Dir, 1, 7) = '/media/') or (Copy(Dir, 1, 11) = '/run/media/') or
            (Copy(Dir, 1, 5) = '/mnt/');
end;
{$ENDIF}

{ Returns the drive root (Windows) or mount point (Linux) that contains Path, with a trailing delimiter. }
function MountPointOf(const Path: string): string;
{$IFDEF WINDOWS}
begin
  Result := ExtractFileDrive(Path);  // drive letter part of the path
  if Result <> '' then Result := IncludeTrailingPathDelimiter(Result);  // add the trailing backslash
end;
{$ELSE}
var
  M: TMountList;  // M: mount table
  N, I: Integer;  // N: number of entries, I: loop index
  Full, D: string;  // Full: expanded path, D: one mount point
begin
  Result := '';  // empty means not found
  Full := IncludeTrailingPathDelimiter(ExpandFileName(Path));  // full path ending with a delimiter
  ReadMounts(M, N);  // read the mount table
  for I := 0 to N - 1 do  // check every mount
  begin
    D := IncludeTrailingPathDelimiter(M[I].Dir);  // mount point with a trailing delimiter
    if (Copy(Full, 1, Length(D)) = D) and (Length(D) > Length(Result)) then  // the path lies below this mount and it is longer than the best so far
      Result := D;                                      // the longest match is the real mount point
  end;
end;
{$ENDIF}

{ Returns True if MountPoint is a memory card or other removable storage. }
function IsRemovableMount(const MountPoint: string): Boolean;
{$IFDEF WINDOWS}
begin
  Result := (MountPoint <> '') and (GetDriveType(PChar(MountPoint)) = DRIVE_REMOVABLE);  // ask Windows for the drive type
end;
{$ELSE}
var
  M: TMountList;  // M: mount table
  N, I: Integer;  // N: number of entries, I: loop index
  D: string;  // D: the mount point being tested
begin
  Result := False;  // assume not removable
  D := IncludeTrailingPathDelimiter(MountPoint);  // mount point with a trailing delimiter
  ReadMounts(M, N);  // read the mount table
  for I := 0 to N - 1 do  // look for the matching entry
    if IncludeTrailingPathDelimiter(M[I].Dir) = D then  // same mount point?
      Result := RemovableByName(M[I].Dev, M[I].Dir);  // decide by device and directory names
end;
{$ENDIF}

{ Fills L with the roots of all removable drives (Windows letters or Linux mount points). }
procedure ListRemovableDrives(L: TStrings);
{$IFDEF WINDOWS}
var
  C: Char;  // C: drive letter being tested
  Root: string;  // Root: its root path
begin
  L.Clear;  // start with an empty list
  for C := 'A' to 'Z' do  // try every drive letter
  begin
    Root := C + ':\';  // build 'C:\' style root
    if GetDriveType(PChar(Root)) = DRIVE_REMOVABLE then  // is it a removable drive?
      L.Add(Root);  // add it to the list
  end;
end;
{$ELSE}
var
  M: TMountList;  // M: mount table
  N, I: Integer;  // N: number of entries, I: loop index
begin
  L.Clear;  // start with an empty list
  ReadMounts(M, N);  // read the mount table
  for I := 0 to N - 1 do  // check every mount
    if RemovableByName(M[I].Dev, M[I].Dir) then  // keep only removable ones
      L.Add(IncludeTrailingPathDelimiter(M[I].Dir));  // add the mount point
end;
{$ENDIF}

{ Ejects the drive at Root (PowerShell on Windows; udisksctl, gio or umount on Linux). }
function EjectDrive(const Root: string): Boolean;
{$IFDEF WINDOWS}
var
  Outp: string;  // Outp: command output (not used)
begin
  Result := RunCommand('powershell.exe',  // run PowerShell and ask the shell to eject the drive
    ['-NoProfile', '-NonInteractive', '-Command',
     '(New-Object -comObject Shell.Application).Namespace(17).ParseName(''' +
       Copy(Root, 1, 2) + ''').InvokeVerb(''Eject'')'],
    Outp, [poNoConsole]);
end;
{$ELSE}
var
  Outp, Dev, Dir: string;  // Outp: command output, Dev: device, Dir: mount point
  M: TMountList;  // M: mount table
  N, I: Integer;  // N: number of entries, I: loop index
begin
  Result := False;  // assume failure
  Dir := ExcludeTrailingPathDelimiter(Root);  // mount point without trailing delimiter
  Dev := '';  // device not known yet
  ReadMounts(M, N);  // read the mount table
  for I := 0 to N - 1 do  // find the device mounted at Dir
    if ExcludeTrailingPathDelimiter(M[I].Dir) = Dir then Dev := M[I].Dev;  // remember its device name
  if Dev <> '' then  // device found
    if RunCommand('udisksctl', ['unmount', '-b', Dev], Outp) then  // try to unmount it with udisks
    begin
      RunCommand('udisksctl', ['power-off', '-b', Dev], Outp);   // switches the reader off; failure is harmless
      Exit(True);  // success
    end;
  if RunCommand('gio', ['mount', '-u', Dir], Outp) then Exit(True);  // fall back to gio
  Result := RunCommand('umount', [Dir], Outp);  // last resort: plain umount
end;
{$ENDIF}

{ Starts a program from a command line without waiting for it. }
procedure LaunchCommand(const CmdLine: string);
var
  P: TProcess;  // P: process object
  Parts: TStringList;  // Parts: command line split into words
  I: Integer;  // I: index of the argument
begin
  Parts := TStringList.Create;  // list for the split command line
  P := TProcess.Create(nil);  // process object
  try
    CommandToList(CmdLine, Parts);  // split the command line, respecting quotes
    if Parts.Count = 0 then Exit;  // empty command: nothing to start
    P.Executable := Parts[0];  // first word is the program
    for I := 1 to Parts.Count - 1 do  // remaining words are its arguments
      P.Parameters.Add(Parts[I]);  // add one argument
    P.Options := [];  // no special options
    P.Execute;  // start the program
  finally
    P.Free;  // free the process object
    Parts.Free;  // free the word list
  end;
end;

{ Opens the file manager at a file (Windows selects it; Linux opens its folder). }
function RevealFile(const FileName: string): Boolean;
{$IFDEF WINDOWS}
var
  Params: UnicodeString;  // Params: command line for Explorer
begin
  Params := UTF8Decode('/select,"' + FileName + '"');  // ask Explorer to select the file
  Result := ShellExecuteW(0, 'open', 'explorer.exe', PWideChar(Params), nil, SW_SHOWNORMAL) > 32;  // start Explorer; values above 32 mean success
end;
{$ELSE}
var
  P: TProcess;  // P: process object
begin
  // most Linux file managers cannot select a file from the command line: open its folder
  Result := False;  // assume failure
  P := TProcess.Create(nil);  // process object
  try
    try
      P.Executable := 'xdg-open';  // xdg-open starts the default file manager
      P.Parameters.Add(ExtractFilePath(FileName));  // argument: the file's folder
      P.Options := [];  // no special options
      P.Execute;  // start it
      Result := True;  // started
    except
      Result := False;  // could not start
    end;
  finally
    P.Free;  // free the process object
  end;
end;
{$ENDIF}

end.
