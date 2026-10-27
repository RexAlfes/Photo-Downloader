unit uHeic;

{$mode objfpc}{$H+}

{ HEIC / HEIF pictures.

  Decoded by the Xelitan HEIC decoder (HeicImageX, bundled in third_party/XelHeic). It is
  pure Pascal: no DLLs or other files are needed. See THIRD_PARTY_NOTICES.md. }

interface

uses
  Classes, SysUtils, Graphics, FPImage;

const
  HeicExts = ';.heic;.heif;.avif;';  // file extensions handled by the HEIC/AVIF decoder

var
  { Reason the last decode failed (class and message), empty when it worked }
  HeicLastError: string = '';
  { True while the caller shows a progress window: the screen is then kept alive (messages are
    processed) during a long decode }
  HeicPump: Boolean = False;
  { Set by the caller (Cancel button): a decode that has run for more than 30 seconds is given up }
  HeicCancel: Boolean = False;
  { Set after a decode had to be given up: the decoder's shared state may still be in use by the
    abandoned work, so no further decodes are started in this session }
  HeicDisabled: Boolean = False;

{ True: the decoder is part of the program }
function HeicEnabled: Boolean;
{ Loads the picture into Pic; False when there is no decoder or the file cannot be decoded }
function LoadHeicPicture(const FileName: string; Pic: TPicture; MaxSide: Integer = 0;
  Fast: Boolean = False): Boolean;
{ Orientation (2..8) that still has to be applied to a decoded HEIC picture of DecW x DecH
  pixels, or 0. Decoders normally apply the file's own rotation ('irot'); this only steps in
  when a quarter turn is asked for (EXIF orientation 5..8) but the picture came back in its
  stored, unturned shape. }
function HeicExtraOrientation(const FileName: string; DecW, DecH, Orient: Integer): Integer;
{ Decodes the picture for the viewer, reduced to at most Target pixels on its long side }
function LoadHeicMemImage(const FileName: string; Target: Integer): TFPMemoryImage;

implementation

uses
  Types, Math, IntfGraphics, Forms, uExif, uScale, HeicImageX, XelHeic, Heif.Decode, Av1.Decoder;

const
  HeicSoftLimitMs = 30000;     // after this a Cancel gives up the decode
  HeicHardLimitMs = 120000;    // after this a decode is given up whatever happens

type
  { The decode runs in its own thread so the window stays alive and can be canceled }
  TDecodeThread = class(TThread)
  public
    Data, Pixels: TBytes;  // Data: file bytes in, Pixels: RGBA out
    MaxSide, W, H: Integer;  // MaxSide: size limit, W and H: decoded size
    Err: string;  // Err: error text, empty when it worked
    procedure Execute; override;
  end;

var
  HeicBusy: Boolean = False;  // True while a decode is running

{ Box-filter reduction of packed RGBA so that the long side is at most MaxSide }
procedure ShrinkRgba(var P: TBytes; var W, H: Integer; MaxSide: Integer);
var
  F, NW, NH, X, Y, DX, DY, C: Integer;  // F: reduction factor, NW and NH: new size, X and Y: new pixel, DX and DY: offsets in a block, C: channel
  S: array[0..3] of Cardinal;  // S: running sums for the four channels
  Q: TBytes;  // Q: reduced picture
  Src, Dst: NativeInt;  // Src and Dst: byte positions in the old and new picture
begin
  if (MaxSide <= 0) or (Max(W, H) <= MaxSide * 3 div 2) then Exit;  // no reduction needed when already close to the wanted size
  F := Max(W, H) div MaxSide;  // whole-number reduction factor
  if F < 2 then Exit;  // a factor below 2 gains nothing
  NW := W div F;  // new width
  NH := H div F;  // new height
  if (NW < 1) or (NH < 1) then Exit;  // too small: leave the picture alone
  Q := nil;  // new buffer
  SetLength(Q, NativeInt(NW) * NH * 4);  // 4 bytes per pixel
  for Y := 0 to NH - 1 do  // every new row
    for X := 0 to NW - 1 do  // every new pixel
    begin
      for C := 0 to 3 do S[C] := 0;  // clear the sums
      for DY := 0 to F - 1 do  // rows of the source block
      begin
        Src := (NativeInt(Y * F + DY) * W + X * F) * 4;  // start of this source row in the block
        for DX := 0 to F - 1 do  // pixels of the source block row
        begin
          for C := 0 to 3 do Inc(S[C], P[Src + C]);  // add the four channels
          Inc(Src, 4);  // next source pixel
        end;
      end;
      Dst := (NativeInt(Y) * NW + X) * 4;  // position of the new pixel
      for C := 0 to 3 do Q[Dst + C] := S[C] div Cardinal(F * F);  // store the average of each channel
    end;
  P := Q;  // replace the picture
  W := NW;  // new width
  H := NH;  // new height
end;

