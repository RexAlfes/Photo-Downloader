unit uTiffRead;

{$mode objfpc}{$H+}
{$POINTERMATH ON}

{ Thumbnails for TIFF files that the plain reader in uItems cannot handle: compressed (LZW,
  PackBits, Deflate, CCITT fax Group 3 / Group 4 and RLE), 1/2/4/8/16-bit grey, palette, RGB and
  CMYK, in strips or tiles. The picture is read strip by strip and averaged down to thumbnail
  size, so large scans need little memory. Not supported: JPEG compression, planar layout,
  floating point samples, BigTIFF. }

interface

uses
  Classes, SysUtils, Graphics, FPImage;

{ The same picture as a memory image (for the viewer), long side at most Target. }
function LoadTiffMemImageAny(const FileName: string; Target: Integer; out Err: string): TFPMemoryImage;
{ Builds a thumbnail with at most MaxSide pixels on its long side. False (with a reason in Err)
  when the file cannot be read. }
function LoadTiffThumb(const FileName: string; MaxSide: Integer; Bmp: TBitmap;
  out Err: string): Boolean;

implementation

uses
  Math, zstream;

const
  WhiteRuns: array[0..103] of Word = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 128, 192, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024, 1088, 1152, 1216, 1280, 1344, 1408, 1472, 1536, 1600, 1664, 1728, 1792, 1856, 1920, 1984, 2048, 2112, 2176, 2240, 2304, 2368, 2432, 2496, 2560);
  WhiteCodes: array[0..103] of Word = (53, 7, 7, 8, 11, 12, 14, 15, 19, 20, 7, 8, 8, 3, 52, 53, 42, 43, 39, 12, 8, 23, 3, 4, 40, 43, 19, 36, 24, 2, 3, 26, 27, 18, 19, 20, 21, 22, 23, 40, 41, 42, 43, 44, 45, 4, 5, 10, 11, 82, 83, 84, 85, 36, 37, 88, 89, 90, 91, 74, 75, 50, 51, 52, 27, 18, 23, 55, 54, 55, 100, 101, 104, 103, 204, 205, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 152, 153, 154, 24, 155, 8, 12, 13, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31);
  WhiteLens: array[0..103] of Byte = (8, 6, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 5, 5, 6, 7, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 9, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12);
  BlackRuns: array[0..103] of Word = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 128, 192, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024, 1088, 1152, 1216, 1280, 1344, 1408, 1472, 1536, 1600, 1664, 1728, 1792, 1856, 1920, 1984, 2048, 2112, 2176, 2240, 2304, 2368, 2432, 2496, 2560);
  BlackCodes: array[0..103] of Word = (55, 2, 3, 2, 3, 3, 2, 3, 5, 4, 4, 5, 7, 4, 7, 24, 23, 24, 8, 103, 104, 108, 55, 40, 23, 24, 202, 203, 204, 205, 104, 105, 106, 107, 210, 211, 212, 213, 214, 215, 108, 109, 218, 219, 84, 85, 86, 87, 100, 101, 82, 83, 36, 55, 56, 39, 40, 88, 89, 43, 44, 90, 102, 103, 15, 200, 201, 91, 51, 52, 53, 108, 109, 74, 75, 76, 77, 114, 115, 116, 117, 118, 119, 82, 83, 84, 85, 90, 91, 100, 101, 8, 12, 13, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31);
  BlackLens: array[0..103] of Byte = (10, 3, 2, 2, 3, 4, 4, 5, 6, 6, 7, 7, 7, 8, 8, 9, 10, 10, 10, 11, 11, 11, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 10, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12);

type
  TInt64Array = array of Int64;
  TIntArray = array of Integer;

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

  TTag = record
    Tag, Typ: Word;
    Cnt: LongWord;
    Raw: array[0..3] of Byte;
  end;

var
  { fax code lookup: [colour 0 = white, 1 = black, code length 2..13][code value] = run + 1 (0 = none) }
  FaxLook: array[0..1, 2..13] of array of SmallInt;
  RevBits: array[0..255] of Byte;

{ ---- fax (CCITT) decoding ---- }

type
  TFaxState = record
    Data: TBytes;
    Len: Integer;          // bytes
    Pos: Integer;          // bit position
    Fail: Boolean;
  end;

function GetB(const S: TFaxState; P: Integer): Cardinal; inline;
begin
  if P < S.Len then Result := S.Data[P] else Result := 0;
end;

function PeekBits(const S: TFaxState; K: Integer): Integer;
var
  P: Integer;
  V: Cardinal;
begin
  P := S.Pos shr 3;
  V := (GetB(S, P) shl 24) or (GetB(S, P + 1) shl 16) or (GetB(S, P + 2) shl 8) or GetB(S, P + 3);
  V := V shl (S.Pos and 7);
  Result := Integer(V shr (32 - K));
end;

function FaxEof(const S: TFaxState): Boolean; inline;
begin
  Result := S.Pos >= S.Len * 8;
end;

{ one run length (terminating plus make-up codes) of the given colour; -1 on a bad code }
function ReadRun(var S: TFaxState; Color: Integer): Integer;
var
  L, V: Integer;
  Total: Integer;
  Found: Boolean;
