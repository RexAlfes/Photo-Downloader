unit uHeic;

{$mode objfpc}{$H+}

{ HEIC / HEIF pictures.

  Decoded by the Xelitan HEIC decoder (HeicImageX, bundled in third_party/XelHeic). It is
  pure Pascal: no DLLs or other files are needed. See THIRD_PARTY_NOTICES.md. }

interface

uses
  Classes, SysUtils, Graphics, FPImage;

const
  HeicExts = ';.heic;.heif;.avif;';

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
  { The decode runs in its own thread so the window stays alive and can be cancelled }
  TDecodeThread = class(TThread)
  public
    Data, Pixels: TBytes;
    MaxSide, W, H: Integer;
    Err: string;
    procedure Execute; override;
  end;

var
  HeicBusy: Boolean = False;

{ Box-filter reduction of packed RGBA so that the long side is at most MaxSide }
procedure ShrinkRgba(var P: TBytes; var W, H: Integer; MaxSide: Integer);
var
  F, NW, NH, X, Y, DX, DY, C: Integer;
  S: array[0..3] of Cardinal;
  Q: TBytes;
  Src, Dst: NativeInt;
begin
  if (MaxSide <= 0) or (Max(W, H) <= MaxSide * 3 div 2) then Exit;
  F := Max(W, H) div MaxSide;
  if F < 2 then Exit;
  NW := W div F;
  NH := H div F;
  if (NW < 1) or (NH < 1) then Exit;
  Q := nil;
  SetLength(Q, NativeInt(NW) * NH * 4);
  for Y := 0 to NH - 1 do
    for X := 0 to NW - 1 do
    begin
      for C := 0 to 3 do S[C] := 0;
      for DY := 0 to F - 1 do
      begin
        Src := (NativeInt(Y * F + DY) * W + X * F) * 4;
        for DX := 0 to F - 1 do
        begin
          for C := 0 to 3 do Inc(S[C], P[Src + C]);
          Inc(Src, 4);
        end;
      end;
      Dst := (NativeInt(Y) * NW + X) * 4;
      for C := 0 to 3 do Q[Dst + C] := S[C] div Cardinal(F * F);
    end;
  P := Q;
  W := NW;
  H := NH;
end;

procedure TDecodeThread.Execute;
var
  K: Integer;
begin
  try
    Pixels := DecodeHeic(Data, W, H);
    Data := nil;
    ShrinkRgba(Pixels, W, H, MaxSide);
  except
    on E: Exception do
    begin
      Pixels := nil;
      Err := E.ClassName + ': ' + E.Message + ' at ' + BackTraceStrFunc(ExceptAddr);
      for K := 0 to ExceptFrameCount - 1 do
        Err := Err + ' < ' + BackTraceStrFunc(ExceptFrames[K]);
    end;
  end;
end;

function HeicEnabled: Boolean;
begin
  Result := True;
end;

function HeicExtraOrientation(const FileName: string; DecW, DecH, Orient: Integer): Integer;
var
  SW, SH: Integer;
begin
  Result := 0;
  if not (Orient in [5, 6, 7, 8]) then Exit;
  if not ReadHeifStoredSize(FileName, SW, SH) then Exit;
  if SW = SH then Exit;
  if (DecW > DecH) = (SW > SH) then Result := Orient;   // still in the stored shape
end;

function LoadHeicPicture(const FileName: string; Pic: TPicture; MaxSide: Integer; Fast: Boolean): Boolean;
var
  Fs: TFileStream;
  Th: TDecodeThread;
  Data: TBytes;
  Bmp: TBitmap;
  Intf: TLazIntfImage;
  T0, Waited: QWord;
  X, Y: Integer;
  SrcI: NativeInt;
  Col: TFPColor;
