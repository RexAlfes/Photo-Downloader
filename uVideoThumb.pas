unit uVideoThumb;

{$mode objfpc}{$H+}

{ Thumbnails of video files (MP4, MOV, LRV) from the operating system.
  Windows: the Shell thumbnail provider (IShellItemImageFactory), the same frame Explorer shows.
  Linux:   ffmpegthumbnailer, or ffmpeg, when one of them is installed.
  No video is decoded by this program itself. When the system cannot supply a frame the caller
  falls back to a picture stored in or next to the video.

  VideoThumbData does the same without window system objects of the program, so the thumbnail threads
  (uThumbPool) can ask for several frames at once: each video is its own request to Windows, or its
  own run of the tool on Linux. }

interface

uses
  Classes, SysUtils, Graphics;

{ Fills Bmp with a frame of the video, at most Box pixels on the long side. On failure the result is
  False and Err tells why. }
function LoadVideoThumb(const FileName: string; Box: Integer; Bmp: TBitmap; out Err: string): Boolean;

{ For threads: the frame as picture data in memory, or nil when the system has none. IsBmp True: a
  finished 24-bit BMP of at most Box pixels (Windows); False: a JPEG (Linux). Call VideoThumbPrepare once
  on the main thread before threads use it, and VideoThreadBegin / VideoThreadEnd in each thread. }
function VideoThumbData(const FileName: string; Box: Integer; out IsBmp: Boolean): TMemoryStream;
procedure VideoThumbPrepare;  // one-time setup (looks up the Shell function, or the tools on Linux)
procedure VideoThreadBegin;  // a thread starts asking for frames (Windows: sets up COM for it)
procedure VideoThreadEnd;  // the thread is done

implementation

uses
  {$IFDEF WINDOWS}
  Windows, ActiveX, LazUTF8, Math,
  {$ELSE}
  Process, FPReadJPEG,
  {$ENDIF}
  LazFileUtils;

{$IFDEF WINDOWS}

type
  { Shell interface that returns the thumbnail of a file. The SIZE argument is passed as one 64-bit
    value (width in the low half, height in the high half), which is how the 8-byte structure travels. }
  IShellItemImageFactory = interface(IUnknown)
    ['{BCC18B79-BA16-442F-80C4-8A59C30C463B}']
    function GetImage(Size: Int64; Flags: DWORD; out Bitmap: HBITMAP): HRESULT; stdcall;
  end;

  TCreateItemFromParsingName = function(Path: PWideChar; BindCtx: Pointer;  // SHCreateItemFromParsingName from shell32
    const RIID: TGUID; out Item): HRESULT; stdcall;

const
  SiigbfThumbnailOnly = 8;  // ask for a real thumbnail, never for the generic file icon

var
  CreateItem: TCreateItemFromParsingName = nil;  // the shell function once it was found
  ShellReady: Boolean = False;  // True after the first setup attempt

{ Looks the shell function up (once, on the main thread). }
procedure NeedShell;
var
  Lib: HMODULE;  // Lib: handle of shell32.dll
begin
  if ShellReady then Exit;  // done before
  ShellReady := True;  // do this only once
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);  // the shell needs COM; an earlier initialization is fine too
  Lib := LoadLibrary('shell32.dll');  // load the shell library
  if Lib <> 0 then Pointer(CreateItem) := GetProcAddress(Lib, 'SHCreateItemFromParsingName');  // not present before Windows Vista
end;

type
  { BMP file header (14 bytes) and info header (40 bytes), to build a BMP in memory }
  TBmpFileHdr = packed record
    bfType: Word;
    bfSize, bfReserved, bfOffBits: LongWord;
  end;
  TBmpInfoHdr = packed record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPels, biYPels: LongInt;
    biClrUsed, biClrImportant: LongWord;
  end;

{ The Shell thumbnail of a file as a 24-bit BMP in memory (transparent parts on white), or nil. Uses only
  the Windows API, no objects of the program, so a thread may call it (after VideoThreadBegin). }
function ShellThumbData(const FileName: string; Box: Integer): TMemoryStream;
var
  WName: UnicodeString;  // WName: file name in UTF-16
  Fact: IShellItemImageFactory;  // Fact: shell object for the file
  HB: HBITMAP;  // HB: bitmap handle returned by the shell
  BM: Windows.BITMAP;  // BM: its description
  IH: TBmpInfoHdr;  // IH: info header (for the pixel request and the BMP)
  FH: TBmpFileHdr;  // FH: BMP file header
  Src, Row: array of Byte;  // Src: the pixels as 32-bit rows; Row: one 24-bit row of the BMP
  W, H, X, Y, LineLen, A: Integer;  // W, H: size; X, Y: pixel; LineLen: bytes per BMP row; A: alpha of a pixel
  DC: HDC;  // DC: screen device context
  P: PByte;  // P: a source pixel
  HasAlpha: Boolean;  // HasAlpha: the bitmap uses its alpha channel
