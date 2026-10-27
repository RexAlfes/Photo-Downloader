unit uTiffRead;

{$mode objfpc}{$H+}
{$POINTERMATH ON}

{ Thumbnails for TIFF files that the plain reader in uItems cannot handle: compressed (LZW,
  PackBits, Deflate, CCITT fax Group 3 / Group 4 and RLE), 1/2/4/8/16-bit gray, palette, RGB and
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
  WhiteRuns: array[0..103] of Word = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 128, 192, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024, 1088, 1152, 1216, 1280, 1344, 1408, 1472, 1536, 1600, 1664, 1728, 1792, 1856, 1920, 1984, 2048, 2112, 2176, 2240, 2304, 2368, 2432, 2496, 2560);  // run lengths of the white fax codes
  WhiteCodes: array[0..103] of Word = (53, 7, 7, 8, 11, 12, 14, 15, 19, 20, 7, 8, 8, 3, 52, 53, 42, 43, 39, 12, 8, 23, 3, 4, 40, 43, 19, 36, 24, 2, 3, 26, 27, 18, 19, 20, 21, 22, 23, 40, 41, 42, 43, 44, 45, 4, 5, 10, 11, 82, 83, 84, 85, 36, 37, 88, 89, 90, 91, 74, 75, 50, 51, 52, 27, 18, 23, 55, 54, 55, 100, 101, 104, 103, 204, 205, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 152, 153, 154, 24, 155, 8, 12, 13, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31);  // bit patterns of the white fax codes
  WhiteLens: array[0..103] of Byte = (8, 6, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 5, 5, 6, 7, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 9, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12);  // bit lengths of the white fax codes
  BlackRuns: array[0..103] of Word = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 128, 192, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024, 1088, 1152, 1216, 1280, 1344, 1408, 1472, 1536, 1600, 1664, 1728, 1792, 1856, 1920, 1984, 2048, 2112, 2176, 2240, 2304, 2368, 2432, 2496, 2560);  // run lengths of the black fax codes
  BlackCodes: array[0..103] of Word = (55, 2, 3, 2, 3, 3, 2, 3, 5, 4, 4, 5, 7, 4, 7, 24, 23, 24, 8, 103, 104, 108, 55, 40, 23, 24, 202, 203, 204, 205, 104, 105, 106, 107, 210, 211, 212, 213, 214, 215, 108, 109, 218, 219, 84, 85, 86, 87, 100, 101, 82, 83, 36, 55, 56, 39, 40, 88, 89, 43, 44, 90, 102, 103, 15, 200, 201, 91, 51, 52, 53, 108, 109, 74, 75, 76, 77, 114, 115, 116, 117, 118, 119, 82, 83, 84, 85, 90, 91, 100, 101, 8, 12, 13, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31);  // bit patterns of the black fax codes
  BlackLens: array[0..103] of Byte = (10, 3, 2, 2, 3, 4, 4, 5, 6, 6, 7, 7, 7, 8, 8, 9, 10, 10, 10, 11, 11, 11, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 10, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12);  // bit lengths of the black fax codes

type
  TInt64Array = array of Int64;  // list of 64-bit values
  TIntArray = array of Integer;  // list of integers

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

  { One 12-byte entry of a TIFF directory. }
  TTag = record
    Tag, Typ: Word;  // tag number and data type
    Cnt: LongWord;  // number of values
    Raw: array[0..3] of Byte;  // the value itself, or the file offset of the values
  end;

var
  { fax code lookup: [color 0 = white, 1 = black, code length 2..13][code value] = run + 1 (0 = none) }
  FaxLook: array[0..1, 2..13] of array of SmallInt;  // fax code lookup tables, indexed by color and code length
  RevBits: array[0..255] of Byte;  // table that mirrors the bit order of a byte

{ ---- fax (CCITT) decoding ---- }

type
  TFaxState = record  // state of the fax bit reader
    Data: TBytes;  // the compressed bytes
    Len: Integer;          // bytes
    Pos: Integer;          // bit position
    Fail: Boolean;  // True once a decoding error occurred
  end;

{ Returns byte P of the fax data, or 0 past the end. }
function GetB(const S: TFaxState; P: Integer): Cardinal; inline;
begin
  if P < S.Len then Result := S.Data[P] else Result := 0;  // byte value or zero past the end
end;

{ Returns the next K bits (at most 24) without consuming them. }
function PeekBits(const S: TFaxState; K: Integer): Integer;
var
  P: Integer;  // P: byte index
  V: Cardinal;  // V: 32 bits starting at that byte
begin
  P := S.Pos shr 3;  // byte holding the current bit
  V := (GetB(S, P) shl 24) or (GetB(S, P + 1) shl 16) or (GetB(S, P + 2) shl 8) or GetB(S, P + 3);  // combine four bytes, most significant first
  V := V shl (S.Pos and 7);  // drop the bits already consumed in the first byte
  Result := Integer(V shr (32 - K));  // keep the top K bits
end;

{ True when all fax data has been consumed. }
function FaxEof(const S: TFaxState): Boolean; inline;
begin
  Result := S.Pos >= S.Len * 8;  // compare bit position with the data size in bits
end;

{ one run length (terminating plus make-up codes) of the given color; -1 on a bad code }
function ReadRun(var S: TFaxState; Color: Integer): Integer;
var
  L, V: Integer;  // L: code length; V: run value
  Total: Integer;  // sum of make-up and terminating codes
  Found: Boolean;  // True when a code was recognized
begin
  Total := 0;  // start with no total
  repeat
    Found := False;
    for L := 2 to 13 do  // try code lengths from short to long
    begin
      V := FaxLook[Color, L][PeekBits(S, L)] - 1;  // look up the run (stored plus one)
      if V >= 0 then
      begin
        Inc(S.Pos, L);  // consume the code bits
        Inc(Total, V);  // add the run to the total
        Found := True;  // remember that a code matched
        Break;  // stop searching lengths
      end;
    end;
    if not Found then
    begin  // no code matched: bad data
      Result := -1;
      Exit;
    end;
    if S.Pos > S.Len * 8 + 64 then  // reading far past the end means damaged data
    begin  // bad data
      Result := -1;
      Exit;
    end;
  until V < 64;  // a value below 64 is a terminating code
  Result := Total;  // return the total run length
end;

{ 1-D coded row; Cur gets the positions where the color changes (white to black first) }
function FaxRow1D(var S: TFaxState; W: Integer; var Cur: TIntArray; out N: Integer): Boolean;
var
  A0, Color, R: Integer;  // A0: current position; Color: current color (0 white, 1 black); R: run length
begin
  Result := False;  // assume failure
  N := 0;  // no color changes yet
  A0 := 0;  // start at the left edge
  Color := 0;  // start with white
  while A0 < W do
  begin  // loop until the row is full
    R := ReadRun(S, Color);  // read one run of the current color
    if R < 0 then Exit;  // bad code ends the row with failure
    Inc(A0, R);  // move the position by the run
    if A0 > W then A0 := W;  // clamp at the row width
    Cur[N] := A0;  // record the color change
    Inc(N);  // count the change
    Color := Color xor 1;  // switch between white and black
  end;
  Result := True;  // row decoded