begin
  Total := 0;
  repeat
    Found := False;
    for L := 2 to 13 do
    begin
      V := FaxLook[Color, L][PeekBits(S, L)] - 1;
      if V >= 0 then
      begin
        Inc(S.Pos, L);
        Inc(Total, V);
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Result := -1;
      Exit;
    end;
    if S.Pos > S.Len * 8 + 64 then
    begin
      Result := -1;
      Exit;
    end;
  until V < 64;
  Result := Total;
end;

{ 1-D coded row; Cur gets the positions where the colour changes (white to black first) }
function FaxRow1D(var S: TFaxState; W: Integer; var Cur: TIntArray; out N: Integer): Boolean;
var
  A0, Color, R: Integer;
begin
  Result := False;
  N := 0;
  A0 := 0;
  Color := 0;
  while A0 < W do
  begin
    R := ReadRun(S, Color);
    if R < 0 then Exit;
    Inc(A0, R);
    if A0 > W then A0 := W;
    Cur[N] := A0;
    Inc(N);
    Color := Color xor 1;
  end;
  Result := True;
end;

{ 2-D coded row against the reference row Ref (NRef changing elements) }
function FaxRow2D(var S: TFaxState; W: Integer; var Ref: TIntArray; NRef: Integer;
  var Cur: TIntArray; out N: Integer): Boolean;
var
  A0, Color, Bi, B1, B2, A1, A2, R1, R2, Mode, St, Guard: Integer;
  IsH, IsP: Boolean;
begin
  Result := False;
  N := 0;
  A0 := -1;
  Color := 0;
  Bi := 0;
  // sentinels after the real elements
  for Mode := 0 to 3 do Ref[NRef + Mode] := W;
  Guard := 0;
  while A0 < W do
  begin
    Inc(Guard);
    if Guard > 4 * W + 64 then Exit;
    // b1: first changing element right of a0 that changes to the opposite colour of a0
    Bi := Max(0, Bi - 2);
    while Bi < NRef + 3 do
    begin
      if (Ref[Bi] > A0) and ((Bi and 1) = Color) then Break;
      if (Ref[Bi] >= W) and ((Bi and 1) = Color) then Break;
      Inc(Bi);
    end;
    if Bi > NRef + 2 then Bi := NRef + 2;
    B1 := Ref[Bi];
    B2 := Ref[Bi + 1];
    IsH := False;
    IsP := False;
    Mode := 0;
    if PeekBits(S, 1) = 1 then begin Inc(S.Pos, 1); Mode := 0; end
    else if PeekBits(S, 3) = 3 then begin Inc(S.Pos, 3); Mode := 1; end
    else if PeekBits(S, 3) = 2 then begin Inc(S.Pos, 3); Mode := -1; end
    else if PeekBits(S, 3) = 1 then begin Inc(S.Pos, 3); IsH := True; end
    else if PeekBits(S, 4) = 1 then begin Inc(S.Pos, 4); IsP := True; end
    else if PeekBits(S, 6) = 3 then begin Inc(S.Pos, 6); Mode := 2; end
    else if PeekBits(S, 6) = 2 then begin Inc(S.Pos, 6); Mode := -2; end
    else if PeekBits(S, 7) = 3 then begin Inc(S.Pos, 7); Mode := 3; end
    else if PeekBits(S, 7) = 2 then begin Inc(S.Pos, 7); Mode := -3; end
    else Exit;      // end of data, extension codes or damage
    if S.Pos > S.Len * 8 + 64 then Exit;
    if IsP then
      A0 := B2
    else if IsH then
    begin
      R1 := ReadRun(S, Color);
      if R1 < 0 then Exit;
      R2 := ReadRun(S, Color xor 1);
      if R2 < 0 then Exit;
      St := Max(A0, 0);
      A1 := Min(W, St + R1);
      A2 := Min(W, A1 + R2);
      if N + 2 > Length(Cur) - 4 then Exit;
      Cur[N] := A1;
      Cur[N + 1] := A2;
      Inc(N, 2);
      A0 := A2;
    end
    else
    begin
      A1 := B1 + Mode;
      if A1 < 0 then A1 := 0;
      if A1 > W then A1 := W;
      if A1 < A0 then A1 := A0;
      if N + 1 > Length(Cur) - 4 then Exit;
      Cur[N] := A1;
      Inc(N);
      A0 := A1;
      Color := Color xor 1;
    end;
  end;
  Result := True;
end;

{ packs a row of colour changes as 1 bit per pixel, black runs = 1 }
procedure FaxToBits(const Ch: TIntArray; N, W: Integer; Dst: PByte; RowBytes: Integer);
var
  I, X, S, E: Integer;
begin
  FillChar(Dst^, RowBytes, 0);
  I := 0;
  while I < N do
  begin
    S := Ch[I];
    if I + 1 < N then E := Ch[I + 1] else E := W;
    if E > W then E := W;
    for X := S to E - 1 do
      Dst[X shr 3] := Dst[X shr 3] or ($80 shr (X and 7));
    Inc(I, 2);
  end;
end;

{ Compression: 2 = RLE, 3 = Group 3, 4 = Group 4. Out gets RowsN rows of RowBytes. }
function FaxDecode(const Src: TBytes; Comp, T4Opt, FillOrder, W, RowsN, RowBytes: Integer;
  var Dst: TBytes): Boolean;