{ Thread body: decodes the file data, then shrinks the result; errors are saved as text. }
procedure TDecodeThread.Execute;
var
  K: Integer;  // K: index into the stack trace
begin
  try
    Pixels := DecodeHeic(Data, W, H);  // decode the file into RGBA pixels
    Data := nil;  // release the file data
    ShrinkRgba(Pixels, W, H, MaxSide);  // reduce to thumbnail size
  except
    on E: Exception do
    begin
      Pixels := nil;  // no pixels on error
      Err := E.ClassName + ': ' + E.Message + ' at ' + BackTraceStrFunc(ExceptAddr);  // error text with the place where it happened
      for K := 0 to ExceptFrameCount - 1 do  // add the call stack
        Err := Err + ' < ' + BackTraceStrFunc(ExceptFrames[K]);  // one stack entry
    end;
  end;
end;

{ Reports that the decoder is part of the program (always True). }
function HeicEnabled: Boolean;
begin
  Result := True;  // decoder is built in
end;

{ Returns the orientation still to be applied to a decoded HEIC picture, or 0 if the decoder already turned it. }
function HeicExtraOrientation(const FileName: string; DecW, DecH, Orient: Integer): Integer;
var
  SW, SH: Integer;  // SW and SH: stored picture size from the file
begin
  Result := 0;  // nothing to do by default
  if not (Orient in [5, 6, 7, 8]) then Exit;  // only quarter turns matter
  if not ReadHeifStoredSize(FileName, SW, SH) then Exit;  // read the stored size from the file
  if SW = SH then Exit;  // a square picture looks the same either way
  if (DecW > DecH) = (SW > SH) then Result := Orient;   // still in the stored shape
end;

{ Decodes a HEIC/AVIF file into Pic using a worker thread; False (with HeicLastError set) on failure. }
function LoadHeicPicture(const FileName: string; Pic: TPicture; MaxSide: Integer; Fast: Boolean): Boolean;
var
  Fs: TFileStream;  // Fs: file stream
  Th: TDecodeThread;  // Th: decoder thread
  Data: TBytes;  // Data: file bytes
  Bmp: TBitmap;  // Bmp: bitmap built from the pixels
  Intf: TLazIntfImage;  // Intf: pixel access object for the bitmap
  T0, Waited: QWord;  // T0: start time, Waited: time spent waiting
  X, Y: Integer;  // X and Y: pixel position
  SrcI: NativeInt;  // SrcI: position in the pixel array
  Col: TFPColor;  // Col: color of one pixel
begin
  Result := False;  // assume failure
  HeicLastError := '';  // clear the last error
  if HeicDisabled then  // decoder was switched off after a hang
  begin
    HeicLastError := 'decoder switched off after an earlier decode was given up';  // tell the caller why
    Exit;  // stop
  end;
  if HeicBusy then  // another decode is still running
  begin
    HeicLastError := 'decoder busy';  // tell the caller why
    Exit;  // stop
  end;
  try
    Fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file for reading
    try
      Data := nil;  // start with a fresh array
      SetLength(Data, Fs.Size);  // room for the whole file
      if Length(Data) > 0 then Fs.ReadBuffer(Data[0], Length(Data));  // read it
    finally
      Fs.Free;  // close the file
    end;
  except
    on E: Exception do
    begin
      HeicLastError := 'cannot read the file: ' + E.Message;  // report the read error
      Exit;  // stop
    end;
  end;
  Th := TDecodeThread.Create(True, 32 * 1024 * 1024);  // create the thread suspended with a large stack
  Th.FreeOnTerminate := False;  // the caller frees it
  Th.Data := Data;  // give it the file bytes
  Th.MaxSide := MaxSide;  // give it the size limit
  HeicBusy := True;  // mark the decoder as busy
  // thumbnails: sample the color conversion down and skip the AV1 post-filters
  if Fast and (MaxSide > 0) then  // thumbnails only need a coarse color conversion
  begin
    HeifTargetSide := MaxSide;  // decoder option: target size
    Av1SkipFilters := True;  // decoder option: skip the AV1 post-filters
  end;
  Th.Start;  // start decoding
  T0 := GetTickCount64;  // remember the start time
  while not Th.Finished do  // wait while the thread works
  begin
    if HeicPump then Application.ProcessMessages;  // keep the screen alive if a progress window is open
    Sleep(5);  // short pause
    Waited := GetTickCount64 - T0;  // time spent so far
    if ((Waited > HeicSoftLimitMs) and HeicCancel) or (Waited > HeicHardLimitMs) then  // Cancel pressed after the soft limit, or the hard limit reached
    begin
      // give up: the thread is left to finish (or not) on its own and is never freed
      HeicDisabled := True;  // switch the decoder off for this session
      HeicBusy := False;  // no longer busy
      HeicLastError := Format('decode given up after %d s (cancelled or too slow)', [Waited div 1000]);  // explain why it stopped
      Exit;  // abandon the thread
    end;
  end;
  HeicBusy := False;  // decoding finished
  HeifTargetSide := 0;  // reset the decoder option
  Av1SkipFilters := False;  // reset the decoder option
  try
  try
    if Th.Err <> '' then  // the thread reported an error
    begin
      HeicLastError := Th.Err;  // pass the error on
      Exit;  // stop
    end;
    if (Th.W <= 0) or (Th.H <= 0) or (Length(Th.Pixels) < NativeInt(Th.W) * Th.H * 4) then  // check that real pixels came back
    begin
      HeicLastError := 'decoder returned an empty picture';  // explain the failure
      Exit;  // stop
    end;
    Bmp := TBitmap.Create;  // bitmap for the picture
    try
      Bmp.PixelFormat := pf32bit;  // 32 bits per pixel
      Bmp.SetSize(Th.W, Th.H);  // size of the decoded picture
      Intf := Bmp.CreateIntfImage;  // pixel access object
      try
        SrcI := 0;  // start at the first pixel
        for Y := 0 to Th.H - 1 do  // every row
          for X := 0 to Th.W - 1 do  // every pixel
          begin
            Col.Red := Th.Pixels[SrcI] * 257;  // red, scaled from 8 to 16 bits
            Col.Green := Th.Pixels[SrcI + 1] * 257;  // green
            Col.Blue := Th.Pixels[SrcI + 2] * 257;  // blue
            Col.Alpha := 65535;  // fully opaque
            Intf.Colors[X, Y] := Col;  // store the pixel
            Inc(SrcI, 4);  // next source pixel (4 bytes)
          end;
        Bmp.LoadFromIntfImage(Intf);  // move the pixels into the bitmap
      finally
        Intf.Free;  // free the pixel access object
      end;
      Pic.Assign(Bmp);  // hand the bitmap to the picture
    finally
      Bmp.Free;  // free the bitmap
    end;
    Result := (Pic.Graphic <> nil) and (not Pic.Graphic.Empty);  // success if the picture has content
    if not Result then HeicLastError := 'could not build the picture';  // explain the failure
  except
    on E: Exception do
    begin
      Result := False;  // failure
      HeicLastError := E.ClassName + ': ' + E.Message;  // keep the error text
    end;
  end;
  finally
    Th.Free;  // free the thread (it has finished)
  end;
