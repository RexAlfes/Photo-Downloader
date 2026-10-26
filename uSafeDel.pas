unit uSafeDel;

{ Safe delete: instead of erasing a file from the image source it is moved somewhere it can be
  recovered from.
    - Windows, fixed disk : the Recycle Bin.
    - Anything else (memory card, USB drive, network share, Linux), or when the Recycle Bin
      refuses: a hidden folder (default "$trash.bin", set in Preferences) at the root of the same drive, keeping
      the folder structure. Moving inside one drive is instant and needs no extra space.
  The file is never erased by this unit; if it cannot be moved the result is False. }

{$mode objfpc}{$H+}

interface

{ Moves FileName out of the way. Where receives a short description of the place it went. }
function SafeDeleteFile(const FileName, TrashName: string; out Where: string): Boolean;

{ The trash folder that safe delete uses on the drive of SourcePath (or, when there is no
  source, the first drive that has one). Returns '' when there is none. }
function FindTrashFolder(const SourcePath, TrashName: string): string;

{ Counts the files in the folder and its sub-folders. }
procedure TrashStats(const Dir: string; out Files: Integer; out Bytes: Int64);

{ Erases everything in the trash folder and the folder itself. Failed = files that stayed. }
procedure EmptyTrashFolder(const Dir: string; out Failed: Integer);

const
  DefaultTrashName = '$trash.bin';

{ Makes a usable folder name from what the user typed (no path characters, not empty). }
function CleanTrashName(const S: string): string;

implementation

uses
  Classes, SysUtils, LazFileUtils, uDrives
  {$IFDEF WINDOWS}, Windows, ShellApi{$ELSE}, Process{$ENDIF};

{$IFDEF WINDOWS}
function IsFixedDrive(const FileName: string): Boolean;
var
  Drv: string;
  W: UnicodeString;