end;

{ 2-D coded row against the reference row Ref (NRef changing elements) }
function FaxRow2D(var S: TFaxState; W: Integer; var Ref: TIntArray; NRef: Integer;
  var Cur: TIntArray; out N: Integer): Boolean;
var
  A0, Color, Bi, B1, B2, A1, A2, R1, R2, Mode, St, Guard: Integer;  // A0: reference position; Color: current color; Bi: index in reference row; B1, B2: reference changes; A1, A2: new changes; R1, R2: run lengths; Mode: vertical offset; St: start of a horizontal run; Guard: loop counter
  IsH, IsP: Boolean;  // IsH: horizontal mode; IsP: pass mode
begin
  Result := False;  // assume failure
  N := 0;  // no color changes yet
  A0 := -1;  // position before the first pixel
  Color := 0;  // start with white
  Bi := 0;  // start at the first reference change
  // sentinels after the real elements
  for Mode := 0 to 3 do Ref[NRef + Mode] := W;  // put end markers after the real changes
  Guard := 0;  // loop counter against endless loops
  while A0 < W do  // loop until the row is full
  begin  // count this step
    Inc(Guard);  // too many steps means damaged data
    if Guard > 4 * W + 64 then Exit;
    // b1: first changing element right of a0 that changes to the opposite color of a0
    Bi := Max(0, Bi - 2);  // step back a little before searching again
    while Bi < NRef + 3 do  // search the reference row
    begin
      if (Ref[Bi] > A0) and ((Bi and 1) = Color) then Break;  // first change right of A0 with the right color
      if (Ref[Bi] >= W) and ((Bi and 1) = Color) then Break;  // a change at the row end also qualifies
      Inc(Bi);  // next reference change
    end;
    if Bi > NRef + 2 then Bi := NRef + 2;  // stay inside the markers
    B1 := Ref[Bi];  // first reference change
    B2 := Ref[Bi + 1];  // the change after it
    IsH := False;  // not horizontal mode yet
    IsP := False;  // not pass mode yet
    Mode := 0;  // default is vertical mode 0
    if PeekBits(S, 1) = 1 then begin Inc(S.Pos, 1); Mode := 0; end  // V0: directly below B1
    else if PeekBits(S, 3) = 3 then begin Inc(S.Pos, 3); Mode := 1; end  // VR1: one pixel right of B1
    else if PeekBits(S, 3) = 2 then begin Inc(S.Pos, 3); Mode := -1; end  // VL1: one pixel left of B1
    else if PeekBits(S, 3) = 1 then begin Inc(S.Pos, 3); IsH := True; end  // horizontal mode
    else if PeekBits(S, 4) = 1 then begin Inc(S.Pos, 4); IsP := True; end  // pass mode
    else if PeekBits(S, 6) = 3 then begin Inc(S.Pos, 6); Mode := 2; end  // VR2: two pixels right of B1
    else if PeekBits(S, 6) = 2 then begin Inc(S.Pos, 6); Mode := -2; end  // VL2: two pixels left of B1
    else if PeekBits(S, 7) = 3 then begin Inc(S.Pos, 7); Mode := 3; end  // VR3: three pixels right of B1
    else if PeekBits(S, 7) = 2 then begin Inc(S.Pos, 7); Mode := -3; end  // VL3: three pixels left of B1
    else Exit;      // end of data, extension codes or damage
    if S.Pos > S.Len * 8 + 64 then Exit;  // reading far past the end means damaged data
    if IsP then
      A0 := B2  // pass mode skips to B2 without a change
    else if IsH then
    begin
      R1 := ReadRun(S, Color);  // first run of the horizontal pair
      if R1 < 0 then Exit;  // bad code
      R2 := ReadRun(S, Color xor 1);  // second run, opposite color
      if R2 < 0 then Exit;  // bad code
      St := Max(A0, 0);  // start of the pair
      A1 := Min(W, St + R1);  // end of the first run
      A2 := Min(W, A1 + R2);  // end of the second run
      if N + 2 > Length(Cur) - 4 then Exit;  // stop when the change list is full
      Cur[N] := A1;  // record the first change
      Cur[N + 1] := A2;  // record the second change
      Inc(N, 2);  // two changes added
      A0 := A2;  // continue after the pair
    end
    else
    begin
      A1 := B1 + Mode;  // new change relative to B1
      if A1 < 0 then A1 := 0;  // not left of the row
      if A1 > W then A1 := W;  // not right of the row
      if A1 < A0 then A1 := A0;  // never move backwards
      if N + 1 > Length(Cur) - 4 then Exit;  // stop when the change list is full
      Cur[N] := A1;  // record the change
      Inc(N);  // count the change
      A0 := A1;  // continue at the change
      Color := Color xor 1;  // switch color
    end;
  end;
  Result := True;  // row decoded
end;

{ packs a row of color changes as 1 bit per pixel, black runs = 1 }
procedure FaxToBits(const Ch: TIntArray; N, W: Integer; Dst: PByte; RowBytes: Integer);
var
  I, X, S, E: Integer;  // I: index of the change; X: pixel; S: run start; E: run end
begin
  FillChar(Dst^, RowBytes, 0);  // start with an all white row
  I := 0;  // start at the first change
  while I < N do
  begin  // start of a black run
    S := Ch[I];
    if I + 1 < N then E := Ch[I + 1] else E := W;  // end of the run or the row end
    if E > W then E := W;  // clamp to the row width
    for X := S to E - 1 do
      Dst[X shr 3] := Dst[X shr 3] or ($80 shr (X and 7));  // set the pixel bit
    Inc(I, 2);  // skip to the next black run
  end;
end;

{ Compression: 2 = RLE, 3 = Group 3, 4 = Group 4. Out gets RowsN rows of RowBytes. }
function FaxDecode(const Src: TBytes; Comp, T4Opt, FillOrder, W, RowsN, RowBytes: Integer;
  var Dst: TBytes): Boolean;
var
  S: TFaxState;  // S: fax bit reader
  Ref, Cur, Tmp: TIntArray;  // Ref: reference row; Cur: current row; Tmp: swap helper
  NRef, NCur, Y, I, Z: Integer;  // NRef, NCur: change counts; Y: row; I: byte index; Z: zero bits skipped
  TwoD, Ok: Boolean;  // TwoD: row is 2-D coded; Ok: row decoded