begin
  Result := False;
  HeicLastError := '';
  if HeicDisabled then
  begin
    HeicLastError := 'decoder switched off after an earlier decode was given up';
    Exit;
  end;
  if HeicBusy then
  begin
    HeicLastError := 'decoder busy';
    Exit;
  end;
  try
    Fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Data := nil;
      SetLength(Data, Fs.Size);
      if Length(Data) > 0 then Fs.ReadBuffer(Data[0], Length(Data));
    finally
      Fs.Free;
    end;
  except
    on E: Exception do
    begin
      HeicLastError := 'cannot read the file: ' + E.Message;
      Exit;
    end;
  end;
  Th := TDecodeThread.Create(True, 32 * 1024 * 1024);
  Th.FreeOnTerminate := False;
  Th.Data := Data;
  Th.MaxSide := MaxSide;
  HeicBusy := True;
  // thumbnails: sample the colour conversion down and skip the AV1 post-filters
  if Fast and (MaxSide > 0) then
  begin
    HeifTargetSide := MaxSide;
    Av1SkipFilters := True;
  end;
  Th.Start;
  T0 := GetTickCount64;
  while not Th.Finished do
  begin
    if HeicPump then Application.ProcessMessages;
    Sleep(5);
    Waited := GetTickCount64 - T0;
    if ((Waited > HeicSoftLimitMs) and HeicCancel) or (Waited > HeicHardLimitMs) then
    begin
      // give up: the thread is left to finish (or not) on its own and is never freed
      HeicDisabled := True;
      HeicBusy := False;
      HeicLastError := Format('decode given up after %d s (cancelled or too slow)', [Waited div 1000]);
      Exit;
    end;
  end;
  HeicBusy := False;
  HeifTargetSide := 0;
  Av1SkipFilters := False;
  try
  try
    if Th.Err <> '' then
    begin
      HeicLastError := Th.Err;
      Exit;
    end;
    if (Th.W <= 0) or (Th.H <= 0) or (Length(Th.Pixels) < NativeInt(Th.W) * Th.H * 4) then
    begin
      HeicLastError := 'decoder returned an empty picture';
      Exit;
    end;
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Th.W, Th.H);
      Intf := Bmp.CreateIntfImage;
      try
        SrcI := 0;
        for Y := 0 to Th.H - 1 do
          for X := 0 to Th.W - 1 do
          begin
            Col.Red := Th.Pixels[SrcI] * 257;
            Col.Green := Th.Pixels[SrcI + 1] * 257;
            Col.Blue := Th.Pixels[SrcI + 2] * 257;
            Col.Alpha := 65535;
            Intf.Colors[X, Y] := Col;
            Inc(SrcI, 4);
          end;
        Bmp.LoadFromIntfImage(Intf);
      finally
        Intf.Free;
      end;
      Pic.Assign(Bmp);
    finally
      Bmp.Free;
    end;
    Result := (Pic.Graphic <> nil) and (not Pic.Graphic.Empty);
    if not Result then HeicLastError := 'could not build the picture';
  except
    on E: Exception do
    begin
      Result := False;
      HeicLastError := E.ClassName + ': ' + E.Message;
    end;
  end;
  finally
    Th.Free;
  end;
end;

function LoadHeicMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
var
  Pic: TPicture;
  Bmp: TBitmap;
  Intf: TLazIntfImage;
  W, H, NW, NH, X, Y: Integer;
  Sc: Double;
  Info: TExifInfo;
  Ori: Integer;
begin
  Result := nil;
  Bmp := nil;
  Intf := nil;
  Pic := TPicture.Create;
  try
    try
      if not LoadHeicPicture(FileName, Pic, Target) then Exit;
      W := Pic.Width;
      H := Pic.Height;
      if (W <= 0) or (H <= 0) then Exit;
      Sc := 1;
      if (Target > 0) and (Max(W, H) > Target) then Sc := Target / Max(W, H);
      NW := Max(1, Round(W * Sc));
      NH := Max(1, Round(H * Sc));
      Bmp := TBitmap.Create;
      Bmp.SetSize(NW, NH);
      Bmp.Canvas.StretchDraw(Rect(0, 0, NW, NH), Pic.Graphic);
      Intf := Bmp.CreateIntfImage;
      Result := TFPMemoryImage.Create(NW, NH);
      for Y := 0 to NH - 1 do
        for X := 0 to NW - 1 do
          Result.Colors[X, Y] := Intf.Colors[X, Y];
      Ori := 0;
      if ReadExifFromFile(FileName, Info) then Ori := HeicExtraOrientation(FileName, W, H, Info.Orientation);
      if Ori > 1 then OrientMemImage(Result, Ori);
    except
      FreeAndNil(Result);
    end;
  finally
    Intf.Free;
    Bmp.Free;
    Pic.Free;
  end;
end;

end.