var
  S: TFaxState;
  Ref, Cur, Tmp: TIntArray;
  NRef, NCur, Y, I, Z: Integer;
  TwoD, Ok: Boolean;
begin
  Result := False;
  S.Len := Length(Src);
  SetLength(S.Data, S.Len);
  if S.Len > 0 then
  begin
    if FillOrder = 2 then
      for I := 0 to S.Len - 1 do S.Data[I] := RevBits[Src[I]]
    else
      Move(Src[0], S.Data[0], S.Len);
  end;
  S.Pos := 0;
  S.Fail := False;
  Ref := nil;
  SetLength(Ref, W + 16);
  Cur := nil;
  SetLength(Cur, W + 16);
  NRef := 0;
  SetLength(Dst, Int64(RowsN) * RowBytes);
  FillChar(Dst[0], Length(Dst), 0);
  for Y := 0 to RowsN - 1 do
  begin
    if Comp = 4 then
      Ok := FaxRow2D(S, W, Ref, NRef, Cur, NCur)
    else if Comp = 2 then
    begin
      Ok := FaxRow1D(S, W, Cur, NCur);
      if Ok and ((S.Pos and 7) <> 0) then S.Pos := (S.Pos or 7) + 1;   // rows start on a byte
    end
    else
    begin
      // Group 3: optional fill zeros and an EOL (11+ zeros and a one) before each row
      Z := 0;
      while (not FaxEof(S)) and (PeekBits(S, 1) = 0) do
      begin
        Inc(S.Pos);
        Inc(Z);
      end;
      if (Z >= 11) and (not FaxEof(S)) then
        Inc(S.Pos)
      else if Z < 11 then
        Dec(S.Pos, Z);
      TwoD := False;
      if (T4Opt and 1) <> 0 then
      begin
        TwoD := PeekBits(S, 1) = 0;
        Inc(S.Pos);
      end;
      if TwoD then
        Ok := FaxRow2D(S, W, Ref, NRef, Cur, NCur)
      else
        Ok := FaxRow1D(S, W, Cur, NCur);
    end;
    if not Ok then
    begin
      Result := Y > 0;     // keep what was decoded; the rest stays white
      Exit;
    end;
    FaxToBits(Cur, NCur, W, @Dst[Int64(Y) * RowBytes], RowBytes);
    Tmp := Ref;
    Ref := Cur;
    Cur := Tmp;
    NRef := NCur;
  end;
  Result := True;
end;

procedure InitFax;
var
  I, L, C, K: Integer;
begin
  for I := 0 to 255 do
  begin
    C := 0;
    for K := 0 to 7 do
      if (I and (1 shl K)) <> 0 then C := C or (128 shr K);
    RevBits[I] := C;
  end;
  for C := 0 to 1 do
    for L := 2 to 13 do
    begin
      SetLength(FaxLook[C, L], 1 shl L);
      FillChar(FaxLook[C, L][0], (1 shl L) * SizeOf(SmallInt), 0);
    end;
  for I := 0 to 103 do
  begin
    FaxLook[0, WhiteLens[I]][WhiteCodes[I]] := WhiteRuns[I] + 1;
    FaxLook[1, BlackLens[I]][BlackCodes[I]] := BlackRuns[I] + 1;
  end;
end;

{ ---- other decompressors ---- }

function PackBitsDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  I, N, O, C, Cnt: Integer;
begin
  SetLength(Dst, Expected);
  if Expected > 0 then FillChar(Dst[0], Expected, 0);
  N := Length(Src);
  I := 0;
  O := 0;
  while (I < N) and (O < Expected) do
  begin
    C := Src[I];
    Inc(I);
    if C < 128 then
    begin
      Cnt := C + 1;
      if I + Cnt > N then Cnt := N - I;
      if O + Cnt > Expected then Cnt := Expected - O;
      if Cnt > 0 then Move(Src[I], Dst[O], Cnt);
      Inc(I, C + 1);
      Inc(O, Cnt);
    end
    else if C > 128 then
    begin
      Cnt := 257 - C;
      if O + Cnt > Expected then Cnt := Expected - O;
      if I < N then
        if Cnt > 0 then FillChar(Dst[O], Cnt, Src[I]);
      Inc(I);
      Inc(O, Cnt);
    end;
  end;
  Result := True;
end;

function LzwDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  Prefix: array[0..4095] of SmallInt;
  Suffix: array[0..4095] of Byte;
  Len: array[0..4095] of Word;
  I, N, Nxt, Width, Pos, Old, Code, O, L, C, First: Integer;
  BitBuf: LongWord;
  BitCnt: Integer;