begin
  Result := False;  // assume failure
  S.Len := Length(Src);  // data size
  SetLength(S.Data, S.Len);  // reserve the working copy
  if S.Len > 0 then
  begin
    if FillOrder = 2 then  // bit order reversed in the file
      for I := 0 to S.Len - 1 do S.Data[I] := RevBits[Src[I]]  // mirror every byte
    else
      Move(Src[0], S.Data[0], S.Len);  // copy the bytes as they are
  end;
  S.Pos := 0;  // start at the first bit
  S.Fail := False;  // no error yet
  Ref := nil;  // release any old array
  SetLength(Ref, W + 16);  // reference row with spare room
  Cur := nil;  // release any old array
  SetLength(Cur, W + 16);  // current row with spare room
  NRef := 0;  // first reference row is all white
  SetLength(Dst, Int64(RowsN) * RowBytes);  // reserve the output
  FillChar(Dst[0], Length(Dst), 0);  // start all white
  for Y := 0 to RowsN - 1 do
  begin
    if Comp = 4 then
      Ok := FaxRow2D(S, W, Ref, NRef, Cur, NCur)  // group 4: every row is 2-D
    else if Comp = 2 then
    begin
      Ok := FaxRow1D(S, W, Cur, NCur);  // RLE: every row is 1-D
      if Ok and ((S.Pos and 7) <> 0) then S.Pos := (S.Pos or 7) + 1;   // rows start on a byte
    end
    else
    begin
      // Group 3: optional fill zeros and an EOL (11+ zeros and a one) before each row
      Z := 0;
      while (not FaxEof(S)) and (PeekBits(S, 1) = 0) do  // count the fill zero bits
      begin
        Inc(S.Pos);  // consume a zero bit
        Inc(Z);  // count it
      end;
      if (Z >= 11) and (not FaxEof(S)) then
        Inc(S.Pos)  // skip the one bit that ends the EOL
      else if Z < 11 then
        Dec(S.Pos, Z);  // no EOL: give the zeros back
      TwoD := False;
      if (T4Opt and 1) <> 0 then  // bit T4Options 0 says 2-D coding may be used
      begin
        TwoD := PeekBits(S, 1) = 0;  // a zero tag bit means 2-D
        Inc(S.Pos);  // consume the tag bit
      end;
      if TwoD then
        Ok := FaxRow2D(S, W, Ref, NRef, Cur, NCur)  // 2-D row
      else
        Ok := FaxRow1D(S, W, Cur, NCur);  // 1-D row
    end;
    if not Ok then
    begin
      Result := Y > 0;     // keep what was decoded; the rest stays white
      Exit;
    end;
    FaxToBits(Cur, NCur, W, @Dst[Int64(Y) * RowBytes], RowBytes);  // store the row as bits
    Tmp := Ref;  // current row becomes the reference
    Ref := Cur;  // swap the two arrays
    Cur := Tmp;  // swap the two arrays
    NRef := NCur;  // remember the number of changes
  end;
  Result := True;  // all rows decoded
end;

{ Builds the fax lookup tables and the bit reverse table. }
procedure InitFax;
var
  I, L, C, K: Integer;  // I: loop counter; L: code length; C: color or mirrored byte; K: bit
begin
  for I := 0 to 255 do
  begin
    C := 0;  // mirrored byte
    for K := 0 to 7 do  // go through the 8 bits
      if (I and (1 shl K)) <> 0 then C := C or (128 shr K);  // move a set bit to its mirror position
    RevBits[I] := C;  // store the mirrored value
  end;
  for C := 0 to 1 do  // both colors
    for L := 2 to 13 do  // all code lengths
    begin
      SetLength(FaxLook[C, L], 1 shl L);  // table with one slot per bit pattern
      FillChar(FaxLook[C, L][0], (1 shl L) * SizeOf(SmallInt), 0);  // clear the table
    end;
  for I := 0 to 103 do  // all 104 codes
  begin
    FaxLook[0, WhiteLens[I]][WhiteCodes[I]] := WhiteRuns[I] + 1;  // enter the white run
    FaxLook[1, BlackLens[I]][BlackCodes[I]] := BlackRuns[I] + 1;  // enter the black run
  end;
end;

{ ---- other decompressors ---- }

{ Decodes PackBits (TIFF RLE) data into Expected bytes. }
function PackBitsDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  I, N, O, C, Cnt: Integer;  // I: input position; N: input size; O: output position; C: control byte; Cnt: byte count
begin
  SetLength(Dst, Expected);  // reserve the output
  if Expected > 0 then FillChar(Dst[0], Expected, 0);  // start with zeros
  N := Length(Src);  // input size
  I := 0;  // start at the first input byte
  O := 0;  // start at the first output byte
  while (I < N) and (O < Expected) do
  begin
    C := Src[I];  // control byte
    Inc(I);  // move past it
    if C < 128 then  // 0..127: copy C + 1 literal bytes
    begin
      Cnt := C + 1;  // number of bytes to copy
      if I + Cnt > N then Cnt := N - I;  // limit to the input left
      if O + Cnt > Expected then Cnt := Expected - O;  // limit to the output left
      if Cnt > 0 then Move(Src[I], Dst[O], Cnt);  // copy the bytes
      Inc(I, C + 1);  // move past the literals
      Inc(O, Cnt);  // move the output position
    end
    else if C > 128 then  // 129..255: repeat the next byte
    begin
      Cnt := 257 - C;  // repeat count
      if O + Cnt > Expected then Cnt := Expected - O;  // limit to the output left
      if I < N then
        if Cnt > 0 then FillChar(Dst[O], Cnt, Src[I]);  // fill with the repeated byte
      Inc(I);  // move past the repeated byte
      Inc(O, Cnt);  // move the output position
    end;
  end;
  Result := True;  // always succeeds, damaged data stays zero
end;

{ Decodes TIFF LZW data (most significant bit first) into Expected bytes. }
function LzwDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  Prefix: array[0..4095] of SmallInt;  // string table: previous code
  Suffix: array[0..4095] of Byte;  // string table: last byte of the string
  Len: array[0..4095] of Word;  // string table: length of the string
  I, N, Nxt, Width, Pos, Old, Code, O, L, C, First: Integer;  // I: loop counter; N: input size; Nxt: next free code; Width: current code width in bits; Pos: input position; Old: previous code; Code: current code; O: output position; L: string length; C: walking code; First: first byte of the string
  BitBuf: LongWord;  // bit buffer
  BitCnt: Integer;  // number of bits in the buffer