begin
  Result := False;
  Drv := ExtractFileDrive(FileName);
  // a UNC path (\\server\share) has no drive letter: treat it as not fixed
  if (Length(Drv) <> 2) or (Drv[2] <> ':') then Exit;
  W := UnicodeString(Drv + '\');
  Result := GetDriveTypeW(PWideChar(W)) = DRIVE_FIXED;
end;

function ToRecycleBin(const FileName: string): Boolean;
var
  Op: TSHFileOpStructW;
  W: UnicodeString;
begin
  Op := Default(TSHFileOpStructW);
  W := UnicodeString(FileName) + #0#0;      // the list must end with two nulls
  Op.Wnd := 0;
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(W);
  Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  Result := (SHFileOperationW(@Op) = 0) and (not Op.fAnyOperationsAborted) and
    (not FileExistsUTF8(FileName));
end;
{$ENDIF}

function CleanTrashName(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if not (S[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31]) then
      Result := Result + S[I];
  Result := Trim(Result);
  while (Result <> '') and (Result[Length(Result)] = '.') do Delete(Result, Length(Result), 1);
  if (Result = '') or (Result = '.') then Result := DefaultTrashName;
end;

function TrashRootFor(const FileName, TrashName: string): string;
var
  Mp: string;
begin
  // the root of the drive (Windows) or the mount point (Linux) that holds the file
  Mp := MountPointOf(FileName);
  if Mp = '' then Mp := ExtractFilePath(FileName);
  Result := IncludeTrailingPathDelimiter(Mp) + TrashName + PathDelim;
end;

function ToHoldingFolder(const FileName, TrashName: string; out Where: string): Boolean;
var
  Root, Rel, Dst, Dir, Base, Ext: string;
  N: Integer;
  Mp: string;
begin
  Result := False;
  Root := TrashRootFor(FileName, TrashName);
  Mp := MountPointOf(FileName);
  Rel := FileName;
  if (Mp <> '') and (Copy(Rel, 1, Length(Mp)) = Mp) then
    Delete(Rel, 1, Length(Mp));
  while (Rel <> '') and (Rel[1] in ['\', '/']) do Delete(Rel, 1, 1);
  if Rel = '' then Rel := ExtractFileName(FileName);
  Dst := Root + Rel;
  Dir := ExtractFilePath(Dst);
  if not ForceDirectoriesUTF8(Dir) then Exit;
  if not DirectoryExistsUTF8(Root) then Exit;
  FileSetAttrUTF8(ExcludeTrailingPathDelimiter(Root), $02);   // hidden (faHidden is not portable); keeps it out of later scans
  if FileExistsUTF8(Dst) then
  begin
    Ext := ExtractFileExt(Dst);
    Base := Copy(Dst, 1, Length(Dst) - Length(Ext));
    N := 1;
    repeat
      Dst := Base + '_' + IntToStr(N) + Ext;
      Inc(N);
    until (not FileExistsUTF8(Dst)) or (N > 9999);
  end;
  if RenameFileUTF8(FileName, Dst) then
  begin
    Where := 'the "' + TrashName + '" folder on the same drive';
    Result := True;
  end;
end;

function FindTrashFolder(const SourcePath, TrashName: string): string;
var
  Name, Drv: string;
  {$IFDEF WINDOWS}C: Char;{$ELSE}L: TStringList; I: Integer;{$ENDIF}
begin
  Result := '';
  Name := CleanTrashName(TrashName);
  if SourcePath <> '' then
  begin
    Result := TrashRootFor(SourcePath, Name);
    if DirectoryExistsUTF8(Result) then Exit;
    Result := '';
    Drv := ExtractFileDrive(SourcePath);
    if Drv <> '' then Exit;       // the source drive has no trash
  end;
  {$IFDEF WINDOWS}
  for C := 'C' to 'Z' do
    if DirectoryExistsUTF8(C + ':\' + Name) then
    begin
      Result := C + ':\' + Name + PathDelim;
      Exit;
    end;
  {$ELSE}
  // Linux: look in the removable drives that are mounted
  L := TStringList.Create;
  try
    ListRemovableDrives(L);
    for I := 0 to L.Count - 1 do
      if DirectoryExistsUTF8(L[I] + Name) then
      begin
        Result := L[I] + Name + PathDelim;
        Exit;
      end;
  finally
    L.Free;
  end;
  {$ENDIF}
end;

procedure TrashStats(const Dir: string; out Files: Integer; out Bytes: Int64);
var
  SR: TSearchRec;
  Base: string;
  F2: Integer;
  B2: Int64;
begin
  Files := 0;
  Bytes := 0;
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirstUTF8(Base + '*', faAnyFile, SR) <> 0 then Exit;
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        TrashStats(Base + SR.Name, F2, B2);
        Inc(Files, F2);
        Inc(Bytes, B2);
      end
      else
      begin
        Inc(Files);
        Inc(Bytes, SR.Size);
      end;
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
end;

procedure EmptyTrashFolder(const Dir: string; out Failed: Integer);
var
  SR: TSearchRec;
  Base: string;
  F2: Integer;
begin
  Failed := 0;
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirstUTF8(Base + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          EmptyTrashFolder(Base + SR.Name, F2);
          Inc(Failed, F2);
        end
        else
        begin
          FileSetAttrUTF8(Base + SR.Name, 0);
          if not DeleteFileUTF8(Base + SR.Name) then Inc(Failed);
        end;
      until FindNextUTF8(SR) <> 0;
    finally
      FindCloseUTF8(SR);
    end;
  end;
  if Failed = 0 then RemoveDirUTF8(Dir);
end;

function SafeDeleteFile(const FileName, TrashName: string; out Where: string): Boolean;
var
  Name: string;
  {$IFNDEF WINDOWS}Outp: string;{$ENDIF}
begin
  Name := CleanTrashName(TrashName);
  Where := '';
  Result := False;
  if not FileExistsUTF8(FileName) then Exit;
  {$IFDEF WINDOWS}
  if IsFixedDrive(FileName) and ToRecycleBin(FileName) then
  begin
    Where := 'the Recycle Bin';
    Exit(True);
  end;
  {$ELSE}
  // Linux: the desktop trash (gio) for the computer's own disks; cards, USB drives and
  // network shares get the holding folder below
  if not IsRemovableMount(MountPointOf(FileName)) then
    if RunCommand('gio', ['trash', FileName], Outp) and (not FileExistsUTF8(FileName)) then
    begin
      Where := 'the Trash';
      Exit(True);
    end;
  {$ENDIF}
  Result := ToHoldingFolder(FileName, Name, Where);
end;

end.