begin
  Result := False;
  SetLength(Dst, Expected);
  if Expected > 0 then FillChar(Dst[0], Expected, 0);
  N := Length(Src);
  for I := 0 to 255 do
  begin
    Prefix[I] := -1;
    Suffix[I] := I;
    Len[I] := 1;
  end;
  Nxt := 258;
  Width := 9;
  BitBuf := 0;
  BitCnt := 0;
  Pos := 0;
  Old := -1;
  O := 0;
  while O < Expected do
  begin
    while (BitCnt < Width) and (Pos < N) do
    begin
      BitBuf := (BitBuf shl 8) or Src[Pos];
      Inc(Pos);
      Inc(BitCnt, 8);
    end;
    if BitCnt < Width then Break;
    Code := Integer((BitBuf shr (BitCnt - Width)) and ((1 shl Width) - 1));
    Dec(BitCnt, Width);
    BitBuf := BitBuf and ((LongWord(1) shl BitCnt) - 1);
    if Code = 257 then Break;
    if Code = 256 then
    begin
      Nxt := 258;
      Width := 9;
      Old := -1;
      Continue;
    end;
    if Old = -1 then
    begin
      if Code >= 256 then Exit;
      Dst[O] := Code;
      Inc(O);
      Old := Code;
      Continue;
    end;
    if Code < Nxt then
    begin
      L := Len[Code];
      // write the string backwards from its last byte
      C := Code;
      First := 0;
      for I := L - 1 downto 0 do
      begin
        if O + I < Expected then Dst[O + I] := Suffix[C];
        if I = 0 then First := Suffix[C];
        C := Prefix[C];
      end;
      Inc(O, L);
    end
    else if Code = Nxt then
    begin
      L := Len[Old];
      C := Old;
      for I := L - 1 downto 0 do
      begin
        if O + I < Expected then Dst[O + I] := Suffix[C];
        if I = 0 then First := Suffix[C];
        C := Prefix[C];
      end;
      if O + L < Expected then Dst[O + L] := First;
      Inc(O, L + 1);
    end
    else
      Exit;
    if Nxt < 4096 then
    begin
      Prefix[Nxt] := Old;
      Suffix[Nxt] := First;
      Len[Nxt] := Len[Old] + 1;
      Inc(Nxt);
      if (Nxt + 1 >= 512) and (Width = 9) then Width := 10
      else if (Nxt + 1 >= 1024) and (Width = 10) then Width := 11
      else if (Nxt + 1 >= 2048) and (Width = 11) then Width := 12;
    end;
    Old := Code;
  end;
  Result := True;
end;

function InflateDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  Ms: TMemoryStream;
  Ds: TDecompressionStream;
  Got, N: Integer;
begin
  SetLength(Dst, Expected);
  if Expected > 0 then FillChar(Dst[0], Expected, 0);
  Result := False;
  if Length(Src) = 0 then Exit;
  Ms := TMemoryStream.Create;
  try
    Ms.WriteBuffer(Src[0], Length(Src));
    Ms.Position := 0;
    Ds := TDecompressionStream.Create(Ms);
    try
      Got := 0;
      try
        while Got < Expected do
        begin
          N := Ds.Read(Dst[Got], Expected - Got);
          if N <= 0 then Break;
          Inc(Got, N);
        end;
      except
        // damaged data: keep what was read
      end;
      Result := Got > 0;
    finally
      Ds.Free;
    end;
  finally
    Ms.Free;
  end;
end;

{ ---- TIFF structure ---- }

type
  TTiffReader = class
  public
    Strm: TFileStream;
    BE: Boolean;
    Tags: array of TTag;
    W, H, Bps, Spp, Comp, Photo, Fill, Rps, Pred, Planar, T4Opt, TW, TL: Integer;
    SampleFmt: Integer;
    RowBytes: Integer;
    Offs, Cnts: TInt64Array;
    CMap: TInt64Array;
    function U16(const B: array of Byte; O: Integer): Integer;
    function U32(const B: array of Byte; O: Integer): Int64;
    function Open(const FileName: string; out Err: string): Boolean;
    function TagIdx(Tag: Word): Integer;
    function TagVals(Tag: Word): TInt64Array;
    function TagInt(Tag: Word; Def: Integer): Integer;
    function ReadChunk(I: Integer; var Buf: TBytes): Boolean;
    function DecodeChunk(I, RowsN, Width, RB: Integer; var Dst: TBytes): Boolean;
  end;

function TTiffReader.U16(const B: array of Byte; O: Integer): Integer;
begin
  if BE then Result := (B[O] shl 8) or B[O + 1] else Result := B[O] or (B[O + 1] shl 8);
end;

function TTiffReader.U32(const B: array of Byte; O: Integer): Int64;
begin
  if BE then
    Result := (Int64(B[O]) shl 24) or (Int64(B[O + 1]) shl 16) or (Int64(B[O + 2]) shl 8) or B[O + 3]
  else
    Result := B[O] or (Int64(B[O + 1]) shl 8) or (Int64(B[O + 2]) shl 16) or (Int64(B[O + 3]) shl 24);
end;

function TTiffReader.TagIdx(Tag: Word): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Tags) do
    if Tags[I].Tag = Tag then Exit(I);
  Result := -1;
end;

function TTiffReader.TagVals(Tag: Word): TInt64Array;
var
  I, J, Sz, N: Integer;
  B: TBytes;
  Off: Int64;
  Raw: array[0..3] of Byte;
begin
  Result := nil;
  I := TagIdx(Tag);
  if I < 0 then Exit;
  case Tags[I].Typ of
    1, 2, 6, 7: Sz := 1;
    3, 8: Sz := 2;
    4, 9: Sz := 4;
  else
    Exit;
  end;
  N := Tags[I].Cnt;
  if (N <= 0) or (Int64(N) * Sz > 64 * 1024 * 1024) then Exit;
  B := nil;
  SetLength(B, N * Sz);
  if N * Sz <= 4 then
  begin
    for J := 0 to 3 do Raw[J] := Tags[I].Raw[J];
    Move(Raw[0], B[0], N * Sz);
  end
  else
  begin
    Off := U32(Tags[I].Raw, 0);
    if Off + N * Sz > Strm.Size then Exit;
    Strm.Position := Off;
    Strm.ReadBuffer(B[0], N * Sz);
  end;
  SetLength(Result, N);
  for J := 0 to N - 1 do
    case Sz of
      1: Result[J] := B[J];
      2: Result[J] := U16(B, J * 2);
      4: Result[J] := U32(B, J * 4);
    end;
