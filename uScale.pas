unit uScale;

{$mode objfpc}{$H+}

{ Smooth image scaling for the viewer. Pictures are decoded at no less than the size
  needed on screen, then averaged (shrinking) or interpolated (enlarging) into a
  24-bit BMP, so they are neither blocky nor aliased. }

interface

uses
  Classes, SysUtils, Math, FPImage, FPReadJPEG, FPReadPNG, FPReadBMP, FPReadGif, uExif, uRotate, uTiffRead, uPngFix;

type
  TPicKind = (pkJpeg, pkPng, pkBmp, pkGif);  // kinds of picture file the reader can decode

{ Decodes the picture in S (positioned at its start). For JPEG with known SrcW/SrcH the
  decoder shrinks the picture by 2, 4 or 8 while it is still at least Target pixels on
  its long side. Returns nil if the picture cannot be read. }
function LoadMemImage(S: TStream; Kind: TPicKind; SrcW, SrcH, Target: Integer): TFPMemoryImage;
{ The reason the last LoadMemImage call failed (empty after a success) }
function LoadMemImageError: string;
{ Reads the uncompressed image of a TIFF/DNG file, averaged down to about Target pixels. }
function LoadTiffMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
{ Turns a picture upright for an EXIF orientation of 2..8; Img is replaced by the new picture. }
procedure OrientMemImage(var Img: TFPMemoryImage; Orient: Integer);
{ Scales Src to NW x NH and writes it to Ms as a 24-bit BMP file. }
function SmoothScaleToBmp(Src: TFPCustomImage; NW, NH: Integer; Ms: TMemoryStream): Boolean;

implementation

type
  { BMP file header (14 bytes), used to build a BMP in memory. }
  TBmpFileHdr = packed record
    bfType: Word;
    bfSize, bfReserved, bfOffBits: LongWord;
  end;
  { BMP info header (40 bytes), used to build a BMP in memory. }
  TBmpInfoHdr = packed record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPels, biYPels: LongInt;
    biClrUsed, biClrImportant: LongWord;
  end;

var
  GLastError: string = '';  // text of the last decoding error

{ Returns the reason the last LoadMemImage call failed. }
function LoadMemImageError: string;
begin
  Result := GLastError;  // the saved error text
end;

{ Decodes a JPEG, PNG, BMP or GIF stream into a memory image; JPEGs are shrunk while decoding when the target is much smaller. }
function LoadMemImage(S: TStream; Kind: TPicKind; SrcW, SrcH, Target: Integer): TFPMemoryImage;
var
  Img: TFPMemoryImage;  // Img: picture being filled
  JR: TFPReaderJPEG;  // JR: JPEG reader
  PR: TFPReaderPNG;  // PR: PNG reader
  BR: TFPReaderBMP;  // BR: BMP reader
  GR: TFPReaderGif;  // GR: GIF reader
  Ratio: Integer;  // Ratio: how much larger the picture is than Target
  StartPos: Int64;  // StartPos: where the picture starts in the stream
  Fix: TMemoryStream;  // Fix: copy of a PNG with repaired checksums
  Retry: Boolean;  // Retry: True when the first PNG attempt failed
  FirstErr: string;  // FirstErr: text of that first error
