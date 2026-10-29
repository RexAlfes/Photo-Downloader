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
  DefaultTrashName = '$trash.bin';  // folder name used when none is set

{ Makes a usable folder name from what the user typed (no path characters, not empty). }
function CleanTrashName(const S: string): string;

implementation

uses
  Classes, SysUtils, LazFileUtils, uDrives
  {$IFDEF WINDOWS}, Windows, ShellApi{$ELSE}, Process{$ENDIF};

{$IFDEF WINDOWS}
function IsFixedDrive(const FileName: string): Boolean;
var
  Drv: string;  // Drv: drive part of the path
  W: UnicodeString;  // W: drive root as a wide string
begin
  Result := False;  // assume not fixed
  Drv := ExtractFileDrive(FileName);  // drive part, such as 'C:'
  // a UNC path (\\server\share) has no drive letter: treat it as not fixed
  if (Length(Drv) <> 2) or (Drv[2] <> ':') then Exit;  // not a drive letter path: treat as not fixed
  W := UnicodeString(Drv + '\');  // drive root with backslash
  Result := GetDriveTypeW(PWideChar(W)) = DRIVE_FIXED;  // ask Windows for the drive type
end;

{ Windows: sends a file to the Recycle Bin; True only if the file is really gone afterward. }
function ToRecycleBin(const FileName: string): Boolean;
var
  Op: TSHFileOpStructW;  // Op: shell file operation request
  W: UnicodeString;  // W: file name list (double null terminated)
begin
  Op := Default(TSHFileOpStructW);  // clear the request record
  W := UnicodeString(FileName) + #0#0;      // the list must end with two nulls
  Op.Wnd := 0;  // no owner window
  Op.wFunc := FO_DELETE;  // operation: delete
  Op.pFrom := PWideChar(W);  // file list
  Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;  // move to the Recycle Bin, no questions or windows
  Result := (SHFileOperationW(@Op) = 0) and (not Op.fAnyOperationsAborted) and  // success only if the call worked, was not aborted, and the file is gone
    (not FileExistsUTF8(FileName));
end;
{$ENDIF}

{ Removes characters that are not allowed in a folder name; falls back to the default name. }
function CleanTrashName(const S: string): string;
var
  I: Integer;  // I: position in the text
begin
  Result := '';  // start empty
  for I := 1 to Length(S) do  // look at every character
    if not (S[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31]) then  // skip path and reserved characters
      Result := Result + S[I];  // keep the allowed ones
  Result := Trim(Result);  // remove spaces at both ends
  while (Result <> '') and (Result[Length(Result)] = '.') do Delete(Result, Length(Result), 1);  // remove trailing dots
  if (Result = '') or (Result = '.') then Result := DefaultTrashName;  // empty or '.' gets the default name
end;

{ Returns the trash folder path at the root of the drive that holds FileName. }
function TrashRootFor(const FileName, TrashName: string): string;
var
  Mp: string;  // Mp: drive root or mount point
begin
  // the root of the drive (Windows) or the mount point (Linux) that holds the file
  Mp := MountPointOf(FileName);  // find the drive root or mount point
  if Mp = '' then Mp := ExtractFilePath(FileName);  // fall back to the file's own folder
  Result := IncludeTrailingPathDelimiter(Mp) + TrashName + PathDelim;  // root + trash folder name + delimiter
end;

{ Moves a file into the hidden trash folder on its own drive, keeping its sub-folders. }
function ToHoldingFolder(const FileName, TrashName: string; out Where: string): Boolean;
var
  Root, Rel, Dst, Dir, Base, Ext: string;  // Root: trash folder, Rel: path below the drive root, Dst: target file, Dir: its folder
  N: Integer;  // N: counter for unique names
  Mp: string;  // Mp: drive root or mount point
begin
  Result := False;  // assume failure
  Root := TrashRootFor(FileName, TrashName);  // trash folder of this drive
  Mp := MountPointOf(FileName);  // drive root or mount point
  Rel := FileName;  // start with the full path
  if (Mp <> '') and (Copy(Rel, 1, Length(Mp)) = Mp) then  // path begins with the drive root?
    Delete(Rel, 1, Length(Mp));  // cut the drive root off
  while (Rel <> '') and (Rel[1] in ['\', '/']) do Delete(Rel, 1, 1);  // remove leading delimiters
  if Rel = '' then Rel := ExtractFileName(FileName);  // nothing left: use the bare file name
  Dst := Root + Rel;  // target path inside the trash folder
  Dir := ExtractFilePath(Dst);  // target folder
  if not ForceDirectoriesUTF8(Dir) then Exit;  // create the folders
  if not DirectoryExistsUTF8(Root) then Exit;  // trash folder must exist now
  FileSetAttrUTF8(ExcludeTrailingPathDelimiter(Root), $02);   // hidden (faHidden is not portable); keeps it out of later scans
  if FileExistsUTF8(Dst) then  // a file with that name is already in the trash?
  begin
    Ext := ExtractFileExt(Dst);  // extension of the target
    Base := Copy(Dst, 1, Length(Dst) - Length(Ext));  // target path without extension
    N := 1;  // first number to try
    repeat
      Dst := Base + '_' + IntToStr(N) + Ext;  // name with a number added
      Inc(N);  // next number
    until (not FileExistsUTF8(Dst)) or (N > 9999);  // stop at a free name or after 9999 tries
  end;
  if RenameFileUTF8(FileName, Dst) then  // move the file (instant on the same drive)
  begin
    Where := 'the "' + TrashName + '" folder on the same drive';  // tell the caller where it went
    Result := True;  // success
  end;
end;

{ Finds the trash folder to show or empty: on the source's drive, or on any drive when there is no source. }
function FindTrashFolder(const SourcePath, TrashName: string): string;
var
  Name, Drv: string;  // Name: cleaned folder name, Drv: drive part of the source path
  {$IFDEF WINDOWS}C: Char;{$ELSE}L: TStringList; I: Integer;{$ENDIF}  // C: drive letter (Windows) / L and I: removable drives and index (Linux)
begin
  Result := '';  // assume none found
  Name := CleanTrashName(TrashName);  // folder name made safe
  if SourcePath <> '' then  // a source folder is known
  begin
    Result := TrashRootFor(SourcePath, Name);  // trash folder on the source's drive
    if DirectoryExistsUTF8(Result) then Exit;  // it exists: done
    Result := '';  // not there
    Drv := ExtractFileDrive(SourcePath);  // drive part of the source path
    if Drv <> '' then Exit;       // the source drive has no trash
  end;
  {$IFDEF WINDOWS}
  for C := 'C' to 'Z' do  // try every drive letter from C to Z
    if DirectoryExistsUTF8(C + ':\' + Name) then  // does this drive have the folder?
    begin
      Result := C + ':\' + Name + PathDelim;  // path with trailing delimiter
      Exit;  // done
    end;
  {$ELSE}
  // Linux: look in the removable drives that are mounted
  L := TStringList.Create;  // list for the removable drives
  try
    ListRemovableDrives(L);  // get the mounted removable drives
    for I := 0 to L.Count - 1 do  // check each one
      if DirectoryExistsUTF8(L[I] + Name) then  // does it have the folder?
      begin
        Result := L[I] + Name + PathDelim;  // path with trailing delimiter
        Exit;  // done
      end;
  finally
    L.Free;  // free the list
  end;
  {$ENDIF}
end;

{ Counts the files and bytes in a folder and all its sub-folders. }
procedure TrashStats(const Dir: string; out Files: Integer; out Bytes: Int64);
var
  SR: TSearchRec;  // SR: search record
  Base: string;  // Base: folder with trailing delimiter
  F2: Integer;  // F2: file count of a sub-folder
  B2: Int64;  // B2: byte count of a sub-folder
begin
  Files := 0;  // start counting at zero
  Bytes := 0;  // no bytes yet
  Base := IncludeTrailingPathDelimiter(Dir);  // folder path with delimiter
  if FindFirstUTF8(Base + '*', faAnyFile, SR) <> 0 then Exit;  // nothing in the folder: done
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;  // skip the '.' and '..' entries
      if (SR.Attr and faDirectory) <> 0 then  // a sub-folder
      begin
        TrashStats(Base + SR.Name, F2, B2);  // count inside it
        Inc(Files, F2);  // add its files
        Inc(Bytes, B2);  // add its bytes
      end
      else
      begin
        Inc(Files);  // count one file
        Inc(Bytes, SR.Size);  // add its size
      end;
    until FindNextUTF8(SR) <> 0;  // next entry
  finally
    FindCloseUTF8(SR);  // end the search
  end;
end;

{ True when a folder entry is a link (Linux symlink, Windows junction or symbolic link) rather than a real file or folder. }
function IsLinkEntry(const Path: string): Boolean;
begin
  Result := FileIsSymlink(Path);  // LazFileUtils: lstat on Linux, reparse tag on Windows (faSymLink is not portable)
end;

{ Deletes everything in the trash folder and the folder itself; Failed counts files that could not be removed.
  Links inside it are removed as links: what they point to is never touched. }
procedure EmptyTrashFolder(const Dir: string; out Failed: Integer);
var
  SR: TSearchRec;  // SR: search record
  Base: string;  // Base: folder with trailing delimiter
  F2: Integer;  // F2: failures inside a sub-folder
begin
  Failed := 0;  // no failures yet
  Base := IncludeTrailingPathDelimiter(Dir);  // folder path with delimiter
  if FindFirstUTF8(Base + '*', faAnyFile, SR) = 0 then  // folder can be listed
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;  // skip the '.' and '..' entries
        if IsLinkEntry(Base + SR.Name) then  // a link (Linux symlink or Windows junction)
        begin
          // remove only the link itself, never what it points to (that may be outside the trash)
          if (SR.Attr and faDirectory) <> 0 then
          begin
            if not RemoveDirUTF8(Base + SR.Name) then  // a Windows folder link is removed like a folder
              if not DeleteFileUTF8(Base + SR.Name) then Inc(Failed);  // a Linux link is removed like a file
          end
          else if not DeleteFileUTF8(Base + SR.Name) then Inc(Failed);  // a link to a file
        end
        else if (SR.Attr and faDirectory) <> 0 then  // a real sub-folder
        begin
          EmptyTrashFolder(Base + SR.Name, F2);  // empty it first
          Inc(Failed, F2);  // add its failures
        end
        else
        begin
          FileSetAttrUTF8(Base + SR.Name, 0);  // clear read-only and hidden flags
          if not DeleteFileUTF8(Base + SR.Name) then Inc(Failed);  // delete the file, count a failure
        end;
      until FindNextUTF8(SR) <> 0;  // next entry
    finally
      FindCloseUTF8(SR);  // end the search
    end;
  end;
  if Failed = 0 then RemoveDirUTF8(Dir);  // remove the folder itself only if everything went
end;

{ Moves FileName to the Recycle Bin, the system trash, or the hidden trash folder; never erases it. Where describes the destination. }
function SafeDeleteFile(const FileName, TrashName: string; out Where: string): Boolean;
var
  Name: string;  // Name: cleaned trash folder name
  {$IFNDEF WINDOWS}Outp: string;{$ENDIF}  // Outp: output of the gio command
begin
  Name := CleanTrashName(TrashName);  // folder name made safe
  Where := '';  // no destination yet
  Result := False;  // assume failure
  if not FileExistsUTF8(FileName) then Exit;  // file not there: nothing to do
  {$IFDEF WINDOWS}
  if IsFixedDrive(FileName) and ToRecycleBin(FileName) then  // fixed disk: try the Recycle Bin first
  begin
    Where := 'the Recycle Bin';  // tell the caller where it went
    Exit(True);  // success
  end;
  {$ELSE}
  // Linux: the desktop trash (gio) for the computer's own disks; cards, USB drives and
  // network shares get the holding folder below
  if not IsRemovableMount(MountPointOf(FileName)) then  // not removable media: use the desktop trash
    if RunCommand('gio', ['trash', FileName], Outp) and (not FileExistsUTF8(FileName)) then  // ask gio to trash the file and check that it is gone
    begin
      Where := 'the Trash';  // tell the caller where it went
      Exit(True);  // success
    end;
  {$ENDIF}
  Result := ToHoldingFolder(FileName, Name, Where);  // everything else goes to the hidden folder on the same drive
end;

end.