begin
  Result := False;
  SetLength(Dst, Expected);  // reserve the output
  if Expected > 0 then FillChar(Dst[0], Expected, 0);  // start with zeros
  N := Length(Src);  // input size
  for I := 0 to 255 do
  begin  // codes 0..255 are single bytes
    Prefix[I] := -1;  // no previous code
    Suffix[I] := I;  // the byte itself
    Len[I] := 1;  // length one
  end;
  Nxt := 258;  // first free code after clear and end codes
  Width := 9;  // start with 9-bit codes
  BitBuf := 0;  // empty bit buffer
  BitCnt := 0;  // no bits yet
  Pos := 0;  // start at the first input byte
  Old := -1;  // no previous code yet
  O := 0;  // start at the first output byte
  while O < Expected do  // until the output is full
  begin
    while (BitCnt < Width) and (Pos < N) do  // fill the bit buffer
    begin
      BitBuf := (BitBuf shl 8) or Src[Pos];  // add a byte at the bottom
      Inc(Pos);  // next input byte
      Inc(BitCnt, 8);  // eight more bits
    end;
    if BitCnt < Width then Break;  // input ended
    Code := Integer((BitBuf shr (BitCnt - Width)) and ((1 shl Width) - 1));  // take the top Width bits
    Dec(BitCnt, Width);  // remove them from the count
    BitBuf := BitBuf and ((LongWord(1) shl BitCnt) - 1);  // keep only the unused bits
    if Code = 257 then Break;  // code 257 ends the data
    if Code = 256 then
    begin
      Nxt := 258;  // reset the table
      Width := 9;  // back to 9-bit codes
      Old := -1;  // forget the previous code
      Continue;  // continue with the next code
    end;
    if Old = -1 then
    begin
      if Code >= 256 then Exit;  // the first code must be a literal
      Dst[O] := Code;  // write the byte
      Inc(O);  // next output byte
      Old := Code;  // remember the code
      Continue;  // continue with the next code
    end;
    if Code < Nxt then
    begin
      L := Len[Code];  // length of the string
      // write the string backwards from its last byte
      C := Code;  // start at the code
      First := 0;  // first byte unknown yet
      for I := L - 1 downto 0 do  // walk the string from the end
      begin
        if O + I < Expected then Dst[O + I] := Suffix[C];  // write the byte if there is room
        if I = 0 then First := Suffix[C];  // the last step is the first byte
        C := Prefix[C];  // go to the previous code
      end;
      Inc(O, L);  // move the output position
    end
    else if Code = Nxt then
    begin
      L := Len[Old];  // length of the old string
      C := Old;  // start at the old code
      for I := L - 1 downto 0 do  // walk the old string from the end
      begin
        if O + I < Expected then Dst[O + I] := Suffix[C];  // write the byte if there is room
        if I = 0 then First := Suffix[C];  // the last step is the first byte
        C := Prefix[C];  // go to the previous code
      end;
      if O + L < Expected then Dst[O + L] := First;  // the new string ends with its own first byte
      Inc(O, L + 1);  // move the output position
    end
    else
      Exit;  // a code beyond the table is damage
    if Nxt < 4096 then
    begin
      Prefix[Nxt] := Old;  // new entry starts with the old string
      Suffix[Nxt] := First;  // and adds the first byte
      Len[Nxt] := Len[Old] + 1;  // one byte longer
      Inc(Nxt);  // next free code
      if (Nxt + 1 >= 512) and (Width = 9) then Width := 10  // switch to 10-bit codes
      else if (Nxt + 1 >= 1024) and (Width = 10) then Width := 11  // switch to 11-bit codes
      else if (Nxt + 1 >= 2048) and (Width = 11) then Width := 12;  // switch to 12-bit codes
    end;
    Old := Code;  // remember the code
  end;
  Result := True;  // always succeeds, damaged data stays zero
end;

{ Decompresses zlib (Deflate) data into Expected bytes; damaged data keeps what was read. }
function InflateDecode(const Src: TBytes; Expected: Integer; var Dst: TBytes): Boolean;
var
  Ms: TMemoryStream;  // Ms: memory stream with the compressed data
  Ds: TDecompressionStream;  // Ds: decompression stream
  Got, N: Integer;  // Got: bytes read; N: bytes of one read
begin
  SetLength(Dst, Expected);  // reserve the output
  if Expected > 0 then FillChar(Dst[0], Expected, 0);  // start with zeros
  Result := False;  // assume failure
  if Length(Src) = 0 then Exit;  // no data
  Ms := TMemoryStream.Create;  // stream for the compressed bytes
  try
    Ms.WriteBuffer(Src[0], Length(Src));  // copy the compressed bytes
    Ms.Position := 0;  // rewind
    Ds := TDecompressionStream.Create(Ms);  // zlib reader
    try
      Got := 0;  // nothing read yet
      try
        while Got < Expected do  // until the output is full
        begin
          N := Ds.Read(Dst[Got], Expected - Got);  // read a block
          if N <= 0 then Break;  // end of data
          Inc(Got, N);  // count the bytes
        end;
      except
        // damaged data: keep what was read
      end;
      Result := Got > 0;  // success when something was read
    finally
      Ds.Free;  // free the reader
    end;
  finally
    Ms.Free;  // free the stream
  end;
end;

{ ---- TIFF structure ---- }

type
  TTiffReader = class  // reader for one TIFF file
  public
    Strm: TFileStream;  // the open file
    BE: Boolean;  // True for big-endian files
    Tags: array of TTag;  // directory entries
    W, H, Bps, Spp, Comp, Photo, Fill, Rps, Pred, Planar, T4Opt, TW, TL: Integer;  // W, H: size; Bps: bits per sample; Spp: samples per pixel; Comp: compression; Photo: photometric type; Fill: fill order; Rps: rows per strip; Pred: predictor; Planar: planar configuration; T4Opt: fax options; TW, TL: tile width and length
    SampleFmt: Integer;  // sample format (1 unsigned, 2 signed, 3 float)
    RowBytes: Integer;  // bytes in one row
    Offs, Cnts: TInt64Array;  // file offsets and sizes of strips or tiles
    CMap: TInt64Array;  // color map of palette files
    function U16(const B: array of Byte; O: Integer): Integer;
    function U32(const B: array of Byte; O: Integer): Int64;
    function Open(const FileName: string; out Err: string): Boolean;
    function TagIdx(Tag: Word): Integer;
    function TagVals(Tag: Word): TInt64Array;
    function TagInt(Tag: Word; Def: Integer): Integer;
    function ReadChunk(I: Integer; var Buf: TBytes): Boolean;
    function DecodeChunk(I, RowsN, Width, RB: Integer; var Dst: TBytes): Boolean;
  end;

{ Reads a 16-bit value in the byte order of the file. }
function TTiffReader.U16(const B: array of Byte; O: Integer): Integer;
begin
  if BE then Result := (B[O] shl 8) or B[O + 1] else Result := B[O] or (B[O + 1] shl 8);  // combine two bytes in the file's byte order
end;

{ Reads a 32-bit value in the byte order of the file. }
function TTiffReader.U32(const B: array of Byte; O: Integer): Int64;
begin
  if BE then
    Result := (Int64(B[O]) shl 24) or (Int64(B[O + 1]) shl 16) or (Int64(B[O + 2]) shl 8) or B[O + 3]  // big-endian combination
  else
    Result := B[O] or (Int64(B[O + 1]) shl 8) or (Int64(B[O + 2]) shl 16) or (Int64(B[O + 3]) shl 24);  // little-endian combination
end;

{ Returns the index of a tag in the directory, or -1. }
function TTiffReader.TagIdx(Tag: Word): Integer;
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to High(Tags) do  // search all tags
    if Tags[I].Tag = Tag then Exit(I);  // found
  Result := -1;  // not found
end;

{ Reads all values of a tag as 64-bit integers. }
function TTiffReader.TagVals(Tag: Word): TInt64Array;
var
  I, J, Sz, N: Integer;  // I: tag index; J: loop counter; Sz: bytes per value; N: number of values
  B: TBytes;  // B: raw bytes of the values
  Off: Int64;  // Off: file offset of the values
  Raw: array[0..3] of Byte;  // Raw: inline value bytes
