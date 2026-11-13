{ Phones, cameras and drone controllers connected by USB (MTP / PTP), read through the Windows Shell
  the same way Explorer reads them (docs/MTP_Plan.md, Phase 1).

  Such a device has no drive letter, so the program copies the chosen folders into a staging folder
  (StagingDir) and then loads that folder as a normal source. This unit lists the devices and their
  folders, lists the files of a folder, copies one file through its IStream (with an MD5 check of the
  copy and the device's date as the file time), and deletes a file on the device (IFileOperation).

  Windows only; on other systems the functions find no devices (a phone appears there as a GVFS folder
  that File > Open Source Folder can open). Nothing on a device is changed except DeleteDeviceFile. }
unit uDevices;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type
  { One file on a device. }
  TDeviceFile = class
    Rel: string;        // path below the staging folder: <storage>\<folder>\...\<name>
    Id: string;         // finds the file again while the device is connected (Shell item ID list)
    Size: Int64;        // size in bytes (-1 when the device does not tell)
    Time: Int64;        // last-modified time as a Windows FILETIME (UTC), 0 when unknown
    CanDelete: Boolean; // the device allows deleting this file
  end;

  TDeviceCountProc = function(Count: Integer): Boolean of object;  // files found so far; False cancels
  TDeviceCopyProc = function(Bytes: Int64): Boolean of object;  // bytes copied of the current file; False cancels

{ True when this system can read devices through the Shell (Windows). }
function DevicesSupported: Boolean;
{ Fills Names with the connected portable devices and Ids with what finds them again. }
procedure ListDevices(Names, Ids: TStrings);
{ Fills Names with the folders one level inside each storage of the device ("Storage\Folder") and Ids
  with what finds them again. }
procedure ListDeviceFolders(const DevId: string; Names, Ids: TStrings);
{ Adds every file below the folder FolderId to Files (TDeviceFile, owned by the list); RelBase is the
  folder's path below the staging folder. Folders and files whose names start with a dot are skipped
  (Android's DCIM\.thumbnails). False when canceled or the folder cannot be read. }
function ListDeviceFiles(const FolderId, RelBase: string; Files: TObjectList;
  OnCount: TDeviceCountProc): Boolean;
{ True when Fn already holds a copy of F (same size and time). }
function StagedCopyMatches(F: TDeviceFile; const Fn: string): Boolean;
{ Copies F from the device to Fn (through Fn + '.part'), checks the copy with an MD5 and gives it the
  device's date. False with Err set on failure or cancel. }
function CopyDeviceFile(F: TDeviceFile; const Fn: string; OnBytes: TDeviceCopyProc; out Err: string): Boolean;
{ Deletes a file on the device (no Recycle Bin on devices: this cannot be undone). }
function DeleteDeviceFile(const Id: string; out Err: string): Boolean;
{ The staging folder of a device: CacheDir\device\<device name>\. }
function StagingDir(const DevName: string): string;
{ Total size of the files in the device staging folders (for Help > Status). }
function StagingBytes: Int64;
{ A name that can be used as a file or folder name (characters Windows refuses become "_"). }
function SafeFolderName(const S: string): string;

implementation

uses
  {$IFDEF WINDOWS}Windows, ActiveX, md5,{$ENDIF} LazFileUtils, uSettings;

{$IFDEF WINDOWS}
const
  FOLDERID_ComputerFolder: TGUID = '{0AC0837C-BBF8-452A-850D-79D08E667CA7}';  // This PC
  BHID_EnumItems: TGUID = '{94F60519-2850-4924-AA5A-D15E84868039}';  // children of a folder item
  BHID_Stream: TGUID = '{1CEBB3AB-7C10-499A-A417-92CA16C4CB83}';  // IStream of a file item
  CLSID_FileOperation: TGUID = '{3AD05575-8857-4850-9277-11B85BDB8E09}';  // the Shell's copy/move/delete engine
  SIGDN_NORMALDISPLAY = $00000000;  // the name Explorer shows
  SIGDN_DESKTOPABSOLUTEPARSING = $80028000;  // the full parsing name (::{...}\\?\usb#... for devices)
  SFGAO_CANDELETE = $00000020;  // the item may be deleted
  SFGAO_STREAM = $00400000;  // can be opened as a stream (a file)
  SFGAO_FOLDER = $20000000;  // a folder (or a storage of a device)
  SFGAO_FILESYSTEM = $40000000;  // part of the normal file system (a drive or folder with a path)
  FOF_SILENT = $0004;  // no progress window
  FOF_NOCONFIRMATION = $0010;  // no "are you sure" (the program asked already)
  FOF_NOERRORUI = $0400;  // no error window (the program reports failures)

type
  TPropertyKey = record  // PROPERTYKEY
    fmtid: TGUID;  // property set
    pid: DWORD;  // property in the set
  end;

  { Free Pascal 3.2.2 has no usable declarations of these Shell interfaces, so they are declared here
    (only what is used; the order of the methods must match the Windows headers). }
  IShellItem = interface(IUnknown)
    ['{43826D1E-E718-42EE-BC55-A1E261C37BFE}']
    function BindToHandler(pbc: Pointer; constref bhid: TGUID; constref riid: TGUID; out ppv): HResult; stdcall;
    function GetParent(out ppsi: IShellItem): HResult; stdcall;
    function GetDisplayName(sigdnName: DWORD; out ppszName: PWideChar): HResult; stdcall;
    function GetAttributes(sfgaoMask: DWORD; out psfgaoAttribs: DWORD): HResult; stdcall;
    function Compare(psi: IShellItem; hint: DWORD; out piOrder: Integer): HResult; stdcall;
  end;

  IShellItem2 = interface(IShellItem)
    ['{7E9FB0D3-919F-4307-AB2E-9B1860310C93}']
    function GetPropertyStore(flags: DWORD; constref riid: TGUID; out ppv): HResult; stdcall;
    function GetPropertyStoreWithCreateObject(flags: DWORD; punkCreateObject: IUnknown; constref riid: TGUID; out ppv): HResult; stdcall;
    function GetPropertyStoreForKeys(rgKeys: Pointer; cKeys: UINT; flags: DWORD; constref riid: TGUID; out ppv): HResult; stdcall;
    function GetPropertyDescriptionList(constref keyType: TPropertyKey; constref riid: TGUID; out ppv): HResult; stdcall;
    function Update(pbc: Pointer): HResult; stdcall;
    function GetProperty(constref key: TPropertyKey; pv: Pointer): HResult; stdcall;
    function GetCLSID(constref key: TPropertyKey; out pclsid: TGUID): HResult; stdcall;
    function GetFileTime(constref key: TPropertyKey; out pft: TFileTime): HResult; stdcall;
    function GetInt32(constref key: TPropertyKey; out pi: Integer): HResult; stdcall;
    function GetString(constref key: TPropertyKey; out ppsz: PWideChar): HResult; stdcall;
    function GetUInt32(constref key: TPropertyKey; out pui: DWORD): HResult; stdcall;
    function GetUInt64(constref key: TPropertyKey; out pull: QWord): HResult; stdcall;
    function GetBool(constref key: TPropertyKey; out pf: LongBool): HResult; stdcall;
  end;

  IEnumShellItems = interface(IUnknown)
    ['{70629033-E363-4A28-A567-0DB78006E6D7}']
    function Next(celt: ULONG; out rgelt: IShellItem; pceltFetched: PULONG): HResult; stdcall;
    function Skip(celt: ULONG): HResult; stdcall;
    function Reset: HResult; stdcall;
    function Clone(out ppenum: IEnumShellItems): HResult; stdcall;
  end;

  IFileOperation = interface(IUnknown)
    ['{947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8}']
    function Advise(pfops: IUnknown; out pdwCookie: DWORD): HResult; stdcall;
    function Unadvise(dwCookie: DWORD): HResult; stdcall;
    function SetOperationFlags(dwOperationFlags: DWORD): HResult; stdcall;
    function SetProgressMessage(pszMessage: PWideChar): HResult; stdcall;
    function SetProgressDialog(popd: IUnknown): HResult; stdcall;
    function SetProperties(pproparray: IUnknown): HResult; stdcall;
    function SetOwnerWindow(hwndOwner: HWND): HResult; stdcall;
    function ApplyPropertiesToItem(psiItem: IShellItem): HResult; stdcall;
    function ApplyPropertiesToItems(punkItems: IUnknown): HResult; stdcall;
    function RenameItem(psiItem: IShellItem; pszNewName: PWideChar; pfopsItem: IUnknown): HResult; stdcall;
    function RenameItems(pUnkItems: IUnknown; pszNewName: PWideChar): HResult; stdcall;
    function MoveItem(psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: PWideChar; pfopsItem: IUnknown): HResult; stdcall;
    function MoveItems(punkItems: IUnknown; psiDestinationFolder: IShellItem): HResult; stdcall;
    function CopyItem(psiItem: IShellItem; psiDestinationFolder: IShellItem; pszCopyName: PWideChar; pfopsItem: IUnknown): HResult; stdcall;
    function CopyItems(punkItems: IUnknown; psiDestinationFolder: IShellItem): HResult; stdcall;
    function DeleteItem(psiItem: IShellItem; pfopsItem: IUnknown): HResult; stdcall;
    function DeleteItems(punkItems: IUnknown): HResult; stdcall;
    function NewItem(psiDestinationFolder: IShellItem; dwFileAttributes: DWORD; pszName: PWideChar; pszTemplateName: PWideChar; pfopsItem: IUnknown): HResult; stdcall;
    function PerformOperations: HResult; stdcall;
    function GetAnyOperationsAborted(out pfAnyOperationsAborted: LongBool): HResult; stdcall;
  end;

const
  PKEY_Size: TPropertyKey = (fmtid: '{B725F130-47EF-101A-A5F1-02608C9EEBAC}'; pid: 12);  // System.Size
  PKEY_DateModified: TPropertyKey = (fmtid: '{B725F130-47EF-101A-A5F1-02608C9EEBAC}'; pid: 14);  // System.DateModified

function SHGetKnownFolderItem(constref rfid: TGUID; flags: DWORD; hToken: THandle; constref riid: TGUID;
  out ppv): HResult; stdcall; external 'shell32' name 'SHGetKnownFolderItem';
function SHCreateItemFromParsingName(pszPath: PWideChar; pbc: Pointer; constref riid: TGUID;
  out ppv): HResult; stdcall; external 'shell32' name 'SHCreateItemFromParsingName';
function SHGetIDListFromObject(punk: IUnknown; out ppidl: Pointer): HResult; stdcall;
  external 'shell32' name 'SHGetIDListFromObject';
function SHCreateItemFromIDList(pidl: Pointer; constref riid: TGUID; out ppv): HResult; stdcall;
  external 'shell32' name 'SHCreateItemFromIDList';
function ILGetSize(pidl: Pointer): UINT; stdcall; external 'shell32' name 'ILGetSize';

var
  ComReady: Boolean = False;  // COM was initialized for this thread

{ Makes sure COM is initialized (an earlier initialization by the program is fine too). }
procedure NeedCom;
begin
  if ComReady then Exit;
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);  // the Shell needs a single-threaded apartment
  ComReady := True;
end;

{ The name of an item in the form Sigdn asks for, as UTF-8. }
function ItemName(It: IShellItem; Sigdn: DWORD): string;
var
  P: PWideChar;  // P: the name, allocated by the Shell
begin
  Result := '';
  if Succeeded(It.GetDisplayName(Sigdn, P)) and (P <> nil) then
  begin
    Result := UTF8Encode(WideString(P));  // to UTF-8
    CoTaskMemFree(P);  // the Shell's memory
  end;
end;

{ The Shell attributes of an item from Mask (0 when the Shell does not tell). }
function Attrs(It: IShellItem; Mask: DWORD): DWORD;
begin
  if Failed(It.GetAttributes(Mask, Result)) then Result := 0;
end;

{ An Id that finds the item again: "pidl:" and the Shell's item ID list in hex. The parsing names of
  files and folders inside a device cannot be parsed back (only the device's own name can), but the
  ID list works while the device stays connected. }
function ItemToId(It: IShellItem): string;
var
  P: Pointer;  // P: the item ID list, allocated by the Shell
  N: UINT;  // N: its size in bytes
begin
  Result := '';
  if Failed(SHGetIDListFromObject(It, P)) or (P = nil) then Exit;
  N := ILGetSize(P);
  SetLength(Result, N * 2);
  BinToHex(PChar(P), PChar(Result), N);  // two hex digits per byte
  Result := 'pidl:' + Result;
  CoTaskMemFree(P);
end;

{ The item an Id names (see ItemToId; a path or parsing name works too), or nil. }
function ItemFromId(const Id: string): IShellItem;
var
  B: array of Byte;  // B: the item ID list
  Hex: string;  // Hex: its hex digits
begin
  Result := nil;
  NeedCom;
  if Copy(Id, 1, 5) = 'pidl:' then
  begin
    Hex := Copy(Id, 6, MaxInt);
    B := nil;  // sized below
    SetLength(B, Length(Hex) div 2);
    if (Length(B) = 0) or (HexToBin(PChar(Hex), PChar(@B[0]), Length(B)) <> Length(B)) then Exit;
    if Failed(SHCreateItemFromIDList(@B[0], IShellItem, Result)) then Result := nil;
  end
  else if Failed(SHCreateItemFromParsingName(PWideChar(UTF8Decode(Id)), nil, IShellItem, Result)) then
    Result := nil;
end;

{ Puts every child of Folder in List; False when the folder cannot be listed. }
function Children(Folder: IShellItem; List: IInterfaceList): Boolean;
var
  En: IEnumShellItems;  // En: the children, one by one
  It: IShellItem;  // It: a child
  Got: ULONG;  // Got: children returned by Next
begin
  Result := Succeeded(Folder.BindToHandler(nil, BHID_EnumItems, IEnumShellItems, En)) and (En <> nil);
  if not Result then Exit;
  while (En.Next(1, It, @Got) = S_OK) and (Got = 1) do
  begin
    List.Add(It);  // keep it
    It := nil;  // Next fills a fresh reference
  end;
end;

{ True when an item is a folder (or a device storage) and not a file. }
function IsFolder(It: IShellItem): Boolean;
begin
  Result := Attrs(It, SFGAO_FOLDER or SFGAO_STREAM) and (SFGAO_FOLDER or SFGAO_STREAM) = SFGAO_FOLDER;
end;
{$ENDIF}

function DevicesSupported: Boolean;
begin
  {$IFDEF WINDOWS}Result := True;{$ELSE}Result := False;{$ENDIF}
end;

procedure ListDevices(Names, Ids: TStrings);
{$IFDEF WINDOWS}
var
  Pc, It: IShellItem;  // Pc: This PC; It: an entry of This PC
  L: IInterfaceList;  // L: entries of This PC
  I: Integer;  // I: loop counter
  Parse: string;  // Parse: parsing name of the entry
{$ENDIF}
begin
  Names.Clear;
  Ids.Clear;
  {$IFDEF WINDOWS}
  NeedCom;
  if Failed(SHGetKnownFolderItem(FOLDERID_ComputerFolder, 0, 0, IShellItem, Pc)) then Exit;  // no This PC
  L := TInterfaceList.Create;
  if not Children(Pc, L) then Exit;
  for I := 0 to L.Count - 1 do
  begin
    It := IShellItem(L[I]);
    Parse := ItemName(It, SIGDN_DESKTOPABSOLUTEPARSING);
    // a portable device has no file system path, and its parsing name holds the device path \\?\usb#...
    if (Attrs(It, SFGAO_FILESYSTEM) and SFGAO_FILESYSTEM = 0) and (Pos('\\?\', Parse) > 0) then
    begin
      Names.Add(ItemName(It, SIGDN_NORMALDISPLAY));  // the name Explorer shows (for example "D700")
      Ids.Add(ItemToId(It));  // finds it again
    end;
  end;
  {$ENDIF}
end;

procedure ListDeviceFolders(const DevId: string; Names, Ids: TStrings);
{$IFDEF WINDOWS}
var
  Dev, St, Fo: IShellItem;  // Dev: the device; St: a storage; Fo: a folder of the storage
  LS, LF: IInterfaceList;  // LS: storages; LF: folders of one storage
  I, J: Integer;  // I, J: loop counters
  SName, FName: string;  // SName, FName: names of the storage and the folder
{$ENDIF}
begin
  Names.Clear;
  Ids.Clear;
  {$IFDEF WINDOWS}
  Dev := ItemFromId(DevId);
  if Dev = nil then Exit;  // unplugged meanwhile
  LS := TInterfaceList.Create;
  if not Children(Dev, LS) then Exit;  // a locked phone shows no storage
  for I := 0 to LS.Count - 1 do
  begin
    St := IShellItem(LS[I]);
    if not IsFolder(St) then Continue;  // a storage is a folder
    SName := ItemName(St, SIGDN_NORMALDISPLAY);
    LF := TInterfaceList.Create;
    if not Children(St, LF) then Continue;
    for J := 0 to LF.Count - 1 do
    begin
      Fo := IShellItem(LF[J]);
      FName := ItemName(Fo, SIGDN_NORMALDISPLAY);
      if IsFolder(Fo) and (Copy(FName, 1, 1) <> '.') then  // hidden folders (".thumbnails") are left out
      begin
        Names.Add(SName + '\' + FName);  // "Storage\Folder"
        Ids.Add(ItemToId(Fo));  // finds it again
      end;
    end;
  end;
  {$ENDIF}
end;

{$IFDEF WINDOWS}
{ Size and time of a file item. }
procedure ItemSizeTime(It: IShellItem; out Size, Time: Int64);
var
  It2: IShellItem2;  // It2: the item with property access
  Q: QWord;  // Q: the size
  Ft: TFileTime;  // Ft: the time
begin
  Size := -1;
  Time := 0;
  if not Supports(It, IShellItem2, It2) then Exit;
  if Succeeded(It2.GetUInt64(PKEY_Size, Q)) then Size := Q;
  if Succeeded(It2.GetFileTime(PKEY_DateModified, Ft)) then Time := Int64(Ft);
end;

{ Walks one folder for ListDeviceFiles. }
function WalkFolder(Folder: IShellItem; const Rel: string; Files: TObjectList; OnCount: TDeviceCountProc): Boolean;
var
  L: IInterfaceList;  // L: children of the folder
  I: Integer;  // I: loop counter
  It: IShellItem;  // It: a child
  Nm: string;  // Nm: its name
  F: TDeviceFile;  // F: a file found
begin
  Result := True;
  L := TInterfaceList.Create;
  if not Children(Folder, L) then Exit(False);
  for I := 0 to L.Count - 1 do
  begin
    It := IShellItem(L[I]);
    Nm := ItemName(It, SIGDN_NORMALDISPLAY);
    if (Nm = '') or (Nm[1] = '.') then Continue;  // hidden entries (Android's .thumbnails, .trashed-...)
    if IsFolder(It) then
    begin
      if not WalkFolder(It, Rel + SafeFolderName(Nm) + PathDelim, Files, OnCount) then Exit(False);
    end
    else
    begin
      F := TDeviceFile.Create;
      F.Rel := Rel + SafeFolderName(Nm);  // its place in the staging folder
      F.Id := ItemToId(It);  // finds it again for copying and deleting
      ItemSizeTime(It, F.Size, F.Time);
      F.CanDelete := Attrs(It, SFGAO_CANDELETE) and SFGAO_CANDELETE <> 0;  // an iPhone says no
      Files.Add(F);
      if Assigned(OnCount) and not OnCount(Files.Count) then Exit(False);  // canceled
    end;
  end;
end;
{$ENDIF}

function ListDeviceFiles(const FolderId, RelBase: string; Files: TObjectList;
  OnCount: TDeviceCountProc): Boolean;
{$IFDEF WINDOWS}
var
  Fo: IShellItem;  // Fo: the folder
{$ENDIF}
begin
  Result := False;
  {$IFDEF WINDOWS}
  Fo := ItemFromId(FolderId);
  if Fo = nil then Exit;  // unplugged or locked meanwhile
  Result := WalkFolder(Fo, IncludeTrailingPathDelimiter(RelBase), Files, OnCount);
  {$ENDIF}
end;

function StagedCopyMatches(F: TDeviceFile; const Fn: string): Boolean;
{$IFDEF WINDOWS}
var
  D: TWin32FileAttributeData;  // D: size and times of the staged file
  W: WideString;  // W: its name for the API
{$ENDIF}
begin
  Result := False;
  {$IFDEF WINDOWS}
  W := UTF8Decode(Fn);
  if not GetFileAttributesExW(PWideChar(W), GetFileExInfoStandard, @D) then Exit;  // not staged yet
  Result := ((Int64(D.nFileSizeHigh) shl 32) or D.nFileSizeLow = F.Size) and
    (Abs(Int64(D.ftLastWriteTime) - F.Time) < 20000000);  // same size, time within 2 s
  {$ENDIF}
end;

function CopyDeviceFile(F: TDeviceFile; const Fn: string; OnBytes: TDeviceCopyProc; out Err: string): Boolean;
{$IFDEF WINDOWS}
const
  BufSize = 262144;  // read in 256 KB pieces
var
  It: IShellItem;  // It: the device file
  Stm: IStream;  // Stm: its contents
  Buf: array of Byte;  // Buf: one piece
  Got: DWORD;  // Got: bytes in the piece
  Ctx: TMD5Context;  // Ctx: MD5 of what was read
  Dig: TMD5Digest;  // Dig: its result
  Fs: TFileStream;  // Fs: the staged file
  Part: string;  // Part: name while copying
  Total: Int64;  // Total: bytes copied
  Ft: TFileTime;  // Ft: the device's time
  Ok: Boolean;  // Ok: copy finished without errors
{$ENDIF}
begin
  Result := False;
  Err := 'Device files can only be read on Windows.';
  {$IFDEF WINDOWS}
  Err := '';
  It := ItemFromId(F.Id);
  if (It = nil) or Failed(It.BindToHandler(nil, BHID_Stream, IStream, Stm)) or (Stm = nil) then
  begin
    Err := 'cannot open the file on the device (unplugged or locked?)';
    Exit;
  end;
  ForceDirectoriesUTF8(ExtractFilePath(Fn));
  Part := Fn + '.part';
  Buf := nil;  // sized below
  SetLength(Buf, BufSize);
  Total := 0;
  Ok := False;
  MD5Init(Ctx);
  try
    Fs := TFileStream.Create(Part, fmCreate);
    try
      repeat
        Got := 0;
        if Failed(Stm.Read(@Buf[0], BufSize, @Got)) then
        begin
          Err := Format('read error after %d bytes', [Total]);
          Break;
        end;
        if Got > 0 then
        begin
          MD5Update(Ctx, Buf[0], Got);  // MD5 of what came from the device
          Fs.WriteBuffer(Buf[0], Got);
          Inc(Total, Got);
          if Assigned(OnBytes) and not OnBytes(Total) then
          begin
            Err := 'canceled';
            Break;
          end;
        end
        else Ok := True;  // end of the file
      until Got = 0;
      if Ok and (F.Time <> 0) then
      begin
        Ft := TFileTime(F.Time);
        SetFileTime(Fs.Handle, @Ft, nil, @Ft);  // the device's date as created and modified time
      end;
    finally
      Fs.Free;
    end;
  except
    on E: Exception do
    begin
      Err := E.Message;
      Ok := False;
    end;
  end;
  if Ok and (F.Size >= 0) and (Total <> F.Size) then
  begin
    Err := Format('copied %d bytes, the device reports %d', [Total, F.Size]);
    Ok := False;
  end;
  if Ok then
  begin
    MD5Final(Ctx, Dig);
    if not MD5Match(Dig, MD5File(Part)) then  // read the copy back: it must hold what came from the device
    begin
      Err := 'the copy does not match what was read (MD5)';
      Ok := False;
    end;
  end;
  if Ok then
  begin
    DeleteFileUTF8(Fn);  // an older copy
    Ok := RenameFileUTF8(Part, Fn);
    if not Ok then Err := 'cannot rename the staged copy';
  end;
  if not Ok then DeleteFileUTF8(Part);  // no half files
  Result := Ok;
  {$ENDIF}
end;

function DeleteDeviceFile(const Id: string; out Err: string): Boolean;
{$IFDEF WINDOWS}
var
  It: IShellItem;  // It: the device file
  Op: IFileOperation;  // Op: the Shell's delete
  Aborted: LongBool;  // Aborted: the Shell stopped the operation
  HR: HResult;  // HR: result of the operation
{$ENDIF}
begin
  Result := False;
  Err := 'Device files can only be deleted on Windows.';
  {$IFDEF WINDOWS}
  Err := '';
  It := ItemFromId(Id);
  if It = nil then
  begin
    Err := 'the file is no longer on the device';
    Exit;
  end;
  if Attrs(It, SFGAO_CANDELETE) and SFGAO_CANDELETE = 0 then
  begin
    Err := 'the device does not allow deleting it';
    Exit;
  end;
  if Failed(CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_ALL, IFileOperation, Op)) or (Op = nil) then
  begin
    Err := 'the Shell delete is not available';
    Exit;
  end;
  Op.SetOperationFlags(FOF_SILENT or FOF_NOCONFIRMATION or FOF_NOERRORUI);  // the program asked and reports
  HR := Op.DeleteItem(It, nil);
  if Succeeded(HR) then HR := Op.PerformOperations;
  Aborted := False;
  Op.GetAnyOperationsAborted(Aborted);
  Result := Succeeded(HR) and not Aborted;
  if not Result then Err := Format('the device refused (error %x)', [HR]);
  {$ENDIF}
end;

function StagingDir(const DevName: string): string;
begin
  Result := CacheDir + 'device' + PathDelim + SafeFolderName(DevName) + PathDelim;
end;

{ Adds up the file sizes below Dir. }
function FolderBytes(const Dir: string): Int64;
var
  SR: TSearchRec;  // SR: an entry of the folder
begin
  Result := 0;
  if FindFirstUTF8(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
          Inc(Result, FolderBytes(IncludeTrailingPathDelimiter(Dir) + SR.Name));
      end
      else
        Inc(Result, SR.Size);
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
end;

function StagingBytes: Int64;
begin
  Result := FolderBytes(CacheDir + 'device');
end;

function SafeFolderName(const S: string): string;
var
  I: Integer;  // I: loop counter
begin
  Result := Trim(S);
  for I := 1 to Length(Result) do
    if Result[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then Result[I] := '_';
  while (Result <> '') and (Result[Length(Result)] in ['.', ' ']) do Delete(Result, Length(Result), 1);  // Windows drops these
  if Result = '' then Result := 'device';
end;

end.