begin
  Result := nil;  // nothing yet
  if not Assigned(CreateItem) then Exit;  // old Windows
  WName := UTF8ToUTF16(FileName);  // the shell wants UTF-16
  Fact := nil;
  if (CreateItem(PWideChar(WName), nil, IShellItemImageFactory, Fact) <> S_OK) or (Fact = nil) then Exit;  // no shell item
  HB := 0;
  if (Fact.GetImage(Int64(Box) or (Int64(Box) shl 32), SiigbfThumbnailOnly, HB) <> S_OK) or (HB = 0) then Exit;  // no thumbnail
  try
    if GetObject(HB, SizeOf(BM), @BM) = 0 then Exit;  // not a bitmap
    W := BM.bmWidth;
    H := Abs(BM.bmHeight);
    if (W <= 0) or (H <= 0) or (W > 8192) or (H > 8192) then Exit;  // nothing usable
    FillChar(IH, SizeOf(IH), 0);
    IH.biSize := SizeOf(IH);
    IH.biWidth := W;
    IH.biHeight := H;  // positive: rows bottom-up, as a BMP file stores them
    IH.biPlanes := 1;
    IH.biBitCount := 32;  // ask for 32 bits to see the alpha channel
    Src := nil;
    SetLength(Src, W * H * 4);
    DC := GetDC(0);  // any device context serves for the conversion
    try
      if GetDIBits(DC, HB, 0, H, @Src[0], Windows.PBitmapInfo(@IH)^, DIB_RGB_COLORS) = 0 then Exit;  // pixels not available
    finally
      ReleaseDC(0, DC);
    end;
    HasAlpha := False;  // an alpha channel of zeros means "not used"
    P := @Src[0];
    for X := 0 to W * H - 1 do
    begin
      if P[3] <> 0 then
      begin
        HasAlpha := True;
        Break;
      end;
      Inc(P, 4);
    end;
    LineLen := ((W * 3 + 3) div 4) * 4;  // BMP rows are padded to 4 bytes
    Row := nil;
    SetLength(Row, LineLen);
    FH.bfType := $4D42;  // "BM"
    FH.bfSize := SizeOf(FH) + SizeOf(IH) + LongWord(LineLen) * LongWord(H);
    FH.bfReserved := 0;
    FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
    IH.biBitCount := 24;  // the BMP itself is plain 24-bit
    IH.biSizeImage := LongWord(LineLen) * LongWord(H);
    Result := TMemoryStream.Create;
    Result.WriteBuffer(FH, SizeOf(FH));
    Result.WriteBuffer(IH, SizeOf(IH));
    for Y := 0 to H - 1 do  // rows are bottom-up in both
    begin
      P := @Src[Y * W * 4];
      for X := 0 to W - 1 do
      begin
        if HasAlpha then
        begin
          A := 255 - P[3];  // what white adds (the shell's colors are multiplied by alpha already)
          Row[X * 3] := Byte(Min(255, P[0] + A));
          Row[X * 3 + 1] := Byte(Min(255, P[1] + A));
          Row[X * 3 + 2] := Byte(Min(255, P[2] + A));
        end
        else
        begin
          Row[X * 3] := P[0];  // blue, green, red as they are
          Row[X * 3 + 1] := P[1];
          Row[X * 3 + 2] := P[2];
        end;
        Inc(P, 4);
      end;
      Result.WriteBuffer(Row[0], LineLen);
    end;
    Result.Position := 0;  // ready to be read
  finally
    DeleteObject(HB);  // free the shell bitmap
  end;
end;

{ Asks the Windows Shell for the thumbnail of a file. }
function ShellThumb(const FileName: string; Box: Integer; Bmp: Graphics.TBitmap; out Err: string): Boolean;
var
  WName: UnicodeString;  // WName: file name in UTF-16
  Fact: IShellItemImageFactory;  // Fact: shell object for the file
  HB: HBITMAP;  // HB: bitmap handle returned by the shell
  Tmp: Graphics.TBitmap;  // Tmp: bitmap that owns the handle
  HR: HRESULT;  // HR: result code of a call
begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  NeedShell;  // first use: look the function up
  if not Assigned(CreateItem) then
  begin
    Err := 'the Windows Shell cannot make thumbnails on this system';  // old Windows
    Exit;
  end;
  WName := UTF8ToUTF16(FileName);  // the shell wants UTF-16
  Fact := nil;  // nothing yet
  HR := CreateItem(PWideChar(WName), nil, IShellItemImageFactory, Fact);  // shell item for the file
  if (HR <> S_OK) or (Fact = nil) then
  begin
    Err := 'shell item could not be created (code ' + IntToHex(Cardinal(HR), 8) + ')';  // report the code
    Exit;
  end;
  HB := 0;  // no bitmap yet
  HR := Fact.GetImage(Int64(Box) or (Int64(Box) shl 32), SiigbfThumbnailOnly, HB);  // ask for the thumbnail
  if (HR <> S_OK) or (HB = 0) then
  begin
    Err := 'the Windows Shell has no thumbnail for this video (code ' + IntToHex(Cardinal(HR), 8) + ')';  // codec missing, for example
    Exit;
  end;
  Tmp := Graphics.TBitmap.Create;  // takes over the handle
  try
    Tmp.Handle := HB;  // the bitmap is freed together with Tmp
    if (Tmp.Width <= 0) or (Tmp.Height <= 0) then
    begin
      Err := 'the shell returned an empty bitmap';  // nothing to use
      Exit;
    end;
    Bmp.PixelFormat := pf24bit;  // plain opaque pixels
    Bmp.SetSize(Tmp.Width, Tmp.Height);  // same size as the shell bitmap
    Bmp.Canvas.Brush.Color := clWhite;  // background under any transparency
    Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);  // clear the bitmap
    Bmp.Canvas.Draw(0, 0, Tmp);  // copy the shell bitmap
    Result := True;  // success
  finally
    Tmp.Free;  // free the shell bitmap
  end;
end;

{$ELSE}

var
  FfThumbExe: string = '';  // path of ffmpegthumbnailer ('' when not installed)
  FfmpegExe: string = '';  // path of ffmpeg ('' when not installed)
  ToolsLooked: Boolean = False;  // True after the programs were searched for

{ Finds a program in the folders of the PATH variable; '' when it is not there. }
function FindExe(const Name: string): string;
var
  Dirs: TStringList;  // Dirs: folders of the PATH variable
  I: Integer;  // I: loop counter
begin
  Result := '';  // not found yet
  Dirs := TStringList.Create;  // list of folders
  try
    Dirs.Delimiter := ':';  // PATH folders are separated by colons
    Dirs.StrictDelimiter := True;  // do not split at blanks
    Dirs.DelimitedText := GetEnvironmentVariable('PATH');  // split the variable
    for I := 0 to Dirs.Count - 1 do  // look in each folder
      if (Dirs[I] <> '') and FileExistsUTF8(IncludeTrailingPathDelimiter(Dirs[I]) + Name) then  // program present
      begin
        Result := IncludeTrailingPathDelimiter(Dirs[I]) + Name;  // full path
        Break;  // stop searching
      end;
  finally
    Dirs.Free;  // free the list
  end;
end;

{ Runs a program and waits for it (at most TimeoutMs); True when it ended normally with code 0. }
function RunTool(const Exe: string; const Args: array of string; TimeoutMs: Integer): Boolean;
var
  P: TProcess;  // P: the child process
  I: Integer;  // I: loop counter
  T0: QWord;  // T0: start time
begin
  Result := False;  // assume failure
  P := TProcess.Create(nil);  // create the process object
  try
    P.Executable := Exe;  // program to run
    for I := 0 to High(Args) do P.Parameters.Add(Args[I]);  // its arguments
    P.Options := [poNoConsole];  // no window
    try
      P.Execute;  // start it
    except
      Exit;  // could not start
    end;
    T0 := GetTickCount64;  // remember the start time
    while P.Running and (GetTickCount64 - T0 < QWord(TimeoutMs)) do Sleep(15);  // wait for the end
    if P.Running then  // took too long
    begin
      P.Terminate(1);  // stop it
      Exit;
    end;
    Result := P.ExitStatus = 0;  // success when it reported no error
  finally
    P.Free;  // free the process object
  end;
end;

{ Searches for the tools (once, on the main thread). }
procedure NeedTools;
begin
  if ToolsLooked then Exit;  // done before
  ToolsLooked := True;  // do this only once
  FfThumbExe := FindExe('ffmpegthumbnailer');  // fast thumbnail tool
  FfmpegExe := FindExe('ffmpeg');  // general tool
end;

{ Lets ffmpegthumbnailer or ffmpeg write a frame of the video to a temporary JPEG file; Tmp is its name
  (one per thread, so several threads may run tools at once). False, with Err, when there is no frame. }
function FfFrameFile(const FileName: string; Box: Integer; out Tmp, Err: string): Boolean;
var
  Side: string;  // Side: box size as text
begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  Tmp := '';
  NeedTools;  // first use: search for the programs
  if (FfThumbExe = '') and (FfmpegExe = '') then
  begin
    Err := 'neither ffmpegthumbnailer nor ffmpeg is installed';  // nothing to use
    Exit;
  end;
  Side := IntToStr(Box);  // box size as text
  Tmp := GetTempDir(False) + 'photodownloader_vthumb_' + IntToStr(GetProcessID) + '_' +
    IntToStr(PtrUInt(GetCurrentThreadId)) + '.jpg';  // temporary file of this thread
  DeleteFile(Tmp);  // remove any old one
  if FfThumbExe <> '' then
    RunTool(FfThumbExe, ['-i', FileName, '-o', Tmp, '-s', Side, '-q', '6'], 8000);  // frame at 10 percent of the clip
  if (not FileExists(Tmp)) and (FfmpegExe <> '') then  // no frame yet: try ffmpeg
  begin
    RunTool(FfmpegExe, ['-nostdin', '-v', 'error', '-y', '-ss', '1', '-i', FileName, '-frames:v', '1',  // frame at one second
      '-vf', 'scale=w=' + Side + ':h=' + Side + ':force_original_aspect_ratio=decrease', '-q:v', '4', Tmp], 8000);
    if not FileExists(Tmp) then  // clip shorter than one second: take the first frame
      RunTool(FfmpegExe, ['-nostdin', '-v', 'error', '-y', '-i', FileName, '-frames:v', '1',
        '-vf', 'scale=w=' + Side + ':h=' + Side + ':force_original_aspect_ratio=decrease', '-q:v', '4', Tmp], 8000);
  end;
  if not FileExists(Tmp) then
  begin
    Err := 'ffmpeg could not extract a frame';  // damaged or unsupported video
    Exit;
  end;
  Result := True;  // the frame is in Tmp
end;

{ Makes a thumbnail with ffmpegthumbnailer or ffmpeg. }
function FfThumb(const FileName: string; Box: Integer; Bmp: TBitmap; out Err: string): Boolean;
var
  Tmp: string;  // Tmp: temporary JPEG written by the tool
  Jpg: TJPEGImage;  // Jpg: that JPEG loaded
begin
  Result := False;  // assume failure
  if not FfFrameFile(FileName, Box, Tmp, Err) then Exit;  // no frame
  Jpg := TJPEGImage.Create;  // create the JPEG
  try
    try
      Jpg.LoadFromFile(Tmp);  // read the frame
      if Jpg.Empty then Exit;  // nothing in it
      Bmp.SetSize(Jpg.Width, Jpg.Height);  // same size as the frame
      Bmp.Canvas.Draw(0, 0, Jpg);  // copy the frame
      Result := True;  // success
    except
      on E: Exception do Err := 'frame could not be read: ' + E.Message;  // report the reason
    end;
  finally
    Jpg.Free;  // free the JPEG
    DeleteFile(Tmp);  // remove the temporary file
  end;
end;

{$ENDIF}

procedure VideoThumbPrepare;
begin
  {$IFDEF WINDOWS}
  NeedShell;  // look the shell function up
  {$ELSE}
  NeedTools;  // search for the tools
  {$ENDIF}
end;

procedure VideoThreadBegin;
begin
  {$IFDEF WINDOWS}
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);  // each thread that talks to the shell needs COM
  {$ENDIF}
end;

procedure VideoThreadEnd;
begin
  {$IFDEF WINDOWS}
  CoUninitialize;  // done with COM in this thread
  {$ENDIF}
end;

function VideoThumbData(const FileName: string; Box: Integer; out IsBmp: Boolean): TMemoryStream;
{$IFNDEF WINDOWS}
var
  Tmp, Err: string;  // Tmp: temporary JPEG written by the tool; Err: reason of a failure (not used)
  Fs: TFileStream;  // Fs: that file
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  IsBmp := True;  // a finished BMP
  Result := ShellThumbData(FileName, Box);  // Windows Shell
  {$ELSE}
  IsBmp := False;  // a JPEG
  Result := nil;  // nothing yet
  if not FfFrameFile(FileName, Box, Tmp, Err) then Exit;  // no frame
  try
    try
      Fs := TFileStream.Create(Tmp, fmOpenRead or fmShareDenyNone);  // the frame
      try
        Result := TMemoryStream.Create;
        Result.CopyFrom(Fs, 0);  // all of it
        Result.Position := 0;  // ready to be read
      finally
        Fs.Free;
      end;
    except
      FreeAndNil(Result);  // unreadable: no frame
    end;
  finally
    DeleteFile(Tmp);  // remove the temporary file
  end;
  {$ENDIF}
end;

{ Returns a frame of the video from the operating system. }
function LoadVideoThumb(const FileName: string; Box: Integer; Bmp: Graphics.TBitmap; out Err: string): Boolean;
begin
  {$IFDEF WINDOWS}
  Result := ShellThumb(FileName, Box, Bmp, Err);  // Windows Shell
  {$ELSE}
  Result := FfThumb(FileName, Box, Bmp, Err);  // ffmpegthumbnailer or ffmpeg
  {$ENDIF}
end;

end.