begin
  Result := nil;  // nothing by default
  I := TagIdx(Tag);  // find the tag
  if I < 0 then Exit;  // tag not present
  case Tags[I].Typ of  // bytes per value by data type
    1, 2, 6, 7: Sz := 1;  // byte types
    3, 8: Sz := 2;  // 16-bit types
    4, 9: Sz := 4;  // 32-bit types
  else
    Exit;  // other types are not used
  end;
  N := Tags[I].Cnt;  // number of values
  if (N <= 0) or (Int64(N) * Sz > 64 * 1024 * 1024) then Exit;  // reject empty or huge tables
  B := nil;  // release any old array
  SetLength(B, N * Sz);  // reserve the raw bytes
  if N * Sz <= 4 then  // values fit in the entry itself
  begin
    for J := 0 to 3 do Raw[J] := Tags[I].Raw[J];  // copy the inline bytes
    Move(Raw[0], B[0], N * Sz);  // use them as the data
  end
  else
  begin
    Off := U32(Tags[I].Raw, 0);  // the entry holds an offset
    if Off + N * Sz > Strm.Size then Exit;  // values must lie inside the file
    Strm.Position := Off;  // go to the values
    Strm.ReadBuffer(B[0], N * Sz);  // read them
  end;
  SetLength(Result, N);  // reserve the result
  for J := 0 to N - 1 do  // convert every value
    case Sz of
      1: Result[J] := B[J];  // byte
      2: Result[J] := U16(B, J * 2);  // 16-bit
      4: Result[J] := U32(B, J * 4);  // 32-bit
    end;
end;

{ Returns the first value of a tag, or Def when it is missing. }
function TTiffReader.TagInt(Tag: Word; Def: Integer): Integer;
var
  V: TInt64Array;  // V: values of the tag
begin
  V := TagVals(Tag);  // read the values
  if Length(V) > 0 then Result := Integer(V[0]) else Result := Def;  // first value or the default
end;

{ Opens a TIFF file, reads the first directory and checks that the layout is supported. }
function TTiffReader.Open(const FileName: string; out Err: string): Boolean;
var
  Hd: array[0..7] of Byte;  // Hd: file header
  IfdOff: Int64;  // IfdOff: offset of the first directory
  Cnt: Integer;  // Cnt: number of directory entries
  Blk: TBytes;  // Blk: raw directory bytes
  I, O: Integer;  // I: loop counter; O: offset of the entry
  V: TInt64Array;  // V: values of a tag
begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file for reading
  if Strm.Size < 16 then  // too small to be a TIFF
  begin
    Err := 'file too small';
    Exit;
  end;
  {$PUSH}{$HINTS OFF}FillChar(Hd, SizeOf(Hd), 0);{$POP}  // clear the header
  Strm.ReadBuffer(Hd[0], 8);  // read the 8-byte header
  if (Hd[0] = Ord('I')) and (Hd[1] = Ord('I')) then BE := False  // II marks little-endian
  else if (Hd[0] = Ord('M')) and (Hd[1] = Ord('M')) then BE := True  // MM marks big-endian
  else
  begin
    Err := 'not a TIFF file';
    Exit;
  end;
  if U16(Hd, 2) <> 42 then  // 42 is the TIFF version
  begin
    Err := 'BigTIFF is not supported';
    Exit;
  end;
  IfdOff := U32(Hd, 4);  // offset of the first directory
  if (IfdOff < 8) or (IfdOff + 2 > Strm.Size) then  // the offset must be inside the file
  begin
    Err := 'bad directory offset';
    Exit;
  end;
  Strm.Position := IfdOff;  // go to the directory
  Blk := nil;  // release any old array
  SetLength(Blk, 2);  // room for the entry count
  Strm.ReadBuffer(Blk[0], 2);  // read the count
  Cnt := U16(Blk, 0);  // number of entries
  if (Cnt < 1) or (Cnt > 500) or (IfdOff + 2 + Cnt * 12 > Strm.Size) then  // reject an empty or huge directory
  begin
    Err := 'bad directory';
    Exit;
  end;
  SetLength(Blk, Cnt * 12);  // room for all entries
  Strm.ReadBuffer(Blk[0], Cnt * 12);  // read the entries
  SetLength(Tags, Cnt);  // reserve the tag list
  for I := 0 to Cnt - 1 do
  begin  // each entry has 12 bytes
    O := I * 12;
    Tags[I].Tag := U16(Blk, O);  // tag number
    Tags[I].Typ := U16(Blk, O + 2);  // data type
    Tags[I].Cnt := LongWord(U32(Blk, O + 4));  // value count
    Move(Blk[O + 8], Tags[I].Raw[0], 4);  // inline value or offset
  end;
  W := TagInt(256, 0);  // image width
  H := TagInt(257, 0);  // image height
  V := TagVals(258);  // bits per sample
  if Length(V) > 0 then Bps := Integer(V[0]) else Bps := 1;  // first value, or 1 bit
  Comp := TagInt(259, 1);  // compression, 1 = none
  Photo := TagInt(262, 1);  // photometric interpretation
  Fill := TagInt(266, 1);  // fill order
  Spp := TagInt(277, 1);  // samples per pixel
  Rps := TagInt(278, H);  // rows per strip
  Planar := TagInt(284, 1);  // planar configuration
  T4Opt := TagInt(292, 0);  // fax options
  Pred := TagInt(317, 1);  // predictor
  SampleFmt := TagInt(339, 1);  // sample format
  TW := TagInt(322, 0);  // tile width
  TL := TagInt(323, 0);  // tile length
  if (W <= 0) or (H <= 0) or (Int64(W) * H > 2000000000) then  // reject impossible sizes
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
  RowBytes := Integer((Int64(W) * Spp * Bps + 7) div 8);  // bytes per row
  if TagIdx(322) >= 0 then  // tile tags present
  begin
    if (TW <= 0) or (TL <= 0) then begin Err := 'bad tile size'; Exit; end;  // tile size needed
    Offs := TagVals(324);  // tile offsets
    Cnts := TagVals(325);  // tile sizes
  end
  else
  begin
    if Rps <= 0 then Rps := H;  // no strip size means one strip
    Offs := TagVals(273);  // strip offsets
    Cnts := TagVals(279);  // strip sizes
  end;
  if (Length(Offs) = 0) or (Length(Offs) <> Length(Cnts)) then  // both tables are needed and must match
  begin
    Err := 'missing strip or tile table';
    Exit;
  end;
  if Photo = 3 then  // palette picture
  begin
    CMap := TagVals(320);  // read the color map
    if Length(CMap) < 3 * (1 shl Bps) then begin Err := 'missing colour map'; Exit; end;  // needs 3 channels of 2^Bps entries
  end;
  Result := True;  // file accepted
end;

