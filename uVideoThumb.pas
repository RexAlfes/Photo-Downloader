unit uVideoThumb;

{$mode objfpc}{$H+}

{ Thumbnails of video files (MP4, MOV, LRV) from the operating system.
  Windows: the Shell thumbnail provider (IShellItemImageFactory), the same frame Explorer shows.
  Linux:   ffmpegthumbnailer, or ffmpeg, when one of them is installed.
  No video is decoded by this program itself. When the system cannot supply a frame the caller
  falls back to a picture stored in or next to the video. }

interface

uses
  Classes, SysUtils, Graphics;

{ Fills Bmp with a frame of the video, at most Box pixels on the long side. On failure the result is
  False and Err tells why. }
function LoadVideoThumb(const FileName: string; Box: Integer; Bmp: TBitmap; out Err: string): Boolean;

implementation

uses
  {$IFDEF WINDOWS}
  Windows, ActiveX, LazUTF8,
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

{ Asks the Windows Shell for the thumbnail of a file. }
function ShellThumb(const FileName: string; Box: Integer; Bmp: Graphics.TBitmap; out Err: string): Boolean;
var
  Lib: HMODULE;  // Lib: handle of shell32.dll
  WName: UnicodeString;  // WName: file name in UTF-16
  Fact: IShellItemImageFactory;  // Fact: shell object for the file
  HB: HBITMAP;  // HB: bitmap handle returned by the shell
  Tmp: Graphics.TBitmap;  // Tmp: bitmap that owns the handle
  HR: HRESULT;  // HR: result code of a call
begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  if not ShellReady then  // first use: look the function up
  begin
    ShellReady := True;  // do this only once
    CoInitializeEx(nil, COINIT_APARTMENTTHREADED);  // the shell needs COM; an earlier initialization is fine too
    Lib := LoadLibrary('shell32.dll');  // load the shell library
    if Lib <> 0 then Pointer(CreateItem) := GetProcAddress(Lib, 'SHCreateItemFromParsingName');  // not present before Windows Vista
  end;
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

{ Makes a thumbnail with ffmpegthumbnailer or ffmpeg. }
function FfThumb(const FileName: string; Box: Integer; Bmp: TBitmap; out Err: string): Boolean;
var
  Tmp: string;  // Tmp: temporary JPEG written by the tool
  Jpg: TJPEGImage;  // Jpg: that JPEG loaded
  Side: string;  // Side: box size as text
begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  if not ToolsLooked then  // first use: search for the programs
  begin
    ToolsLooked := True;  // do this only once
    FfThumbExe := FindExe('ffmpegthumbnailer');  // fast thumbnail tool
    FfmpegExe := FindExe('ffmpeg');  // general tool
  end;
  if (FfThumbExe = '') and (FfmpegExe = '') then
  begin
    Err := 'neither ffmpegthumbnailer nor ffmpeg is installed';  // nothing to use
    Exit;
  end;
  Side := IntToStr(Box);  // box size as text
  Tmp := GetTempDir(False) + 'photodownloader_vthumb_' + IntToStr(GetProcessID) + '.jpg';  // temporary file
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