begin
  Result := nil;  // assume failure
  GLastError := '';  // clear the last error
  Img := TFPMemoryImage.Create(0, 0);  // empty picture to fill
  try
    try
      case Kind of
        pkJpeg:  // JPEG
          begin
            JR := TFPReaderJPEG.Create;  // JPEG reader
            try
              Ratio := Max(SrcW, SrcH) div Max(1, Target);  // how many times larger than needed
              if Ratio >= 8 then JR.Scale := jsEighth  // 8 or more: decode at 1/8 size
              else if Ratio >= 4 then JR.Scale := jsQuarter  // 4 or more: decode at 1/4 size
              else if Ratio >= 2 then JR.Scale := jsHalf  // 2 or more: decode at half size
              else JR.Scale := jsFullSize;  // otherwise full size
              Img.LoadFromStream(S, JR);  // decode into the picture
            finally
              JR.Free;  // free the reader
            end;
          end;
        pkPng:
          begin  // PNG
            StartPos := S.Position;  // remember the start for a second try
            PR := TFPReaderPNG.Create;  // PNG reader
            try
              Retry := False;  // no retry yet
              FirstErr := '';  // no error yet
              try
                Img.LoadFromStream(S, PR);  // decode into the picture
              except
                on E: Exception do
                begin
                  Retry := True;  // remember to retry
                  FirstErr := E.ClassName + ' ' + E.Message;  // keep the error text
                end;
              end;
              if Retry then  // first try failed
              begin
                // wrong chunk checksums (oscilloscopes and some tools write them): repair and retry
                Fix := TMemoryStream.Create;  // copy for the repair
                try
                  S.Position := StartPos;  // go back to the start of the picture
                  Fix.CopyFrom(S, S.Size - StartPos);  // copy the whole PNG to memory
                  if not RepairPngCrc(Fix) then raise Exception.Create(FirstErr);  // repair the checksums; if none were wrong the first error was real
                  Fix.Position := 0;  // rewind
                  FreeAndNil(PR);  // discard the used reader
                  PR := TFPReaderPNG.Create;  // new reader
                  Img.LoadFromStream(Fix, PR);  // decode the repaired copy
                finally
                  Fix.Free;  // free the copy
                end;
              end;
            finally
              PR.Free;  // free the reader
            end;
          end;
        pkGif:
          begin  // GIF (first frame)
            GR := TFPReaderGif.Create;  // GIF reader
            try
              Img.LoadFromStream(S, GR);  // decode into the picture
            finally
              GR.Free;  // free the reader
            end;
          end;
      else
        BR := TFPReaderBMP.Create;  // BMP reader
        try
          Img.LoadFromStream(S, BR);  // decode into the picture
        finally
          BR.Free;  // free the reader
        end;
      end;
      if (Img.Width > 0) and (Img.Height > 0) then  // the decoder produced something
      begin
        Result := Img;  // return the picture
        Img := nil;  // the caller owns it now
      end
      else
        GLastError := 'the decoder returned an empty picture';  // explain the failure
    except
      on E: Exception do
      begin
        GLastError := E.ClassName + ' ' + E.Message;  // keep the error text
        Result := nil;  // no picture
      end;
    end;
  finally
    Img.Free;  // free the picture if it was not returned
  end;
end;

{ Reads an uncompressed TIFF or DNG image row by row, averaging blocks down to about Target pixels. }
function LoadTiffMemImage(const FileName: string; Target: Integer): TFPMemoryImage;
var
  R: TTiffRgb;  // R: TIFF description (size, sample layout)
  Strm: TFileStream;  // Strm: the file
  Img: TFPMemoryImage;  // Img: picture being built
  K, OW, OH, OX, OY, J, I, SY, SX, P, Bps, Hi, N: Integer;  // K: block size, OW and OH: output size, OX and OY: output pixel, J and I: offsets in a block, SY and SX: source pixel, P: byte position, Bps: bytes per sample, Hi: byte holding the high part of a sample, N: pixels per block
  Row: TBytes;  // Row: one row of file data
  Sum: array of Int64;  // Sum: running color sums for one output row
  C: TFPColor;  // C: color of one output pixel
  G: Byte;  // G: gray value
  ErrText: string;  // ErrText: reason from the general reader (not used)