end;

{ Decodes a HEIC/AVIF file for the viewer, reduced to at most Target pixels on its long side. }
function LoadHeicMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
var
  Pic: TPicture;  // Pic: decoded picture
  Bmp: TBitmap;  // Bmp: reduced bitmap
  Intf: TLazIntfImage;  // Intf: pixel access object
  W, H, NW, NH, X, Y: Integer;  // W and H: decoded size, NW and NH: new size, X and Y: pixel position
  Sc: Double;  // Sc: reduction scale
  Info: TExifInfo;  // Info: EXIF data
  Ori: Integer;  // Ori: orientation still to apply
begin
  Result := nil;  // assume failure
  Bmp := nil;  // nothing created yet
  Intf := nil;  // nothing created yet
  Pic := TPicture.Create;  // picture object for the decoder
  try
    try
      if not LoadHeicPicture(FileName, Pic, Target) then Exit;  // decode the file
      W := Pic.Width;  // decoded width
      H := Pic.Height;  // decoded height
      if (W <= 0) or (H <= 0) then Exit;  // empty picture: give up
      Sc := 1;  // no reduction by default
      if (Target > 0) and (Max(W, H) > Target) then Sc := Target / Max(W, H);  // reduce only when larger than Target
      NW := Max(1, Round(W * Sc));  // new width
      NH := Max(1, Round(H * Sc));  // new height
      Bmp := TBitmap.Create;  // bitmap at the new size
      Bmp.SetSize(NW, NH);  // set its size
      Bmp.Canvas.StretchDraw(Rect(0, 0, NW, NH), Pic.Graphic);  // draw the picture scaled
      Intf := Bmp.CreateIntfImage;  // pixel access object
      Result := TFPMemoryImage.Create(NW, NH);  // memory image for the viewer
      for Y := 0 to NH - 1 do  // every row
        for X := 0 to NW - 1 do  // every pixel
          Result.Colors[X, Y] := Intf.Colors[X, Y];  // copy the pixel color
      Ori := 0;  // no extra turn by default
      if ReadExifFromFile(FileName, Info) then Ori := HeicExtraOrientation(FileName, W, H, Info.Orientation);  // read the EXIF orientation of the file
      if Ori > 1 then OrientMemImage(Result, Ori);  // apply the turn the decoder missed
    except
      FreeAndNil(Result);  // on error return nothing
    end;
  finally
    Intf.Free;  // free the pixel access object
    Bmp.Free;  // free the bitmap
    Pic.Free;  // free the picture
  end;
end;

end.