end;

function TTiffReader.TagInt(Tag: Word; Def: Integer): Integer;
var
  V: TInt64Array;
begin
  V := TagVals(Tag);
  if Length(V) > 0 then Result := Integer(V[0]) else Result := Def;
end;

function TTiffReader.Open(const FileName: string; out Err: string): Boolean;
var
  Hd: array[0..7] of Byte;
  IfdOff: Int64;
  Cnt: Integer;
  Blk: TBytes;
  I, O: Integer;
  V: TInt64Array;
begin
  Result := False;
  Err := '';
  Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  if Strm.Size < 16 then
  begin
    Err := 'file too small';
    Exit;
  end;
  {$PUSH}{$HINTS OFF}FillChar(Hd, SizeOf(Hd), 0);{$POP}
  Strm.ReadBuffer(Hd[0], 8);
  if (Hd[0] = Ord('I')) and (Hd[1] = Ord('I')) then BE := False
  else if (Hd[0] = Ord('M')) and (Hd[1] = Ord('M')) then BE := True
  else
  begin
    Err := 'not a TIFF file';
    Exit;
  end;
  if U16(Hd, 2) <> 42 then
  begin
    Err := 'BigTIFF is not supported';
    Exit;
  end;
  IfdOff := U32(Hd, 4);
  if (IfdOff < 8) or (IfdOff + 2 > Strm.Size) then
  begin
    Err := 'bad directory offset';
    Exit;
  end;
  Strm.Position := IfdOff;
  Blk := nil;
  SetLength(Blk, 2);
  Strm.ReadBuffer(Blk[0], 2);
  Cnt := U16(Blk, 0);
  if (Cnt < 1) or (Cnt > 500) or (IfdOff + 2 + Cnt * 12 > Strm.Size) then
  begin
    Err := 'bad directory';
    Exit;
  end;
  SetLength(Blk, Cnt * 12);
  Strm.ReadBuffer(Blk[0], Cnt * 12);
  SetLength(Tags, Cnt);
  for I := 0 to Cnt - 1 do
  begin
    O := I * 12;
    Tags[I].Tag := U16(Blk, O);
    Tags[I].Typ := U16(Blk, O + 2);
    Tags[I].Cnt := LongWord(U32(Blk, O + 4));
    Move(Blk[O + 8], Tags[I].Raw[0], 4);
  end;
  W := TagInt(256, 0);
  H := TagInt(257, 0);
  V := TagVals(258);
  if Length(V) > 0 then Bps := Integer(V[0]) else Bps := 1;
  Comp := TagInt(259, 1);
  Photo := TagInt(262, 1);
  Fill := TagInt(266, 1);
  Spp := TagInt(277, 1);
  Rps := TagInt(278, H);
  Planar := TagInt(284, 1);
  T4Opt := TagInt(292, 0);
  Pred := TagInt(317, 1);
  SampleFmt := TagInt(339, 1);
  TW := TagInt(322, 0);
  TL := TagInt(323, 0);
  if (W <= 0) or (H <= 0) or (Int64(W) * H > 2000000000) then
  begin
    Err := 'bad image size';
    Exit;
  end;
  if Planar <> 1 then begin Err := 'planar layout is not supported'; Exit; end;
  if SampleFmt > 2 then begin Err := 'floating point samples are not supported'; Exit; end;
  if not (Bps in [1, 2, 4, 8, 16]) then begin Err := 'bits per sample ' + IntToStr(Bps) + ' not supported'; Exit; end;
  if not ((Comp >= 1) and (Comp <= 5) and (Comp <> 0) or (Comp = 8) or (Comp = 32773) or (Comp = 32946)) then
  begin
    Err := 'compression ' + IntToStr(Comp) + ' is not supported';
    Exit;
  end;
  if not (Photo in [0, 1, 2, 3, 5]) then begin Err := 'photometric ' + IntToStr(Photo) + ' not supported'; Exit; end;
  if (Photo in [0, 1, 3]) and (Spp < 1) then Exit;
  if (Photo = 2) and ((Spp < 3) or (Bps < 8)) then begin Err := 'unusual RGB layout'; Exit; end;
  if (Photo = 5) and ((Spp < 4) or (Bps <> 8)) then begin Err := 'unusual CMYK layout'; Exit; end;
  if (Bps < 8) and (Spp <> 1) then begin Err := 'unusual packed layout'; Exit; end;
  if (Comp in [2, 3, 4]) and ((Bps <> 1) or (Spp <> 1)) then begin Err := 'fax compression needs 1-bit data'; Exit; end;
  RowBytes := Integer((Int64(W) * Spp * Bps + 7) div 8);
  if TagIdx(322) >= 0 then
  begin
    if (TW <= 0) or (TL <= 0) then begin Err := 'bad tile size'; Exit; end;
    Offs := TagVals(324);
    Cnts := TagVals(325);
  end
  else
  begin
    if Rps <= 0 then Rps := H;
    Offs := TagVals(273);
    Cnts := TagVals(279);
  end;
  if (Length(Offs) = 0) or (Length(Offs) <> Length(Cnts)) then
  begin
    Err := 'missing strip or tile table';
    Exit;
  end;
  if Photo = 3 then
  begin
    CMap := TagVals(320);
    if Length(CMap) < 3 * (1 shl Bps) then begin Err := 'missing colour map'; Exit; end;
  end;
  Result := True;