{ Reads the raw bytes of strip or tile I. }
function TTiffReader.ReadChunk(I: Integer; var Buf: TBytes): Boolean;
begin
  Result := False;  // assume failure
  if (I < 0) or (I >= Length(Offs)) then Exit;  // index out of range
  if (Cnts[I] <= 0) or (Cnts[I] > 400 * 1024 * 1024) or (Offs[I] + Cnts[I] > Strm.Size) then Exit;  // reject empty, huge or out of file chunks
  SetLength(Buf, Cnts[I]);  // reserve the buffer
  Strm.Position := Offs[I];  // go to the chunk
  Strm.ReadBuffer(Buf[0], Cnts[I]);  // read it
  Result := True;  // chunk read
end;

{ decodes strip or tile I (RowsN rows of Width pixels, RB bytes per row) }
function TTiffReader.DecodeChunk(I, RowsN, Width, RB: Integer; var Dst: TBytes): Boolean;
var
  Src: TBytes;  // Src: compressed bytes
  Expected, R, X, P, Base: Integer;  // Expected: size of the decoded data; R: row; X: sample; P: byte position; Base: start of the row
  V: Integer;  // V: sample value
begin
  Result := False;  // assume failure
  Expected := RowsN * RB;  // size of the decoded data
  Src := nil;  // release any old array
  if not ReadChunk(I, Src) then Exit;  // read the compressed chunk
  case Comp of
    1:  // no compression
      begin
        SetLength(Dst, Expected);  // reserve the output
        FillChar(Dst[0], Expected, 0);  // start with zeros
        Move(Src[0], Dst[0], Min(Expected, Length(Src)));  // copy what is available
        Result := True;  // done
      end;
    32773: Result := PackBitsDecode(Src, Expected, Dst);  // PackBits
    5: Result := LzwDecode(Src, Expected, Dst);  // LZW
    8, 32946: Result := InflateDecode(Src, Expected, Dst);  // Deflate
    2, 3, 4: Result := FaxDecode(Src, Comp, T4Opt, Fill, Width, RowsN, RB, Dst);  // fax compression
  end;
  if not Result then Exit;  // stop when decoding failed
  if (Pred = 2) and (Comp <> 2) and (Comp <> 3) and (Comp <> 4) then  // predictor 2 (horizontal differencing) for non-fax data
  begin
    for R := 0 to RowsN - 1 do  // every row
    begin
      Base := R * RB;  // start of the row
      if Bps = 8 then  // 8-bit samples
      begin
        for X := Spp to Width * Spp - 1 do  // add the sample one pixel to the left
          Dst[Base + X] := Byte(Dst[Base + X] + Dst[Base + X - Spp]);  // wrap around at 256
      end
      else if Bps = 16 then  // 16-bit samples
      begin
        for X := Spp to Width * Spp - 1 do
        begin
          P := Base + X * 2;  // byte position of the sample
          if BE then
            V := ((Dst[P] shl 8) or Dst[P + 1]) + ((Dst[P - 2 * Spp] shl 8) or Dst[P - 2 * Spp + 1])  // big-endian sum with the left neighbor
          else
            V := (Dst[P] or (Dst[P + 1] shl 8)) + (Dst[P - 2 * Spp] or (Dst[P - 2 * Spp + 1] shl 8));  // little-endian sum with the left neighbor
          V := V and $FFFF;  // wrap around at 65536
          if BE then
          begin
            Dst[P] := V shr 8;  // high byte first
            Dst[P + 1] := V and $FF;  // low byte
          end
          else
          begin
            Dst[P] := V and $FF;  // low byte first
            Dst[P + 1] := V shr 8;  // high byte
          end;
        end;
      end;
    end;
  end;
end;

{ ---- thumbnail ---- }

{ Reads a TIFF in strips and averages it down to at most MaxSide pixels; returns RGB bytes. }
function RenderTiff(const FileName: string; MaxSide: Integer; out OutW, OutH: Integer;
  out OutPix: TBytes; out Err: string): Boolean;
