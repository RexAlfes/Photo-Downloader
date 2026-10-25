unit uScale;

{$mode objfpc}{$H+}

{ Smooth image scaling for the viewer. Pictures are decoded at no less than the size
  needed on screen, then averaged (shrinking) or interpolated (enlarging) into a
  24-bit BMP, so they are neither blocky nor aliased. }

interface

uses
  Classes, SysUtils, Math, FPImage, FPReadJPEG, FPReadPNG, FPReadBMP, uExif, uRotate;

type
  TPicKind = (pkJpeg, pkPng, pkBmp);

{ Decodes the picture in S (positioned at its start). For JPEG with known SrcW/SrcH the
  decoder shrinks the picture by 2, 4 or 8 while it is still at least Target pixels on
  its long side. Returns nil if the picture cannot be read. }
function LoadMemImage(S: TStream; Kind: TPicKind; SrcW, SrcH, Target: Integer): TFPMemoryImage;
{ Reads the uncompressed image of a TIFF/DNG file, averaged down to about Target pixels. }
function LoadTiffMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
{ Turns a picture upright for an EXIF orientation of 2..8; Img is replaced by the new picture. }
procedure OrientMemImage(var Img: TFPMemoryImage; Orient: Integer);
{ Scales Src to NW x NH and writes it to Ms as a 24-bit BMP file. }
function SmoothScaleToBmp(Src: TFPCustomImage; NW, NH: Integer; Ms: TMemoryStream): Boolean;

implementation

type
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

function LoadMemImage(S: TStream; Kind: TPicKind; SrcW, SrcH, Target: Integer): TFPMemoryImage;
var
  Img: TFPMemoryImage;
  JR: TFPReaderJPEG;
  PR: TFPReaderPNG;
  BR: TFPReaderBMP;
  Ratio: Integer;
begin
  Result := nil;
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      case Kind of
        pkJpeg:
          begin
            JR := TFPReaderJPEG.Create;
            try
              Ratio := Max(SrcW, SrcH) div Max(1, Target);
              if Ratio >= 8 then JR.Scale := jsEighth
              else if Ratio >= 4 then JR.Scale := jsQuarter
              else if Ratio >= 2 then JR.Scale := jsHalf
              else JR.Scale := jsFullSize;
              Img.LoadFromStream(S, JR);
            finally
              JR.Free;
            end;
          end;
        pkPng:
          begin
            PR := TFPReaderPNG.Create;
            try
              Img.LoadFromStream(S, PR);
            finally
              PR.Free;
            end;
          end;
      else
        BR := TFPReaderBMP.Create;
        try
          Img.LoadFromStream(S, BR);
        finally
          BR.Free;
        end;
      end;
      if (Img.Width > 0) and (Img.Height > 0) then
      begin
        Result := Img;
        Img := nil;
      end;
    except
      Result := nil;
    end;
  finally
    Img.Free;
  end;
end;

function LoadTiffMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
var
  R: TTiffRgb;
  Strm: TFileStream;
  Img: TFPMemoryImage;
  K, OW, OH, OX, OY, J, I, SY, SX, P, Bps, Hi, N: Integer;
  Row: TBytes;
  Sum: array of Int64;
  C: TFPColor;
  G: Byte;
begin
  Result := nil;
  Row := nil;
  Sum := nil;
  Img := nil;
  if not FindTiffRgb(FileName, R) then Exit;
  Bps := R.Bits div 8;
  if R.Big then Hi := 0 else Hi := Bps - 1;
  K := Max(1, Max(R.W, R.H) div Max(1, Target));
  OW := Max(1, R.W div K);
  OH := Max(1, R.H div K);
  try
    try
      Img := TFPMemoryImage.Create(OW, OH);
      Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        SetLength(Sum, OW * 3);
        N := K * K;
        for OY := 0 to OH - 1 do
        begin
          for I := 0 to High(Sum) do Sum[I] := 0;
          for J := 0 to K - 1 do
          begin
            SY := Min(R.H - 1, OY * K + J);
            if not ReadTiffRgbRow(Strm, R, SY, Row) then Exit;
            for OX := 0 to OW - 1 do
              for I := 0 to K - 1 do
              begin
                SX := OX * K + I;
                P := SX * R.Spp * Bps + Hi;
                if R.Spp = 3 then
                begin
                  Inc(Sum[OX * 3], Row[P]);
                  Inc(Sum[OX * 3 + 1], Row[P + Bps]);
                  Inc(Sum[OX * 3 + 2], Row[P + 2 * Bps]);
                end
                else
                begin
                  G := Row[P];
                  if R.Photo = 0 then G := 255 - G;     // WhiteIsZero
                  Inc(Sum[OX * 3], G);
                  Inc(Sum[OX * 3 + 1], G);
                  Inc(Sum[OX * 3 + 2], G);
                end;
              end;
          end;
          for OX := 0 to OW - 1 do
          begin
            C.Red := Word((Sum[OX * 3] div N) * 257);
            C.Green := Word((Sum[OX * 3 + 1] div N) * 257);
            C.Blue := Word((Sum[OX * 3 + 2] div N) * 257);
            C.Alpha := $FFFF;
            Img.Colors[OX, OY] := C;
          end;
        end;
      finally
        Strm.Free;
      end;
      Result := Img;
      Img := nil;
    except
      Result := nil;
    end;
  finally
    Img.Free;
  end;
end;

procedure OrientMemImage(var Img: TFPMemoryImage; Orient: Integer);
var
  Nw, Nh, X, Y, NX, NY: Integer;
  Res: TFPMemoryImage;