end;

function TTiffReader.ReadChunk(I: Integer; var Buf: TBytes): Boolean;
begin
  Result := False;
  if (I < 0) or (I >= Length(Offs)) then Exit;
  if (Cnts[I] <= 0) or (Cnts[I] > 400 * 1024 * 1024) or (Offs[I] + Cnts[I] > Strm.Size) then Exit;
  SetLength(Buf, Cnts[I]);
  Strm.Position := Offs[I];
  Strm.ReadBuffer(Buf[0], Cnts[I]);
  Result := True;
end;

{ decodes strip or tile I (RowsN rows of Width pixels, RB bytes per row) }
function TTiffReader.DecodeChunk(I, RowsN, Width, RB: Integer; var Dst: TBytes): Boolean;
var
  Src: TBytes;
  Expected, R, X, P, Base: Integer;
  V: Integer;
begin
  Result := False;
  Expected := RowsN * RB;
  Src := nil;
  if not ReadChunk(I, Src) then Exit;
  case Comp of
    1:
      begin
        SetLength(Dst, Expected);
        FillChar(Dst[0], Expected, 0);
        Move(Src[0], Dst[0], Min(Expected, Length(Src)));
        Result := True;
      end;
    32773: Result := PackBitsDecode(Src, Expected, Dst);
    5: Result := LzwDecode(Src, Expected, Dst);
    8, 32946: Result := InflateDecode(Src, Expected, Dst);
    2, 3, 4: Result := FaxDecode(Src, Comp, T4Opt, Fill, Width, RowsN, RB, Dst);
  end;
  if not Result then Exit;
  if (Pred = 2) and (Comp <> 2) and (Comp <> 3) and (Comp <> 4) then
  begin
    for R := 0 to RowsN - 1 do
    begin
      Base := R * RB;
      if Bps = 8 then
      begin
        for X := Spp to Width * Spp - 1 do
          Dst[Base + X] := Byte(Dst[Base + X] + Dst[Base + X - Spp]);
      end
      else if Bps = 16 then
      begin
        for X := Spp to Width * Spp - 1 do
        begin
          P := Base + X * 2;
          if BE then
            V := ((Dst[P] shl 8) or Dst[P + 1]) + ((Dst[P - 2 * Spp] shl 8) or Dst[P - 2 * Spp + 1])
          else
            V := (Dst[P] or (Dst[P + 1] shl 8)) + (Dst[P - 2 * Spp] or (Dst[P - 2 * Spp + 1] shl 8));
          V := V and $FFFF;
          if BE then
          begin
            Dst[P] := V shr 8;
            Dst[P + 1] := V and $FF;
          end
          else
          begin
            Dst[P] := V and $FF;
            Dst[P + 1] := V shr 8;
          end;
        end;
      end;
    end;
  end;
end;

{ ---- thumbnail ---- }

function RenderTiff(const FileName: string; MaxSide: Integer; out OutW, OutH: Integer;
  out OutPix: TBytes; out Err: string): Boolean;