var
  T: TTiffReader;  // T: the TIFF reader
  NW, NH, X, Y, DY, CurDY, I, BandY0, BandRows, BandRB, AcrossT, DownT, TRB, R, Tx, Rn: Integer;  // NW, NH: thumbnail size; X, Y: pixels; DY, CurDY: destination row and the row being collected; I: strip index; BandY0: first row of the band; BandRows: rows in the band; BandRB: bytes per band row; AcrossT, DownT: tiles across and down; TRB: bytes per tile row; R: row; Tx: tile column; Rn: rows to decode
  Sc: Double;  // Sc: scale factor
  Band, Tile: TBytes;  // Band: decoded strip or tile row; Tile: one decoded tile
  ColMap: TIntArray;  // ColMap: destination column of each source column
  ColCnt: TIntArray;  // ColCnt: source columns per destination column
  Acc: array of Cardinal;  // Acc: color sums of the row being collected
  Pix: TBytes;  // Pix: finished RGB thumbnail
  RowCnt: Integer;  // RowCnt: source rows collected so far
  Row: PByte;  // Row: pointer to a source row
  Tiled: Boolean;  // True when the file uses tiles
  RV, GV, BV, Nc, K, Cc, Mc, Yc: Integer;  // RV, GV, BV: color channels; Nc: palette size; K, Cc, Mc, Yc: CMYK channels

  procedure EmitRow(DestY: Integer);
  var
    Dx, Dv, O: Integer;  // Dx: destination column; Dv: divisor; O: byte offset in the thumbnail
  begin
    for Dx := 0 to NW - 1 do  // every destination column
    begin
      Dv := ColCnt[Dx] * RowCnt;  // number of source pixels summed
      if Dv < 1 then Dv := 1;  // never divide by zero
      O := (DestY * NW + Dx) * 3;  // offset of the pixel
      Pix[O] := Byte(Acc[Dx * 3] div Cardinal(Dv));  // average red
      Pix[O + 1] := Byte(Acc[Dx * 3 + 1] div Cardinal(Dv));  // average green
      Pix[O + 2] := Byte(Acc[Dx * 3 + 2] div Cardinal(Dv));  // average blue
    end;
    FillChar(Acc[0], Length(Acc) * SizeOf(Cardinal), 0);  // clear the sums
    RowCnt := 0;  // start a new row
  end;

  procedure AddRow(P: PByte);
  var
    Xx, Dx, S0, Q: Integer;  // Xx: source column; Dx: destination column; S0: sample offset; Q: palette index or channel offset
    Vv: Integer;  // Vv: gray value
  begin
    case T.Photo of  // by photometric type
      0, 1:  // gray
        for Xx := 0 to T.W - 1 do  // every source column
        begin
          case T.Bps of
            1: Vv := ((P[Xx shr 3] shr (7 - (Xx and 7))) and 1) * 255;  // 1 bit per sample
            2: Vv := ((P[Xx shr 2] shr (6 - 2 * (Xx and 3))) and 3) * 85;  // 2 bits per sample
            4: Vv := ((P[Xx shr 1] shr (4 - 4 * (Xx and 1))) and 15) * 17;  // 4 bits per sample
            8: Vv := P[Xx * T.Spp];  // 8 bits per sample
          else
            if T.BE then Vv := P[Xx * T.Spp * 2] else Vv := P[Xx * T.Spp * 2 + 1];  // 16 bits: take the high byte
          end;
          if T.Photo = 0 then Vv := 255 - Vv;  // 0 means white is zero, so invert
          Dx := ColMap[Xx];  // destination column
          Inc(Acc[Dx * 3], Vv);  // add to red
          Inc(Acc[Dx * 3 + 1], Vv);  // add to green
          Inc(Acc[Dx * 3 + 2], Vv);  // add to blue
        end;
      3:
        begin
          Nc := 1 shl T.Bps;  // number of palette entries
          for Xx := 0 to T.W - 1 do  // every source column
          begin
            case T.Bps of
              1: Q := (P[Xx shr 3] shr (7 - (Xx and 7))) and 1;  // 1 bit per index
              2: Q := (P[Xx shr 2] shr (6 - 2 * (Xx and 3))) and 3;  // 2 bits per index
              4: Q := (P[Xx shr 1] shr (4 - 4 * (Xx and 1))) and 15;  // 4 bits per index
              8: Q := P[Xx * T.Spp];  // 8 bits per index
            else
              if T.BE then Q := (P[Xx * T.Spp * 2] shl 8) or P[Xx * T.Spp * 2 + 1]  // 16 bit index, big-endian
              else Q := P[Xx * T.Spp * 2] or (P[Xx * T.Spp * 2 + 1] shl 8);  // 16 bit index, little-endian
            end;
            if Q >= Nc then Q := Nc - 1;  // keep the index inside the palette
            Dx := ColMap[Xx];  // destination column
            Inc(Acc[Dx * 3], T.CMap[Q] shr 8);  // red from the color map
            Inc(Acc[Dx * 3 + 1], T.CMap[Nc + Q] shr 8);  // green from the color map
            Inc(Acc[Dx * 3 + 2], T.CMap[2 * Nc + Q] shr 8);  // blue from the color map
          end;
        end;
      2:  // RGB
        for Xx := 0 to T.W - 1 do  // every source column
        begin
          if T.Bps = 8 then  // 8 bits per channel
          begin
            S0 := Xx * T.Spp;  // offset of the pixel
            RV := P[S0]; GV := P[S0 + 1]; BV := P[S0 + 2];  // read the three channels
          end
          else
          begin
            S0 := Xx * T.Spp * 2;  // offset of the pixel
            if T.BE then Q := 0 else Q := 1;  // byte offset of the high byte
            RV := P[S0 + Q]; GV := P[S0 + 2 + Q]; BV := P[S0 + 4 + Q];  // read the high bytes of the three channels
          end;
          Dx := ColMap[Xx];  // destination column
          Inc(Acc[Dx * 3], RV);  // add to red
          Inc(Acc[Dx * 3 + 1], GV);  // add to green
          Inc(Acc[Dx * 3 + 2], BV);  // add to blue
        end;
      5:
        for Xx := 0 to T.W - 1 do  // CMYK
        begin
          S0 := Xx * T.Spp;  // offset of the pixel
          Cc := P[S0]; Mc := P[S0 + 1]; Yc := P[S0 + 2]; K := P[S0 + 3];  // read the four channels
          Dx := ColMap[Xx];  // destination column
          Inc(Acc[Dx * 3], (255 - Cc) * (255 - K) div 255);  // red from cyan and black
          Inc(Acc[Dx * 3 + 1], (255 - Mc) * (255 - K) div 255);  // green from magenta and black
          Inc(Acc[Dx * 3 + 2], (255 - Yc) * (255 - K) div 255);  // blue from yellow and black
        end;
    end;
  end;

begin
  Result := False;  // assume failure
  Err := '';  // no error yet
  T := TTiffReader.Create;  // create the reader
  try
    try
      if not T.Open(FileName, Err) then  // open and check the file
      begin
        if Err = '' then Err := 'unsupported TIFF layout';  // give a generic reason
        Exit;
      end;
      if Max(T.W, T.H) > MaxSide then Sc := MaxSide / Max(T.W, T.H) else Sc := 1;  // scale factor, never enlarge
      NW := Max(1, Round(T.W * Sc));  // thumbnail width
      NH := Max(1, Round(T.H * Sc));  // thumbnail height
      ColMap := nil;  // release any old array
      SetLength(ColMap, T.W);  // one entry per source column
      ColCnt := nil;  // release any old array
      SetLength(ColCnt, NW);  // one entry per destination column
      for X := 0 to T.W - 1 do  // every source column
      begin
        ColMap[X] := Integer((Int64(X) * NW) div T.W);  // destination column of the source column
        Inc(ColCnt[ColMap[X]]);  // count the source columns
      end;
      Acc := nil;  // release any old array
      SetLength(Acc, NW * 3);  // three sums per destination column
      FillChar(Acc[0], Length(Acc) * SizeOf(Cardinal), 0);  // start at zero
      Pix := nil;  // release any old array
      SetLength(Pix, NW * NH * 3);  // three bytes per thumbnail pixel
      FillChar(Pix[0], Length(Pix), 255);  // start white
      Tiled := T.TagIdx(322) >= 0;  // tile layout
      BandY0 := 0;  // the band starts at the top
      BandRows := 0;  // no rows decoded yet
      BandRB := T.RowBytes;  // bytes per strip row
      TRB := 0;  // no tiles yet
      AcrossT := 0;  // no tiles yet
      DownT := 0;  // no tiles yet
      if Tiled then
      begin
        AcrossT := (T.W + T.TW - 1) div T.TW;  // tiles across
        DownT := (T.H + T.TL - 1) div T.TL;  // tiles down
        TRB := Integer((Int64(T.TW) * T.Spp * T.Bps + 7) div 8);  // bytes per tile row
        BandRB := TRB * AcrossT;  // bytes per row of a row of tiles
        if Length(T.Offs) < AcrossT * DownT then  // all tiles must have an offset
        begin
          Err := 'missing tiles';  // stop with a reason
          Exit;
        end;
      end;
      CurDY := 0;  // first destination row
      RowCnt := 0;  // no rows collected yet
      Y := 0;  // start at the top
      while Y < T.H do  // every source row
      begin
        if Y >= BandY0 + BandRows then  // row is outside the decoded band
        begin
          // next strip, or next row of tiles
          if Tiled then
          begin
            Rn := Min(T.TL, T.H - Y);  // rows in this row of tiles
            if Int64(BandRB) * Rn > 800 * 1024 * 1024 then begin Err := 'strip too large'; Exit; end;  // refuse bands that are too large
            Band := nil;
            SetLength(Band, BandRB * Rn);  // reserve the band
            FillChar(Band[0], Length(Band), 0);  // start with zeros
            for Tx := 0 to AcrossT - 1 do  // every tile in the row
            begin
              Tile := nil;  // release any old array
              if not T.DecodeChunk((Y div T.TL) * AcrossT + Tx, T.TL, T.TW, TRB, Tile) then  // decode the tile
              begin
                Err := 'tile could not be decoded';  // stop with a reason
                Exit;
              end;
              for R := 0 to Rn - 1 do  // every row of the tile
                Move(Tile[R * TRB], Band[R * BandRB + Tx * TRB], TRB);  // copy the row into the band
            end;
            BandY0 := Y;  // band starts here
            BandRows := Rn;  // number of rows in the band
          end
          else
          begin
            Rn := Min(T.Rps, T.H - Y);  // rows in this strip
            if Int64(BandRB) * Rn > 800 * 1024 * 1024 then begin Err := 'strip too large'; Exit; end;  // refuse strips that are too large
            I := Y div T.Rps;  // strip number
            if I >= Length(T.Offs) then begin Err := 'missing strip'; Exit; end;  // the strip must exist
            if not T.DecodeChunk(I, Rn, T.W, BandRB, Band) then  // decode the strip
            begin
              Err := 'strip could not be decoded (compression ' + IntToStr(T.Comp) + ')';  // stop with a reason
              Exit;
            end;
            BandY0 := I * T.Rps;  // first row of the strip
            BandRows := Rn;  // number of rows in the strip
            if BandY0 < Y then
            begin
              // cannot happen with a regular strip table; guard against odd files
              BandY0 := Y;
            end;
          end;
        end;
        DY := Integer((Int64(Y) * NH) div T.H);  // destination row of this source row
        if DY <> CurDY then  // moved to a new destination row
        begin
          EmitRow(CurDY);  // write the finished row
          CurDY := DY;  // collect the next row
        end;
        Row := @Band[(Y - BandY0) * BandRB];  // pointer to the source row
        AddRow(Row);  // add it to the sums
        Inc(RowCnt);  // count the row
        Inc(Y);  // next source row
      end;
      EmitRow(CurDY);  // write the last row

      OutW := NW;  // return the width
      OutH := NH;  // return the height
      OutPix := Pix;  // return the pixels
      Result := True;  // success
    except
      on E: Exception do
      begin
        Err := E.ClassName + ' ' + E.Message;  // report the error
        Result := False;  // failure
      end;
    end;
  finally
    T.Strm.Free;  // close the file
    T.Free;  // free the reader
  end;