begin
  Result := nil;  // assume failure
  Row := nil;  // no row yet
  Sum := nil;  // no sums yet
  Img := nil;  // no picture yet
  if not FindTiffRgb(FileName, R) then  // layout not handled by the simple reader
  begin
    // compressed, 1-bit, palette ...: the general TIFF reader
    Result := LoadTiffMemImageAny(FileName, Target, ErrText);  // use the general TIFF reader
    Exit;  // done
  end;
  Bps := R.Bits div 8;  // bytes per sample
  if R.Big then Hi := 0 else Hi := Bps - 1;  // which byte of a sample is the most significant
  K := Max(1, Max(R.W, R.H) div Max(1, Target));  // block size needed to get close to Target
  OW := Max(1, R.W div K);  // output width
  OH := Max(1, R.H div K);  // output height
  try
    try
      Img := TFPMemoryImage.Create(OW, OH);  // picture to fill
      Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
      try
        SetLength(Sum, OW * 3);  // three sums (red, green, blue) per output pixel
        N := K * K;  // pixels per block
        for OY := 0 to OH - 1 do  // every output row
        begin
          for I := 0 to High(Sum) do Sum[I] := 0;  // clear the sums
          for J := 0 to K - 1 do  // rows of the block
          begin
            SY := Min(R.H - 1, OY * K + J);  // source row, kept inside the picture
            if not ReadTiffRgbRow(Strm, R, SY, Row) then Exit;  // read it; stop if it cannot be read
            for OX := 0 to OW - 1 do  // every output pixel
              for I := 0 to K - 1 do  // pixels of the block row
              begin
                SX := OX * K + I;  // source pixel column
                P := SX * R.Spp * Bps + Hi;  // byte position of that pixel
                if R.Spp = 3 then  // color picture
                begin
                  Inc(Sum[OX * 3], Row[P]);  // add red
                  Inc(Sum[OX * 3 + 1], Row[P + Bps]);  // add green
                  Inc(Sum[OX * 3 + 2], Row[P + 2 * Bps]);  // add blue
                end
                else
                begin
                  G := Row[P];  // gray value of the pixel
                  if R.Photo = 0 then G := 255 - G;     // WhiteIsZero
                  Inc(Sum[OX * 3], G);  // add to red
                  Inc(Sum[OX * 3 + 1], G);  // add to green
                  Inc(Sum[OX * 3 + 2], G);  // add to blue
                end;
              end;
          end;
          for OX := 0 to OW - 1 do  // every output pixel
          begin
            C.Red := Word((Sum[OX * 3] div N) * 257);  // average red, scaled to 16 bits
            C.Green := Word((Sum[OX * 3 + 1] div N) * 257);  // average green
            C.Blue := Word((Sum[OX * 3 + 2] div N) * 257);  // average blue
            C.Alpha := $FFFF;  // fully opaque
            Img.Colors[OX, OY] := C;  // store the pixel
          end;
        end;
      finally
        Strm.Free;  // close the file
      end;
      Result := Img;  // return the picture
      Img := nil;  // the caller owns it now
    except
      Result := nil;  // any error: no picture
    end;
  finally
    Img.Free;  // free the picture if it was not returned
  end;
end;

{ Turns the picture upright for EXIF orientation 2 to 8 and replaces Img with the result. }
procedure OrientMemImage(var Img: TFPMemoryImage; Orient: Integer);
var
  Nw, Nh, X, Y, NX, NY: Integer;  // Nw and Nh: new size, X and Y: old pixel, NX and NY: new pixel
  Res: TFPMemoryImage;  // Res: the turned picture
begin
  if (Img = nil) or (Orient < 2) or (Orient > 8) then Exit;  // nothing to do for normal or invalid values
  OrientDims(Orient, Img.Width, Img.Height, Nw, Nh);  // new size (swapped for quarter turns)
  Res := TFPMemoryImage.Create(Nw, Nh);  // empty picture of that size
  try
    for Y := 0 to Img.Height - 1 do  // every row
      for X := 0 to Img.Width - 1 do  // every pixel
      begin
        OrientPoint(Orient, Img.Width, Img.Height, X, Y, NX, NY);  // where this pixel goes
        Res.Colors[NX, NY] := Img.Colors[X, Y];  // copy the color
      end;
  except
    Res.Free;  // free the new picture on error
    Exit;  // leave Img unchanged
  end;
  Img.Free;  // free the old picture
  Img := Res;  // use the turned picture