var
  T: TTiffReader;
  NW, NH, X, Y, DY, CurDY, I, BandY0, BandRows, BandRB, AcrossT, DownT, TRB, R, Tx, Rn: Integer;
  Sc: Double;
  Band, Tile: TBytes;
  ColMap: TIntArray;
  ColCnt: TIntArray;
  Acc: array of Cardinal;
  Pix: TBytes;
  RowCnt: Integer;
  Row: PByte;
  Tiled: Boolean;
  RV, GV, BV, Nc, K, Cc, Mc, Yc: Integer;

  procedure EmitRow(DestY: Integer);
  var
    Dx, Dv, O: Integer;
  begin
    for Dx := 0 to NW - 1 do
    begin
      Dv := ColCnt[Dx] * RowCnt;
      if Dv < 1 then Dv := 1;
      O := (DestY * NW + Dx) * 3;
      Pix[O] := Byte(Acc[Dx * 3] div Cardinal(Dv));
      Pix[O + 1] := Byte(Acc[Dx * 3 + 1] div Cardinal(Dv));
      Pix[O + 2] := Byte(Acc[Dx * 3 + 2] div Cardinal(Dv));
    end;
    FillChar(Acc[0], Length(Acc) * SizeOf(Cardinal), 0);
    RowCnt := 0;
  end;

  procedure AddRow(P: PByte);
  var
    Xx, Dx, S0, Q: Integer;
    Vv: Integer;
  begin
    case T.Photo of
      0, 1:
        for Xx := 0 to T.W - 1 do
        begin
          case T.Bps of
            1: Vv := ((P[Xx shr 3] shr (7 - (Xx and 7))) and 1) * 255;
            2: Vv := ((P[Xx shr 2] shr (6 - 2 * (Xx and 3))) and 3) * 85;
            4: Vv := ((P[Xx shr 1] shr (4 - 4 * (Xx and 1))) and 15) * 17;
            8: Vv := P[Xx * T.Spp];
          else
            if T.BE then Vv := P[Xx * T.Spp * 2] else Vv := P[Xx * T.Spp * 2 + 1];
          end;
          if T.Photo = 0 then Vv := 255 - Vv;
          Dx := ColMap[Xx];
          Inc(Acc[Dx * 3], Vv);
          Inc(Acc[Dx * 3 + 1], Vv);
          Inc(Acc[Dx * 3 + 2], Vv);
        end;
      3:
        begin
          Nc := 1 shl T.Bps;
          for Xx := 0 to T.W - 1 do
          begin
            case T.Bps of
              1: Q := (P[Xx shr 3] shr (7 - (Xx and 7))) and 1;
              2: Q := (P[Xx shr 2] shr (6 - 2 * (Xx and 3))) and 3;
              4: Q := (P[Xx shr 1] shr (4 - 4 * (Xx and 1))) and 15;
              8: Q := P[Xx * T.Spp];
            else
              if T.BE then Q := (P[Xx * T.Spp * 2] shl 8) or P[Xx * T.Spp * 2 + 1]
              else Q := P[Xx * T.Spp * 2] or (P[Xx * T.Spp * 2 + 1] shl 8);
            end;
            if Q >= Nc then Q := Nc - 1;
            Dx := ColMap[Xx];
            Inc(Acc[Dx * 3], T.CMap[Q] shr 8);
            Inc(Acc[Dx * 3 + 1], T.CMap[Nc + Q] shr 8);
            Inc(Acc[Dx * 3 + 2], T.CMap[2 * Nc + Q] shr 8);
          end;
        end;
      2:
        for Xx := 0 to T.W - 1 do
        begin
          if T.Bps = 8 then
          begin
            S0 := Xx * T.Spp;
            RV := P[S0]; GV := P[S0 + 1]; BV := P[S0 + 2];
          end
          else
          begin
            S0 := Xx * T.Spp * 2;
            if T.BE then Q := 0 else Q := 1;
            RV := P[S0 + Q]; GV := P[S0 + 2 + Q]; BV := P[S0 + 4 + Q];
          end;
          Dx := ColMap[Xx];
          Inc(Acc[Dx * 3], RV);
          Inc(Acc[Dx * 3 + 1], GV);
          Inc(Acc[Dx * 3 + 2], BV);
        end;
      5:
        for Xx := 0 to T.W - 1 do
        begin
          S0 := Xx * T.Spp;
          Cc := P[S0]; Mc := P[S0 + 1]; Yc := P[S0 + 2]; K := P[S0 + 3];
          Dx := ColMap[Xx];
          Inc(Acc[Dx * 3], (255 - Cc) * (255 - K) div 255);
          Inc(Acc[Dx * 3 + 1], (255 - Mc) * (255 - K) div 255);
          Inc(Acc[Dx * 3 + 2], (255 - Yc) * (255 - K) div 255);
        end;
    end;
  end;

begin
  Result := False;
  Err := '';
  T := TTiffReader.Create;
  try
    try
      if not T.Open(FileName, Err) then
      begin
        if Err = '' then Err := 'unsupported TIFF layout';
        Exit;
      end;
      if Max(T.W, T.H) > MaxSide then Sc := MaxSide / Max(T.W, T.H) else Sc := 1;
      NW := Max(1, Round(T.W * Sc));
      NH := Max(1, Round(T.H * Sc));
      ColMap := nil;
      SetLength(ColMap, T.W);
      ColCnt := nil;
      SetLength(ColCnt, NW);
      for X := 0 to T.W - 1 do
      begin
        ColMap[X] := Integer((Int64(X) * NW) div T.W);
        Inc(ColCnt[ColMap[X]]);
      end;
      Acc := nil;
      SetLength(Acc, NW * 3);
      FillChar(Acc[0], Length(Acc) * SizeOf(Cardinal), 0);
      Pix := nil;
      SetLength(Pix, NW * NH * 3);
      FillChar(Pix[0], Length(Pix), 255);
      Tiled := T.TagIdx(322) >= 0;
      BandY0 := 0;
      BandRows := 0;
      BandRB := T.RowBytes;
      TRB := 0;
      AcrossT := 0;
      DownT := 0;
      if Tiled then
      begin
        AcrossT := (T.W + T.TW - 1) div T.TW;
        DownT := (T.H + T.TL - 1) div T.TL;
        TRB := Integer((Int64(T.TW) * T.Spp * T.Bps + 7) div 8);
        BandRB := TRB * AcrossT;
        if Length(T.Offs) < AcrossT * DownT then
        begin
          Err := 'missing tiles';
          Exit;
        end;
      end;
      CurDY := 0;
      RowCnt := 0;
      Y := 0;
      while Y < T.H do
      begin
        if Y >= BandY0 + BandRows then
        begin
          // next strip, or next row of tiles
          if Tiled then
          begin
            Rn := Min(T.TL, T.H - Y);
            if Int64(BandRB) * Rn > 800 * 1024 * 1024 then begin Err := 'strip too large'; Exit; end;
            Band := nil;
            SetLength(Band, BandRB * Rn);
            FillChar(Band[0], Length(Band), 0);
            for Tx := 0 to AcrossT - 1 do
            begin
              Tile := nil;
              if not T.DecodeChunk((Y div T.TL) * AcrossT + Tx, T.TL, T.TW, TRB, Tile) then
              begin
                Err := 'tile could not be decoded';
                Exit;
              end;
              for R := 0 to Rn - 1 do
                Move(Tile[R * TRB], Band[R * BandRB + Tx * TRB], TRB);
            end;
            BandY0 := Y;
            BandRows := Rn;
          end
          else
          begin
            Rn := Min(T.Rps, T.H - Y);
            if Int64(BandRB) * Rn > 800 * 1024 * 1024 then begin Err := 'strip too large'; Exit; end;
            I := Y div T.Rps;
            if I >= Length(T.Offs) then begin Err := 'missing strip'; Exit; end;
            if not T.DecodeChunk(I, Rn, T.W, BandRB, Band) then
            begin
              Err := 'strip could not be decoded (compression ' + IntToStr(T.Comp) + ')';
              Exit;
            end;
            BandY0 := I * T.Rps;
            BandRows := Rn;
            if BandY0 < Y then
            begin
              // cannot happen with a regular strip table; guard against odd files
              BandY0 := Y;
            end;
          end;
        end;
        DY := Integer((Int64(Y) * NH) div T.H);
        if DY <> CurDY then
        begin
          EmitRow(CurDY);
          CurDY := DY;
        end;
        Row := @Band[(Y - BandY0) * BandRB];
        AddRow(Row);
        Inc(RowCnt);
        Inc(Y);
      end;
      EmitRow(CurDY);

      OutW := NW;
      OutH := NH;
      OutPix := Pix;
      Result := True;
    except
      on E: Exception do
      begin
        Err := E.ClassName + ' ' + E.Message;
        Result := False;
      end;
    end;
  finally
    T.Strm.Free;
    T.Free;
  end;