end;

{ Builds a thumbnail bitmap from a TIFF file; False with a reason in Err when it cannot be read. }
function LoadTiffThumb(const FileName: string; MaxSide: Integer; Bmp: TBitmap;
  out Err: string): Boolean;
var
  NW, NH, X, Y, I, LineLen: Integer;  // NW, NH: thumbnail size; X, Y: pixels; I: byte offset; LineLen: bytes per BMP line
  Pix, Line: TBytes;  // Pix: RGB pixels; Line: one BMP line
  Ms: TMemoryStream;  // Ms: BMP built in memory
  FH: TBmpFileHdr;  // FH: BMP file header
  IH: TBmpInfoHdr;  // IH: BMP info header
begin
  Result := False;  // assume failure
  if not RenderTiff(FileName, MaxSide, NW, NH, Pix, Err) then Exit;  // render the picture
  try
    // 24-bit bottom-up BMP, stored as B,G,R
    LineLen := ((NW * 3 + 3) div 4) * 4;  // BMP lines are padded to 4 bytes
    Line := nil;  // release any old array
    SetLength(Line, LineLen);  // reserve one line
    FH.bfType := $4D42;  // BM signature
    FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;  // file size
    FH.bfReserved := 0;  // reserved, must be zero
    FH.bfOffBits := SizeOf(FH) + SizeOf(IH);  // where the pixels start
    IH.biSize := SizeOf(IH);  // size of the info header
    IH.biWidth := NW;  // width
    IH.biHeight := NH;  // height
    IH.biPlanes := 1;  // one plane
    IH.biBitCount := 24;  // 24 bits per pixel
    IH.biCompression := 0;  // no compression
    IH.biSizeImage := LineLen * NH;  // size of the pixel data
    IH.biXPels := 2835;  // horizontal resolution (72 dpi)
    IH.biYPels := 2835;  // vertical resolution (72 dpi)
    IH.biClrUsed := 0;  // no palette
    IH.biClrImportant := 0;  // all colors important
    Ms := TMemoryStream.Create;  // stream for the BMP
    try
      Ms.WriteBuffer(FH, SizeOf(FH));  // write the file header
      Ms.WriteBuffer(IH, SizeOf(IH));  // write the info header
      for Y := NH - 1 downto 0 do  // BMP stores the bottom line first
      begin
        FillChar(Line[0], LineLen, 0);  // clear the padding
        for X := 0 to NW - 1 do
        begin
          I := (Y * NW + X) * 3;  // offset of the source pixel
          Line[X * 3] := Pix[I + 2];        // blue
          Line[X * 3 + 1] := Pix[I + 1];    // green
          Line[X * 3 + 2] := Pix[I];        // red
        end;
        Ms.WriteBuffer(Line[0], LineLen);
      end;
      Ms.Position := 0;  // rewind
      Bmp.LoadFromStream(Ms);  // let the bitmap read it
    finally
      Ms.Free;
    end;
    Result := (Bmp.Width > 0) and (Bmp.Height > 0);  // success when the picture is not empty
    if not Result then Err := 'empty picture';  // reason for failure
  except
    on E: Exception do
    begin
      Err := E.ClassName + ' ' + E.Message;  // report the error
      Result := False;  // failure
    end;
  end;
end;

{ Builds a memory image from a TIFF file for the viewer; nil when it cannot be read. }
function LoadTiffMemImageAny(const FileName: string; Target: Integer; out Err: string): TFPMemoryImage;
var
  NW, NH, X, Y, I: Integer;  // NW, NH: image size; X, Y: pixels; I: byte offset
  Pix: TBytes;  // Pix: RGB pixels
  Img: TFPMemoryImage;  // Img: the new image
  C: TFPColor;  // C: color of one pixel
begin
  Result := nil;  // nothing by default
  if not RenderTiff(FileName, Target, NW, NH, Pix, Err) then Exit;  // render the picture
  try
    Img := TFPMemoryImage.Create(NW, NH);  // image of the right size
    try
      for Y := 0 to NH - 1 do
        for X := 0 to NW - 1 do  // every column
        begin
          I := (Y * NW + X) * 3;  // offset of the source pixel
          C.Red := Word(Pix[I] * 257);  // red scaled to 16 bits
          C.Green := Word(Pix[I + 1] * 257);  // green scaled to 16 bits
          C.Blue := Word(Pix[I + 2] * 257);  // blue scaled to 16 bits
          C.Alpha := $FFFF;  // fully opaque
          Img.Colors[X, Y] := C;  // set the pixel
        end;
      Result := Img;  // hand over the image
      Img := nil;  // do not free it below
    finally
      Img.Free;
    end;
  except
    on E: Exception do
    begin
      Err := E.ClassName + ' ' + E.Message;  // report the error
      Result := nil;  // nothing
    end;
  end;
end;

initialization
  InitFax;  // build the fax tables at start

end.