begin
  if (Img = nil) or (Orient < 2) or (Orient > 8) then Exit;
  OrientDims(Orient, Img.Width, Img.Height, Nw, Nh);
  Res := TFPMemoryImage.Create(Nw, Nh);
  try
    for Y := 0 to Img.Height - 1 do
      for X := 0 to Img.Width - 1 do
      begin
        OrientPoint(Orient, Img.Width, Img.Height, X, Y, NX, NY);
        Res.Colors[NX, NY] := Img.Colors[X, Y];
      end;
  except
    Res.Free;
    Exit;
  end;
  Img.Free;
  Img := Res;
end;

function SmoothScaleToBmp(Src: TFPCustomImage; NW, NH: Integer; Ms: TMemoryStream): Boolean;
var
  SW, SH, LineLen, X, Y, Y0, Y1, XX, YY, N, V: Integer;
  SX, SY, FX, FY, TY: Double;
  XA, XB: array of Integer;
  XT: array of Double;
  Line: TBytes;
  FH: TBmpFileHdr;
  IH: TBmpInfoHdr;
  C00, C10, C01, C11: TFPColor;
  SR, SG, SB: Int64;
  Down: Boolean;

  function Mix(P00, P10, P01, P11: Word; TX: Double): Byte;
  var
    Vv: Double;
  begin
    Vv := ((P00 * (1 - TX) + P10 * TX) * (1 - TY) + (P01 * (1 - TX) + P11 * TX) * TY) / 257;
    if Vv < 0 then Vv := 0;
    if Vv > 255 then Vv := 255;
    Result := Byte(Round(Vv));
  end;

begin
  Result := False;
  SW := Src.Width;
  SH := Src.Height;
  if (SW < 1) or (SH < 1) or (NW < 1) or (NH < 1) then Exit;
  SX := SW / NW;
  SY := SH / NH;
  Down := (SX > 1) or (SY > 1);
  XA := nil;
  XB := nil;
  XT := nil;
  Line := nil;
  SetLength(XA, NW);
  SetLength(XB, NW);
  SetLength(XT, NW);
  for X := 0 to NW - 1 do
    if Down then
    begin
      XA[X] := Min(SW - 1, Trunc(X * SX));
      XB[X] := Min(SW, Max(XA[X] + 1, Ceil((X + 1) * SX)));   // exclusive end
      XT[X] := 0;
    end
    else
    begin
      FX := (X + 0.5) * SX - 0.5;
      if FX < 0 then FX := 0;
      XA[X] := Min(SW - 1, Trunc(FX));
      XB[X] := Min(SW - 1, XA[X] + 1);
      XT[X] := FX - XA[X];
    end;

  LineLen := ((NW * 3 + 3) div 4) * 4;
  SetLength(Line, LineLen);
  for X := 0 to LineLen - 1 do Line[X] := 0;

  FH.bfType := $4D42;
  FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;
  FH.bfReserved := 0;
  FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
  IH.biSize := SizeOf(IH);
  IH.biWidth := NW;
  IH.biHeight := NH;                     // positive: rows are stored bottom-up
  IH.biPlanes := 1;
  IH.biBitCount := 24;
  IH.biCompression := 0;
  IH.biSizeImage := LineLen * NH;
  IH.biXPels := 2835;
  IH.biYPels := 2835;
  IH.biClrUsed := 0;
  IH.biClrImportant := 0;
  Ms.WriteBuffer(FH, SizeOf(FH));
  Ms.WriteBuffer(IH, SizeOf(IH));

  TY := 0;
  for Y := NH - 1 downto 0 do
  begin
    if Down then
    begin
      Y0 := Min(SH - 1, Trunc(Y * SY));
      Y1 := Min(SH, Max(Y0 + 1, Ceil((Y + 1) * SY)));
    end
    else
    begin
      FY := (Y + 0.5) * SY - 0.5;
      if FY < 0 then FY := 0;
      Y0 := Min(SH - 1, Trunc(FY));
      Y1 := Min(SH - 1, Y0 + 1);
      TY := FY - Y0;
    end;
    for X := 0 to NW - 1 do
    begin
      if Down then
      begin
        SR := 0;
        SG := 0;
        SB := 0;
        N := 0;
        for YY := Y0 to Y1 - 1 do
          for XX := XA[X] to XB[X] - 1 do
          begin
            C00 := Src.Colors[XX, YY];
            Inc(SR, C00.Red);
            Inc(SG, C00.Green);
            Inc(SB, C00.Blue);
            Inc(N);
          end;
        if N < 1 then N := 1;
        V := Integer((SR div N) shr 8);
        Line[X * 3 + 2] := Byte(V);
        V := Integer((SG div N) shr 8);
        Line[X * 3 + 1] := Byte(V);
        V := Integer((SB div N) shr 8);
        Line[X * 3] := Byte(V);
      end
      else
      begin
        C00 := Src.Colors[XA[X], Y0];
        C10 := Src.Colors[XB[X], Y0];
        C01 := Src.Colors[XA[X], Y1];
        C11 := Src.Colors[XB[X], Y1];
        Line[X * 3 + 2] := Mix(C00.Red, C10.Red, C01.Red, C11.Red, XT[X]);
        Line[X * 3 + 1] := Mix(C00.Green, C10.Green, C01.Green, C11.Green, XT[X]);
        Line[X * 3] := Mix(C00.Blue, C10.Blue, C01.Blue, C11.Blue, XT[X]);
      end;
    end;
    Ms.WriteBuffer(Line[0], LineLen);
  end;
  Result := True;
end;

end.