end;

{ Scales Src to NW x NH and writes it to Ms as a 24-bit BMP; averages when shrinking, interpolates when enlarging. }
function SmoothScaleToBmp(Src: TFPCustomImage; NW, NH: Integer; Ms: TMemoryStream): Boolean;
var
  SW, SH, LineLen, X, Y, Y0, Y1, XX, YY, N, V: Integer;  // SW and SH: source size, LineLen: bytes per BMP row, X and Y: output pixel, Y0 and Y1: source rows, XX and YY: loop positions, N: pixels averaged, V: color value
  SX, SY, FX, FY, TY: Double;  // SX and SY: source pixels per output pixel, FX and FY: exact source position, TY: vertical weight
  XA, XB: array of Integer;  // XA and XB: first and last source column for each output column
  XT: array of Double;  // XT: horizontal weight for each output column
  Line: TBytes;  // Line: one BMP row
  FH: TBmpFileHdr;  // FH: BMP file header
  IH: TBmpInfoHdr;  // IH: BMP info header
  C00, C10, C01, C11: TFPColor;  // C00, C10, C01, C11: the four neighbor colors
  SR, SG, SB: Int64;  // SR, SG, SB: color sums
  Down: Boolean;  // True when the picture is being shrunk

  { Blends four neighbor values with horizontal weight TX and vertical weight TY; result 0..255. }
  function Mix(P00, P10, P01, P11: Word; TX: Double): Byte;
  var
    Vv: Double;  // Vv: blended value
  begin
    Vv := ((P00 * (1 - TX) + P10 * TX) * (1 - TY) + (P01 * (1 - TX) + P11 * TX) * TY) / 257;  // weighted average of the four values, converted from 16 to 8 bits
    if Vv < 0 then Vv := 0;  // not below 0
    if Vv > 255 then Vv := 255;  // not above 255
    Result := Byte(Round(Vv));  // rounded result
  end;