end;

function LoadTiffThumb(const FileName: string; MaxSide: Integer; Bmp: TBitmap;
  out Err: string): Boolean;
var
  NW, NH, X, Y, I, LineLen: Integer;
  Pix, Line: TBytes;
  Ms: TMemoryStream;
  FH: TBmpFileHdr;
  IH: TBmpInfoHdr;
begin
  Result := False;
  if not RenderTiff(FileName, MaxSide, NW, NH, Pix, Err) then Exit;
  try
    // 24-bit bottom-up BMP, stored as B,G,R
    LineLen := ((NW * 3 + 3) div 4) * 4;
    Line := nil;
    SetLength(Line, LineLen);
    FH.bfType := $4D42;
    FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;
    FH.bfReserved := 0;
    FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
    IH.biSize := SizeOf(IH);
    IH.biWidth := NW;
    IH.biHeight := NH;
    IH.biPlanes := 1;
    IH.biBitCount := 24;
    IH.biCompression := 0;
    IH.biSizeImage := LineLen * NH;
    IH.biXPels := 2835;
    IH.biYPels := 2835;
    IH.biClrUsed := 0;
    IH.biClrImportant := 0;
    Ms := TMemoryStream.Create;
    try
      Ms.WriteBuffer(FH, SizeOf(FH));
      Ms.WriteBuffer(IH, SizeOf(IH));
      for Y := NH - 1 downto 0 do
      begin
        FillChar(Line[0], LineLen, 0);
        for X := 0 to NW - 1 do
        begin
          I := (Y * NW + X) * 3;
          Line[X * 3] := Pix[I + 2];        // blue
          Line[X * 3 + 1] := Pix[I + 1];    // green
          Line[X * 3 + 2] := Pix[I];        // red
        end;
        Ms.WriteBuffer(Line[0], LineLen);
      end;
      Ms.Position := 0;
      Bmp.LoadFromStream(Ms);
    finally
      Ms.Free;
    end;
    Result := (Bmp.Width > 0) and (Bmp.Height > 0);
    if not Result then Err := 'empty picture';
  except
    on E: Exception do
    begin
      Err := E.ClassName + ' ' + E.Message;
      Result := False;
    end;
  end;
end;

function LoadTiffMemImageAny(const FileName: string; Target: Integer; out Err: string): TFPMemoryImage;
var
  NW, NH, X, Y, I: Integer;
  Pix: TBytes;
  Img: TFPMemoryImage;
  C: TFPColor;
begin
  Result := nil;
  if not RenderTiff(FileName, Target, NW, NH, Pix, Err) then Exit;
  try
    Img := TFPMemoryImage.Create(NW, NH);
    try
      for Y := 0 to NH - 1 do
        for X := 0 to NW - 1 do
        begin
          I := (Y * NW + X) * 3;
          C.Red := Word(Pix[I] * 257);
          C.Green := Word(Pix[I + 1] * 257);
          C.Blue := Word(Pix[I + 2] * 257);
          C.Alpha := $FFFF;
          Img.Colors[X, Y] := C;
        end;
      Result := Img;
      Img := nil;
    finally
      Img.Free;
    end;
  except
    on E: Exception do
    begin
      Err := E.ClassName + ' ' + E.Message;
      Result := nil;
    end;
  end;
end;

initialization
  InitFax;

end.