begin
  Result := False;  // assume failure
  SW := Src.Width;  // source width
  SH := Src.Height;  // source height
  if (SW < 1) or (SH < 1) or (NW < 1) or (NH < 1) then Exit;  // nothing to do for empty sizes
  SX := SW / NW;  // source pixels per output pixel, horizontally
  SY := SH / NH;  // source pixels per output pixel, vertically
  Down := (SX > 1) or (SY > 1);  // shrinking in either direction?
  XA := nil;  // no arrays yet
  XB := nil;  // no arrays yet
  XT := nil;  // no arrays yet
  Line := nil;  // no row yet
  SetLength(XA, NW);  // first source column per output column
  SetLength(XB, NW);  // end source column per output column
  SetLength(XT, NW);  // horizontal weights
  for X := 0 to NW - 1 do  // prepare every output column
    if Down then  // shrinking
    begin
      XA[X] := Min(SW - 1, Trunc(X * SX));  // first source column
      XB[X] := Min(SW, Max(XA[X] + 1, Ceil((X + 1) * SX)));   // exclusive end
      XT[X] := 0;  // no weight needed when averaging
    end
    else
    begin
      FX := (X + 0.5) * SX - 0.5;  // exact source position
      if FX < 0 then FX := 0;  // not before the first column
      XA[X] := Min(SW - 1, Trunc(FX));  // left neighbor
      XB[X] := Min(SW - 1, XA[X] + 1);  // right neighbor
      XT[X] := FX - XA[X];  // weight of the right neighbor
    end;

  LineLen := ((NW * 3 + 3) div 4) * 4;  // BMP rows are padded to 4 bytes
  SetLength(Line, LineLen);  // room for one row
  for X := 0 to LineLen - 1 do Line[X] := 0;  // clear the row (including the padding)

  FH.bfType := $4D42;  // file type marker "BM"
  FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;  // total file size
  FH.bfReserved := 0;  // reserved
  FH.bfOffBits := SizeOf(FH) + SizeOf(IH);  // where the pixel data starts
  IH.biSize := SizeOf(IH);  // size of this header
  IH.biWidth := NW;  // width in pixels
  IH.biHeight := NH;                     // positive: rows are stored bottom-up
  IH.biPlanes := 1;  // one plane
  IH.biBitCount := 24;  // 24 bits per pixel
  IH.biCompression := 0;  // no compression
  IH.biSizeImage := LineLen * NH;  // size of the pixel data
  IH.biXPels := 2835;  // horizontal resolution (pixels per meter)
  IH.biYPels := 2835;  // vertical resolution
  IH.biClrUsed := 0;  // all colors used
  IH.biClrImportant := 0;  // all colors important
  Ms.WriteBuffer(FH, SizeOf(FH));  // write the file header
  Ms.WriteBuffer(IH, SizeOf(IH));  // write the info header

  TY := 0;  // no vertical weight yet
  for Y := NH - 1 downto 0 do  // BMP stores the bottom row first
  begin
    if Down then  // shrinking
    begin
      Y0 := Min(SH - 1, Trunc(Y * SY));  // first source row
      Y1 := Min(SH, Max(Y0 + 1, Ceil((Y + 1) * SY)));  // end row, at least one pixel tall
    end
    else
    begin
      FY := (Y + 0.5) * SY - 0.5;  // exact source row
      if FY < 0 then FY := 0;  // not before the first row
      Y0 := Min(SH - 1, Trunc(FY));  // upper neighbor
      Y1 := Min(SH - 1, Y0 + 1);  // lower neighbor
      TY := FY - Y0;  // weight of the lower neighbor
    end;
    for X := 0 to NW - 1 do  // every output column
    begin
      if Down then  // shrinking: average a block
      begin
        SR := 0;  // red sum
        SG := 0;  // green sum
        SB := 0;  // blue sum
        N := 0;  // pixel count
        for YY := Y0 to Y1 - 1 do  // rows of the block
          for XX := XA[X] to XB[X] - 1 do  // columns of the block
          begin
            C00 := Src.Colors[XX, YY];  // source pixel
            Inc(SR, C00.Red);  // add red
            Inc(SG, C00.Green);  // add green
            Inc(SB, C00.Blue);  // add blue
            Inc(N);  // count it
          end;
        if N < 1 then N := 1;  // avoid dividing by zero
        V := Integer((SR div N) shr 8);  // average red, 16 to 8 bits
        Line[X * 3 + 2] := Byte(V);  // BMP stores blue, green, red
        V := Integer((SG div N) shr 8);  // average green
        Line[X * 3 + 1] := Byte(V);  // green byte
        V := Integer((SB div N) shr 8);  // average blue
        Line[X * 3] := Byte(V);  // blue byte
      end
      else
      begin
        C00 := Src.Colors[XA[X], Y0];  // enlarging: upper left neighbor
        C10 := Src.Colors[XB[X], Y0];  // upper right neighbor
        C01 := Src.Colors[XA[X], Y1];  // lower left neighbor
        C11 := Src.Colors[XB[X], Y1];  // lower right neighbor
        Line[X * 3 + 2] := Mix(C00.Red, C10.Red, C01.Red, C11.Red, XT[X]);  // blend red
        Line[X * 3 + 1] := Mix(C00.Green, C10.Green, C01.Green, C11.Green, XT[X]);  // blend green
        Line[X * 3] := Mix(C00.Blue, C10.Blue, C01.Blue, C11.Blue, XT[X]);  // blend blue
      end;
    end;
    Ms.WriteBuffer(Line[0], LineLen);  // write the finished row
  end;
  Result := True;  // success
end;

end.
