unit uRotate;

{$mode objfpc}{$H+}

{ Lossless JPEG rotation for "Auto-rotate JPEGs after downloading".

  The picture is turned according to the EXIF Orientation tag by working on the
  quantised DCT coefficients (like jpegtran): nothing is decoded to pixels, so no
  picture quality is lost. The result is written with the standard Huffman tables.
  As jpegtran -trim does, up to 15 pixel rows/columns that do not fill a complete
  block are dropped on the edge that ends up mirrored.

  Supported: baseline/extended sequential and progressive JPEG, 8 bit, 1 or 3 components,
  restart markers. A progressive file is written back as a sequential file (same picture,
  slightly different file size). Anything else (CMYK, arithmetic coding, 12 bit, ...) is left untouched. }

interface

{ Returns 1 = rotated, 0 = nothing to do (no EXIF orientation or already upright),
  -1 = not possible (the file is left unchanged). }
function AutoRotateJpegFile(const FileName: string): Integer;

{ Display helpers for the EXIF orientation values 2..8: size of the turned picture and where
  the pixel (X, Y) of a W x H picture ends up. }
procedure OrientDims(Orient, W, H: Integer; out NW, NH: Integer);
{ Gives the new position of a pixel after the orientation is applied. }
procedure OrientPoint(Orient, W, H, X, Y: Integer; out NX, NY: Integer);

var
  { Why the last AutoRotateJpegFile call returned -1 (empty when it did not) }
  RotateLastError: string = '';  // reason of the last failure

implementation

uses
  Classes, SysUtils, LazFileUtils;

const
  ZZ: array[0..63] of Byte = (  // zigzag order of the 64 coefficients
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63);
  DcLumBits: array[0..15] of Byte = (  // standard luminance DC code lengths
    0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0);
  DcLumVals: array[0..11] of Byte = (  // standard luminance DC values
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  DcChrBits: array[0..15] of Byte = (  // standard chrominance DC code lengths
    0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0);
  DcChrVals: array[0..11] of Byte = (  // standard chrominance DC values
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  AcLumBits: array[0..15] of Byte = (  // standard luminance AC code lengths
    0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125);
  AcLumVals: array[0..161] of Byte = (  // standard luminance AC values
    1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7,
    34, 113, 20, 50, 129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209, 240,
    36, 51, 98, 114, 130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40,
    41, 42, 52, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73,
    74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105,
    106, 115, 116, 117, 118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137,
    138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167,
    168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197,
    198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226,
    227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244, 245, 246, 247, 248,
    249, 250);
  AcChrBits: array[0..15] of Byte = (  // standard chrominance AC code lengths
    0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119);
  AcChrVals: array[0..161] of Byte = (  // standard chrominance AC values
    0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113,
    19, 34, 50, 129, 8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240,
    21, 98, 114, 209, 10, 22, 36, 52, 225, 37, 241, 23, 24, 25, 26, 38,
    39, 40, 41, 42, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72,
    73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104,
    105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135,
    136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165,
    166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195,
    196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218,
    226, 227, 228, 229, 230, 231, 232, 233, 234, 242, 243, 244, 245, 246, 247, 248,
    249, 250);

type
  EJpegRot = class(Exception);  // error raised for files that cannot be rotated

  { Huffman decoding table. }
  THuffDec = record
    MinC, MaxC, Ptr: array[1..16] of Integer;  // MinC, MaxC: smallest and largest code per length; Ptr: index of the first value per length
    Vals: array[0..255] of Byte;  // symbol values
    Ok: Boolean;  // True when the table was defined
  end;

  { Huffman encoding table. }
  THuffEnc = record
    Code: array[0..255] of Cardinal;  // code of each symbol
    Len: array[0..255] of Byte;  // bit length of each symbol
  end;

  TCoefs = array of SmallInt;  // list of DCT coefficients

  { One color component of the picture. }
  TComp = record
    Id, H, V, Tq, Bw, Bh, Td, Ta: Integer;  // Id: component number; H, V: sampling factors; Tq: quantization table; Bw, Bh: blocks across and down; Td, Ta: DC and AC table numbers
    Coef: TCoefs;                   // ((Y * Bw + X) * 64) + natural coefficient index
  end;

  { One marker segment of the file. }
  TSeg = record
    Marker: Byte;  // marker code
    Data: TBytes;  // segment bytes
  end;

  { TBitReader }
  TBitReader = class
  public
    D: TBytes;  // scan data
    Pos: Integer;  // read position
    Acc, Cnt: Integer;  // Acc: bit accumulator; Cnt: bits left in it
    function GetBit: Integer;
    function GetBits(K: Integer): Integer;
    function Decode(const T: THuffDec): Integer;
    procedure Restart;
  end;

  { TBitWriter }
  TBitWriter = class
  public
    Strm: TMemoryStream;  // output stream
    Acc, Cnt: Integer;  // Acc: bit accumulator; Cnt: bits collected
    procedure Put(Code: Cardinal; Len: Integer);
    procedure Finish;
  end;

{ Reads one bit from the scan data. }
function TBitReader.GetBit: Integer;
var
  B: Integer;  // B: next byte
begin
  if Cnt = 0 then  // accumulator is empty
  begin
    if Pos >= Length(D) then raise EJpegRot.Create('end of data');  // no more data
    B := D[Pos];  // take the next byte
    if B = $FF then  // an FF byte is followed by a stuffed zero
    begin
      if Pos + 1 >= Length(D) then raise EJpegRot.Create('end of data');  // no more data
      if D[Pos + 1] = 0 then
        Inc(Pos, 2)  // skip the stuffed zero
      else
        raise EJpegRot.Create('marker inside scan data');  // a real marker ends the scan
    end
    else
      Inc(Pos);  // plain byte
    Acc := B;  // load the accumulator
    Cnt := 8;  // eight bits available
  end;
  Dec(Cnt);  // use one bit
  Result := (Acc shr Cnt) and 1;  // return the top remaining bit
end;

{ Reads K bits, most significant first. }
function TBitReader.GetBits(K: Integer): Integer;
var
  I: Integer;  // I: loop counter
begin
  Result := 0;  // start with zero
  for I := 1 to K do Result := (Result shl 1) or GetBit;  // shift in the bits
end;

{ Decodes one Huffman symbol. }
function TBitReader.Decode(const T: THuffDec): Integer;
var
  L, Code: Integer;  // L: code length; Code: bits read so far
begin
  Code := 0;  // no bits yet
  for L := 1 to 16 do  // try increasing lengths
  begin
    Code := (Code shl 1) or GetBit;  // add one bit
    if (T.MaxC[L] >= 0) and (Code <= T.MaxC[L]) and (Code >= T.MinC[L]) then  // code falls into the range of this length
    begin
      Result := T.Vals[T.Ptr[L] + Code - T.MinC[L]];  // look up the symbol
      Exit;
    end;
  end;
  raise EJpegRot.Create('bad Huffman code');  // no length matched
end;

{ Skips to the byte after the next restart marker and clears the bit buffer. }
procedure TBitReader.Restart;
begin
  Cnt := 0;  // discard the partial byte
  while (Pos < Length(D)) and (D[Pos] <> $FF) do Inc(Pos);  // skip to the next FF
  while (Pos < Length(D)) and (D[Pos] = $FF) do Inc(Pos);  // skip FF fill bytes
  Inc(Pos);                          // the RSTn marker byte
end;

{ Writes the lowest Len bits of Code, with byte stuffing. }
procedure TBitWriter.Put(Code: Cardinal; Len: Integer);
var
  I: Integer;  // I: bit index
  B: Byte;  // B: byte to write
begin
  for I := Len - 1 downto 0 do  // from the highest bit down
  begin
    Acc := (Acc shl 1) or Integer((Code shr I) and 1);  // append a bit
    Inc(Cnt);  // one more bit collected
    if Cnt = 8 then  // a byte is complete
    begin
      B := Acc and $FF;  // take the byte
      Strm.WriteBuffer(B, 1);  // write it
      if B = $FF then  // FF must be followed by a zero byte
      begin
        B := 0;  // stuffing byte
        Strm.WriteBuffer(B, 1);  // write it
      end;
      Acc := 0;  // empty the accumulator
      Cnt := 0;  // no bits left
    end;
  end;
end;

{ Pads the last byte with one bits. }
procedure TBitWriter.Finish;
begin
  while Cnt <> 0 do Put(1, 1);  // add one bits until a byte is complete
end;

{ Returns the number of bits needed to store V. }
function BitCount(V: Integer): Integer;
begin
  Result := 0;  // start with zero bits
  while V > 0 do  // while V is not zero
  begin
    Inc(Result);  // count a bit
    V := V shr 1;  // drop the lowest bit
  end;
end;

{ Builds a decoding table from the code lengths and values of a DHT segment. }
procedure BuildDec(var T: THuffDec; const B: TBytes; BitsPos, ValsPos, N: Integer);
var
  L, K, Code, C, I: Integer;  // L: code length; K: value index; Code: current code; C: codes of this length; I: loop counter
begin
  if (N > 256) or (ValsPos + N > Length(B)) then raise EJpegRot.Create('bad DHT');  // segment too short
  Code := 0;  // first code is zero
  K := 0;  // no values yet
  for L := 1 to 16 do  // every code length
  begin
    C := B[BitsPos + L - 1];  // number of codes of this length
    T.Ptr[L] := K;  // index of the first value of this length
    T.MinC[L] := Code;  // smallest code of this length
    Inc(Code, C);  // next free code
    Inc(K, C);  // values used so far
    if C > 0 then T.MaxC[L] := Code - 1 else T.MaxC[L] := -1;  // largest code of this length, or -1 when none
    Code := Code shl 1;  // codes grow by one bit
  end;
  for I := 0 to 255 do T.Vals[I] := 0;  // clear the values
  for I := 0 to N - 1 do T.Vals[I] := B[ValsPos + I];  // copy the values
  T.Ok := True;  // table is ready
end;

{ Builds an encoding table from code lengths and values. }
procedure BuildEnc(var E: THuffEnc; const Bits: array of Byte; const Vals: array of Byte);
var
  L, I, K: Integer;  // L: code length; I: loop counter; K: value index
  Code: Cardinal;  // current code
begin
  for I := 0 to 255 do  // clear every symbol
  begin
    E.Code[I] := 0;  // no code
    E.Len[I] := 0;  // no length
  end;
  Code := 0;  // first code is zero
  K := 0;  // first value
  for L := 1 to 16 do  // every code length
  begin
    for I := 1 to Bits[L - 1] do  // every code of this length
    begin
      E.Code[Vals[K]] := Code;  // code of the symbol
      E.Len[Vals[K]] := L;  // length of the symbol
      Inc(Code);  // next code
      Inc(K);  // next value
    end;
    Code := Code shl 1;  // codes grow by one bit
  end;
end;

{ Gives the size of the picture after the orientation is applied. }
procedure OrientDims(Orient, W, H: Integer; out NW, NH: Integer);
begin
  if Orient in [5, 6, 7, 8] then  // orientations 5 to 8 swap width and height
  begin
    NW := H;  // new width is the old height
    NH := W;  // new height is the old width
  end
  else
  begin
    NW := W;  // same width
    NH := H;  // same height
  end;
end;

{ Gives the new position of a pixel after the orientation is applied. }
procedure OrientPoint(Orient, W, H, X, Y: Integer; out NX, NY: Integer);
begin
  case Orient of
    2: begin NX := W - 1 - X; NY := Y; end;          // mirror left-right
    3: begin NX := W - 1 - X; NY := H - 1 - Y; end;  // turn 180
    4: begin NX := X; NY := H - 1 - Y; end;          // mirror top-bottom
    5: begin NX := Y; NY := X; end;                  // transpose
    6: begin NX := H - 1 - Y; NY := X; end;          // turn 90 clockwise
    7: begin NX := H - 1 - Y; NY := W - 1 - X; end;  // transverse
    8: begin NX := Y; NY := W - 1 - X; end;          // turn 90 counter-clockwise
  else
    begin NX := X; NY := Y; end;
  end;
end;

{ ---- the JPEG being turned ---- }

type
  TRotator = class
  public
    D: TBytes;  // whole file
    Segs: array of TSeg;  // marker segments before the scan
    Dqt: array[0..3, 0..63] of Byte;  // quantization tables
    HaveDqt: array[0..3] of Boolean;  // which tables are defined
    Dht: array[0..1, 0..3] of THuffDec;  // Huffman tables (DC and AC)
    Dri, W, H, NComp, DataPos, NScan: Integer;  // Dri: restart interval; W, H: picture size; NComp: number of components; DataPos: start of the scan data; NScan: number of scans
    Comp: array[0..2] of TComp;  // the color components
    ScanId, ScanTd, ScanTa: array[0..2] of Integer;  // component ids and table numbers of the current scan
    HaveSof, Progressive: Boolean;  // HaveSof: frame header found; Progressive: progressive coding
    { Reads the EXIF orientation of the picture. }
    function Orientation: Integer;
    { Reads all marker segments. }
    procedure Parse;
    { Decodes the coefficients of a sequential file. }
    procedure DecodeScan;
    { Decodes the coefficients of a progressive file. }
    procedure DecodeProgressive;
    { Moves the coefficients according to the orientation. }
    procedure Transform(Orient: Integer; out Transposed: Boolean);
    { Writes the rotated picture with standard Huffman tables. }
    procedure Encode(Dest: TStream; Transposed: Boolean);
  private
    { Changes the orientation tag to 1 in the segment data. }
    procedure PatchOrientation(var Data: TBytes);
    { Swaps the block rows and columns. }
    procedure Transpose;
    { Drops the incomplete blocks at the right edge. }
    procedure CutColumns(NewW: Integer);
    { Drops the incomplete blocks at the bottom edge. }
    procedure CutRows(NewH: Integer);
    { Mirrors the picture left to right. }
    procedure FlipH;
    { Mirrors the picture top to bottom. }
    procedure FlipV;
    { Largest horizontal sampling factor. }
    function HMax: Integer;
    { Largest vertical sampling factor. }
    function VMax: Integer;
  end;

{ Reads a big-endian 16-bit value from B at position P. }
function U16At(const B: TBytes; P: Integer): Integer;
begin
  Result := (B[P] shl 8) or B[P + 1];  // combine high and low byte
end;

{ Writes a marker segment (marker, length, data) to a stream. }
procedure WriteSeg(S: TStream; Marker: Byte; const Data: array of Byte; Len: Integer);
var
  M: array[0..3] of Byte;  // M: marker and length bytes
begin
  M[0] := $FF;  // marker prefix
  M[1] := Marker;  // marker code
  M[2] := (Len + 2) shr 8;  // high byte of the length (includes the length field)
  M[3] := (Len + 2) and $FF;  // low byte of the length
  S.WriteBuffer(M, 4);  // write the four header bytes
  if Len > 0 then S.WriteBuffer(Data[0], Len);  // write the data
end;

{ finds the Orientation tag in an EXIF APP1 segment; returns its value (0 if absent) and,
  when Patch is True, sets it to 1 }
function ExifOrientation(var Data: TBytes; Patch: Boolean): Integer;
var
  T, Off, N, I, X: Integer;  // T: start of the TIFF header; Off: offset of the first directory; N: entry count; I: loop counter; X: offset of the entry
  Big: Boolean;  // True for big-endian data

  function R16(P: Integer): Integer;
  begin
    if (P < 0) or (P + 2 > Length(Data)) then Exit(0);  // outside the data
    if Big then Result := (Data[P] shl 8) or Data[P + 1] else Result := Data[P] or (Data[P + 1] shl 8);  // read 16 bits in the right byte order
  end;

  function R32(P: Integer): Integer;
  begin
    if (P < 0) or (P + 4 > Length(Data)) then Exit(0);  // outside the data
    if Big then
      Result := (Data[P] shl 24) or (Data[P + 1] shl 16) or (Data[P + 2] shl 8) or Data[P + 3]  // big-endian value
    else
      Result := Data[P] or (Data[P + 1] shl 8) or (Data[P + 2] shl 16) or (Data[P + 3] shl 24);  // little-endian value
  end;

begin
  Result := 0;  // 0 means no orientation found
  if (Length(Data) < 14) or (Data[0] <> Ord('E')) or (Data[1] <> Ord('x')) or  // must start with the Exif identifier
     (Data[2] <> Ord('i')) or (Data[3] <> Ord('f')) or (Data[4] <> 0) or (Data[5] <> 0) then Exit;
  T := 6;  // TIFF header starts after "Exif" and two zero bytes
  Big := (Data[T] = $4D) and (Data[T + 1] = $4D);  // MM marks big-endian
  if (not Big) and not ((Data[T] = $49) and (Data[T + 1] = $49)) then Exit;  // anything but II is invalid
  Off := R32(T + 4);  // offset of the first directory
  if (Off < 8) or (Off > 65536) then Exit;  // reject silly offsets
  N := R16(T + Off);  // number of entries
  if N > 300 then N := 300;  // limit the number of entries
  for I := 0 to N - 1 do  // look at every entry
  begin
    X := T + Off + 2 + I * 12;  // offset of this 12-byte entry
    if X + 12 > Length(Data) then Break;  // entry outside the data
    if R16(X) = $0112 then  // tag 0x0112 is the orientation
    begin
      Result := R16(X + 8);  // the value sits at offset 8 of the entry
      if Patch then  // only write when asked to
        if Big then
        begin
          Data[X + 8] := 0;  // big-endian value 1, high byte
          Data[X + 9] := 1;  // big-endian value 1, low byte
        end
        else
        begin
          Data[X + 8] := 1;  // little-endian value 1, low byte
          Data[X + 9] := 0;  // little-endian value 1, high byte
        end;
      Exit;
    end;
  end;
end;

function TRotator.Orientation: Integer;
var
  I: Integer;  // I: loop counter
begin
  Result := 0;  // no orientation yet
  for I := 0 to High(Segs) do  // look at all segments
    if Segs[I].Marker = $E1 then  // APP1 segments may hold EXIF
    begin
      Result := ExifOrientation(Segs[I].Data, False);  // read the orientation
      if Result <> 0 then Exit;  // stop at the first one found
    end;
end;

procedure TRotator.PatchOrientation(var Data: TBytes);
begin
  ExifOrientation(Data, True);  // set the orientation to 1 (upright)
end;

function TRotator.HMax: Integer;
var
  I: Integer;  // I: loop counter
begin
  Result := 1;  // at least 1
  for I := 0 to NComp - 1 do
    if Comp[I].H > Result then Result := Comp[I].H;  // keep the largest factor
end;

function TRotator.VMax: Integer;
var
  I: Integer;  // I: loop counter
begin
  Result := 1;  // at least 1
  for I := 0 to NComp - 1 do
    if Comp[I].V > Result then Result := Comp[I].V;  // keep the largest factor
end;

{ Reads the marker segments up to the first scan header. }
procedure TRotator.Parse;
var
  P, M, L, Q, I, N, Tc, Th, Pq, Tq, Ns: Integer;  // P: position; M: marker; L: segment length; Q: position inside the segment; I: loop counter; N: number of symbols; Tc: table class; Th: table number; Pq: precision; Tq: table number; Ns: components in the scan
  Body: Integer;  // Body: start of the segment data
  S: TSeg;  // S: segment copy
begin
  if (Length(D) < 4) or (D[0] <> $FF) or (D[1] <> $D8) then raise EJpegRot.Create('not a JPEG');  // must start with the SOI marker
  P := 2;  // first marker follows SOI
  Dri := 0;  // no restart interval yet
  NComp := 0;  // no components yet
  HaveSof := False;  // no frame header yet
  Progressive := False;  // assume sequential coding
  for I := 0 to 3 do HaveDqt[I] := False;  // no quantization tables yet
  for Tc := 0 to 1 do  // no Huffman tables yet
    for Th := 0 to 3 do Dht[Tc, Th].Ok := False;  // mark the table as undefined
  while True do
  begin
    if P + 4 > Length(D) then raise EJpegRot.Create('truncated');  // a marker needs at least four bytes
    if D[P] <> $FF then raise EJpegRot.Create('bad marker');  // every marker starts with FF
    M := D[P + 1];  // marker code
    if M = $FF then  // FF fill bytes
    begin
      Inc(P);  // skip the fill byte
      Continue;
    end;
    L := U16At(D, P + 2);  // segment length
    Body := P + 4;  // start of the segment data
    if (L < 2) or (P + 2 + L > Length(D)) then raise EJpegRot.Create('bad segment');  // length must fit in the file
    if ((M >= $E0) and (M <= $EF)) or (M = $FE) then  // APPn and comment segments are kept
    begin
      S.Marker := M;  // remember the marker
      SetLength(S.Data, L - 2);  // reserve the data
      if L > 2 then Move(D[Body], S.Data[0], L - 2);  // copy the data
      SetLength(Segs, Length(Segs) + 1);  // add a segment to the list
      Segs[High(Segs)] := S;  // store it
    end
    else if M = $DB then  // quantization table
    begin
      Q := Body;  // first table in the segment
      while Q < P + 2 + L do
      begin
        Pq := D[Q] shr 4;  // precision (0 = 8 bit)
        Tq := D[Q] and 15;  // table number
        Inc(Q);  // move past the table header
        if (Pq <> 0) or (Tq > 3) or (Q + 64 > P + 2 + L) then raise EJpegRot.Create('unsupported DQT');  // only 8-bit tables are supported
        Move(D[Q], Dqt[Tq, 0], 64);  // copy the 64 values
        HaveDqt[Tq] := True;  // remember that the table exists
        Inc(Q, 64);  // move to the next table
      end;
    end
    else if (M = $C0) or (M = $C1) or (M = $C2) then  // frame header (baseline, extended or progressive)
    begin
      Progressive := (M = $C2);  // C2 means progressive
      if D[Body] <> 8 then raise EJpegRot.Create('not 8 bit');  // only 8-bit samples are supported
      H := U16At(D, Body + 1);  // picture height
      W := U16At(D, Body + 3);  // picture width
      NComp := D[Body + 5];  // number of components
      if not (NComp in [1, 3]) or (H = 0) or (W = 0) then raise EJpegRot.Create('unsupported layout');  // only gray or three-component files are supported
      for I := 0 to NComp - 1 do
      begin
        Comp[I].Id := D[Body + 6 + I * 3];  // component id
        Comp[I].H := D[Body + 7 + I * 3] shr 4;  // horizontal sampling factor
        Comp[I].V := D[Body + 7 + I * 3] and 15;  // vertical sampling factor
        Comp[I].Tq := D[Body + 8 + I * 3];  // quantization table number
        if (Comp[I].H < 1) or (Comp[I].H > 4) or (Comp[I].V < 1) or (Comp[I].V > 4) or
           (Comp[I].Tq > 3) then raise EJpegRot.Create('unsupported sampling');
      end;
      HaveSof := True;
    end
    else if (M = $C3) or ((M >= $C5) and (M <= $CF) and (M <> $C8) and (M <> $CC) and (M <> $C4)) then  // arithmetic coding, lossless and other types are not supported
      raise EJpegRot.Create('unsupported JPEG type')
    else if M = $C4 then  // Huffman table definition
    begin
      Q := Body;  // first table in the segment
      while Q + 17 <= P + 2 + L do
      begin
        Tc := D[Q] shr 4;  // table class (0 DC, 1 AC)
        Th := D[Q] and 15;  // table number
        N := 0;  // total number of symbols
        for I := 0 to 15 do Inc(N, D[Q + 1 + I]);  // add up the code counts
        if (Tc > 1) or (Th > 3) then raise EJpegRot.Create('unsupported DHT');
        BuildDec(Dht[Tc, Th], D, Q + 1, Q + 17, N);  // build the decoding table
        Inc(Q, 17 + N);  // move to the next table
      end;
    end
    else if M = $DD then
      Dri := U16At(D, Body)  // restart interval
    else if M = $DA then  // start of scan
    begin
      if not HaveSof then raise EJpegRot.Create('no frame header');  // a scan needs a frame header
      Ns := D[Body];  // number of components in the scan
      if Progressive then
      begin
        DataPos := P;                // DecodeProgressive starts at this scan header
        Exit;
      end;
      if Ns <> NComp then raise EJpegRot.Create('several scans');  // a sequential file needs a single scan
      NScan := Ns;  // remember the component count
      for I := 0 to Ns - 1 do
      begin
        ScanId[I] := D[Body + 1 + I * 2];  // component id
        ScanTd[I] := D[Body + 2 + I * 2] shr 4;  // DC table number
        ScanTa[I] := D[Body + 2 + I * 2] and 15;  // AC table number
        if (ScanTd[I] > 3) or (ScanTa[I] > 3) then raise EJpegRot.Create('bad scan');
      end;
      DataPos := P + 2 + L;  // scan data starts after the header
      Exit;
    end;
    P := P + 2 + L;  // go to the next segment
  end;
end;

{ Decodes all blocks of a sequential file into the coefficient arrays. }
procedure TRotator.DecodeScan;
var
  Mw, Mh, McuX, McuY, MX, MY, CI, VI, HI, I, K, Si, T, R, S, Base, Count: Integer;  // Mw, Mh: size of an MCU in pixels; McuX, McuY: MCUs across and down; MX, MY: MCU position; CI: component; VI, HI: block inside the MCU; I: loop counter; K: coefficient index; Si: scan component; T: DC size; R: zero run; S: coefficient size; Base: start of the block; Count: MCUs decoded
  Pred: array[0..2] of Integer;  // DC predictor of each component
  BR: TBitReader;  // BR: bit reader for the scan data
  Diff, V: Integer;  // Diff: DC difference; V: AC symbol or value
  Found: Boolean;  // True when the component is in the scan
begin
  if Progressive then
  begin
    DecodeProgressive;
    Exit;
  end;
  Mw := 8 * HMax;  // MCU width
  Mh := 8 * VMax;  // MCU height
  McuX := (W + Mw - 1) div Mw;  // MCUs across
  McuY := (H + Mh - 1) div Mh;  // MCUs down
  for CI := 0 to NComp - 1 do
  begin
    Comp[CI].Bw := McuX * Comp[CI].H;  // blocks across
    Comp[CI].Bh := McuY * Comp[CI].V;  // blocks down
    Count := Comp[CI].Bw * Comp[CI].Bh * 64;  // number of coefficients
    SetLength(Comp[CI].Coef, Count);  // reserve the coefficients
    if Count > 0 then FillChar(Comp[CI].Coef[0], Count * SizeOf(SmallInt), 0);  // start with zeros
    Found := False;  // component not found yet
    for Si := 0 to NScan - 1 do
      if ScanId[Si] = Comp[CI].Id then  // find the scan entry of the component
      begin
        Comp[CI].Td := ScanTd[Si];  // DC table
        Comp[CI].Ta := ScanTa[Si];  // AC table
        Found := True;  // found
      end;
    if not Found then raise EJpegRot.Create('scan component missing');  // every component must be in the scan
    if (not Dht[0, Comp[CI].Td].Ok) or (not Dht[1, Comp[CI].Ta].Ok) then  // both Huffman tables must exist
      raise EJpegRot.Create('missing Huffman table');
  end;
  for I := 0 to 2 do Pred[I] := 0;  // reset the DC predictors
  BR := TBitReader.Create;  // create the bit reader
  try
    BR.D := D;  // scan data
    BR.Pos := DataPos;  // start of the scan data
    BR.Acc := 0;  // empty accumulator
    BR.Cnt := 0;  // no bits yet
    Count := 0;  // no MCUs decoded yet
    for MY := 0 to McuY - 1 do
      for MX := 0 to McuX - 1 do
      begin
        if (Dri > 0) and (Count > 0) and ((Count mod Dri) = 0) then  // restart marker due
        begin
          BR.Restart;  // skip the restart marker
          for I := 0 to 2 do Pred[I] := 0;  // reset the DC predictors
        end;
        Inc(Count);  // count the MCU
        for CI := 0 to NComp - 1 do
          for VI := 0 to Comp[CI].V - 1 do
            for HI := 0 to Comp[CI].H - 1 do
            begin
              Base := (((MY * Comp[CI].V + VI) * Comp[CI].Bw) + (MX * Comp[CI].H + HI)) * 64;  // start of the block in the coefficient array
              T := BR.Decode(Dht[0, Comp[CI].Td]);  // DC size
              if T > 11 then raise EJpegRot.Create('bad DC');  // DC size is at most 11
              if T > 0 then
              begin
                Diff := BR.GetBits(T);  // read the difference bits
                if Diff < (1 shl (T - 1)) then Diff := Diff - (1 shl T) + 1;  // negative values are stored in complement form
              end
              else
                Diff := 0;  // zero difference
              Inc(Pred[CI], Diff);  // add the difference to the predictor
              Comp[CI].Coef[Base] := SmallInt(Pred[CI]);  // store the DC coefficient
              K := 1;  // AC coefficients start at index 1
              while K < 64 do
              begin
                V := BR.Decode(Dht[1, Comp[CI].Ta]);  // AC symbol
                R := V shr 4;  // zero run length
                S := V and 15;  // size of the coefficient
                if S = 0 then
                begin
                  if R = 15 then  // ZRL: sixteen zeros
                  begin
                    Inc(K, 16);  // skip sixteen coefficients
                    Continue;
                  end;
                  Break;  // end of block
                end;
                Inc(K, R);  // skip the zero run
                if K > 63 then raise EJpegRot.Create('coefficient overflow');  // index must stay inside the block
                V := BR.GetBits(S);  // read the value bits
                if V < (1 shl (S - 1)) then V := V - (1 shl S) + 1;  // negative values are stored in complement form
                Comp[CI].Coef[Base + ZZ[K]] := SmallInt(V);  // store at the natural position
                Inc(K);  // next coefficient
              end;
            end;
      end;
  finally
    BR.Free;  // free the bit reader
  end;
end;

{ Progressive JPEG: all scans (spectral selection and successive approximation) are decoded
  into the same coefficient arrays that a sequential file fills; the picture is then turned and
  written as an ordinary sequential file. Method of the Independent JPEG Group decoder. }
procedure TRotator.DecodeProgressive;
var
  Mw, Mh, McuX, McuY, CI, Cur, I, P, M, L, Body, Q, N, Tc, Th, Ns, Ss, Se, Ah, Al: Integer;  // Mw, Mh: size of an MCU; McuX, McuY: MCUs across and down; CI: component; Cur: current component; I: loop counter; P: position in the file; M: marker; L: segment length; Body: start of segment data; Q: position inside the segment; N: count; Tc: table class; Th: table number; Ns: components in the scan; Ss, Se: first and last coefficient; Ah, Al: successive approximation bits
  MX, MY, VI, HI, McuCount, BlkW, BlkH, Base, T, EobRun, P1, M1, Z, Si: Integer;  // MX, MY: MCU position; VI, HI: block inside the MCU; McuCount: MCUs decoded; BlkW, BlkH: blocks across and down; Base: block start; T: DC size; EobRun: blocks left in an end-of-band run; P1, M1: refinement values; Z: coefficient index; Si: scan component
  ScanCi: array[0..3] of Integer;  // scan component indexes
  Pred: array[0..3] of Integer;  // DC predictor of each component
  BR: TBitReader;  // BR: bit reader for the scan data
  Dc, Interleaved: Boolean;  // Dc: DC scan; Interleaved: several components in the scan

  { Reads Size bits and converts them to a signed value. }
  function DecodeValue(Size: Integer): Integer;
  begin
    Result := BR.GetBits(Size);  // read the bits
    if Result < (1 shl (Size - 1)) then Result := Result - (1 shl Size) + 1;  // negative values are stored in complement form
  end;

  { Refines one non-zero coefficient by one more bit. }
  procedure RefineCoef(Idx: Integer);
  var
    C: Integer;  // C: coefficient value
  begin
    C := Comp[Cur].Coef[Idx];  // current value
    if C <> 0 then  // only non-zero coefficients are refined
      if BR.GetBit = 1 then  // a set bit adds precision
        if (C and P1) = 0 then  // only when the bit is not set yet
        begin
          if C >= 0 then C := C + P1 else C := C + M1;  // move away from zero
          Comp[Cur].Coef[Idx] := SmallInt(C);  // store the new value
        end;
  end;

  { Decodes one block of the current scan (DC or AC, first pass or refinement). }
  procedure DoBlock(BB: Integer; Ci2: Integer);
  var
    KK, RR, SSym, VV: Integer;  // KK: coefficient index; RR: zero run; SSym: symbol size; VV: value
  begin
    Cur := Ci2;  // current component
    if Dc then  // DC scan
    begin
      if Ah = 0 then  // first DC pass
      begin
        T := BR.Decode(Dht[0, Comp[Cur].Td]);  // DC size
        if T > 11 then raise EJpegRot.Create('bad DC');  // DC size is at most 11
        VV := 0;  // no difference by default
        if T > 0 then VV := DecodeValue(T);  // read the difference
        Inc(Pred[Cur], VV);  // add the difference to the predictor
        Comp[Cur].Coef[BB] := SmallInt(Pred[Cur] * (1 shl Al));  // store the scaled DC coefficient
      end
      else if BR.GetBit = 1 then  // DC refinement: one more bit
        Comp[Cur].Coef[BB] := SmallInt(Comp[Cur].Coef[BB] or (1 shl Al));  // set the bit
      Exit;
    end;
    if Ah = 0 then
    begin
      // first AC pass for a band of coefficients
      if EobRun > 0 then  // inside an end-of-band run
      begin
        Dec(EobRun);  // one block less in the run
        Exit;
      end;
      KK := Ss;  // start with the first coefficient of the band
      while KK <= Se do
      begin
        VV := BR.Decode(Dht[1, Comp[Cur].Ta]);  // AC symbol
        RR := VV shr 4;  // zero run length
        SSym := VV and 15;  // size of the coefficient
        if SSym <> 0 then
        begin
          Inc(KK, RR);  // skip the zero run
          if KK > 63 then raise EJpegRot.Create('coefficient overflow');  // index must stay inside the block
          Comp[Cur].Coef[BB + ZZ[KK]] := SmallInt(DecodeValue(SSym) * (1 shl Al));  // store the scaled coefficient
          Inc(KK);  // next coefficient
        end
        else if RR = 15 then
          Inc(KK, 16)  // ZRL: sixteen zeros
        else
        begin
          EobRun := 1 shl RR;  // new end-of-band run
          if RR > 0 then Inc(EobRun, BR.GetBits(RR));  // add the extra bits
          Dec(EobRun);  // this block is part of the run
          Break;
        end;
      end;
      Exit;
    end;
    // refinement pass for a band of coefficients
    KK := Ss;  // start with the first coefficient of the band
    if EobRun = 0 then  // not in an end-of-band run
    begin
      while KK <= Se do
      begin
        VV := BR.Decode(Dht[1, Comp[Cur].Ta]);  // AC symbol
        RR := VV shr 4;  // zero run length
        SSym := VV and 15;  // size of the coefficient
        if SSym <> 0 then
        begin
          if SSym <> 1 then raise EJpegRot.Create('bad refinement');  // refinement values must be one bit
          if BR.GetBit = 1 then SSym := P1 else SSym := M1;  // new coefficient is positive or negative
        end
        else if RR <> 15 then
        begin
          EobRun := 1 shl RR;  // new end-of-band run
          if RR > 0 then Inc(EobRun, BR.GetBits(RR));  // add the extra bits
          Break;
        end;
        repeat
          Z := BB + ZZ[KK];  // natural position of the coefficient
          if Comp[Cur].Coef[Z] <> 0 then
            RefineCoef(Z)  // refine an existing coefficient
          else
          begin
            Dec(RR);  // count the zeros skipped
            if RR < 0 then Break;  // zero run used up
          end;
          Inc(KK);  // next coefficient
        until KK > Se;
        if (SSym <> 0) and (KK <= 63) then Comp[Cur].Coef[BB + ZZ[KK]] := SmallInt(SSym);  // store the new coefficient
        Inc(KK);  // next coefficient
      end;
    end;
    if EobRun > 0 then
    begin
      while KK <= Se do  // refine the rest of the band
      begin
        RefineCoef(BB + ZZ[KK]);  // refine the coefficient
        Inc(KK);  // next coefficient
      end;
      Dec(EobRun);  // one block less in the run
    end;
  end;

begin
  Mw := 8 * HMax;  // MCU width
  Mh := 8 * VMax;  // MCU height
  McuX := (W + Mw - 1) div Mw;  // MCUs across
  McuY := (H + Mh - 1) div Mh;  // MCUs down
  for CI := 0 to NComp - 1 do
  begin
    Comp[CI].Bw := McuX * Comp[CI].H;  // blocks across
    Comp[CI].Bh := McuY * Comp[CI].V;  // blocks down
    N := Comp[CI].Bw * Comp[CI].Bh * 64;  // number of coefficients
    SetLength(Comp[CI].Coef, N);  // reserve the coefficients
    if N > 0 then FillChar(Comp[CI].Coef[0], N * SizeOf(SmallInt), 0);  // start with zeros
  end;
  P := DataPos;  // first scan header
  BR := TBitReader.Create;  // create the bit reader
  try
    BR.D := D;  // file data
    while P + 2 <= Length(D) do  // go through all segments
    begin
      if D[P] <> $FF then raise EJpegRot.Create('bad marker');  // every marker starts with FF
      M := D[P + 1];  // marker code
      if M = $FF then  // FF fill bytes
      begin
        Inc(P);  // skip the fill byte
        Continue;
      end;
      if M = $D9 then Break;                       // end of image
      if (M = $D8) or ((M >= $D0) and (M <= $D7)) or (M = 1) then  // markers without a length field
      begin
        Inc(P, 2);  // skip the two marker bytes
        Continue;
      end;
      if P + 4 > Length(D) then raise EJpegRot.Create('truncated');  // a marker needs at least four bytes
      L := U16At(D, P + 2);  // segment length
      Body := P + 4;  // start of the segment data
      if (L < 2) or (P + 2 + L > Length(D)) then raise EJpegRot.Create('bad segment');  // length must fit in the file
      if M = $C4 then  // Huffman table definition
      begin
        Q := Body;  // first table in the segment
        while Q + 17 <= P + 2 + L do
        begin
          Tc := D[Q] shr 4;  // table class (0 DC, 1 AC)
          Th := D[Q] and 15;  // table number
          N := 0;  // total number of symbols
          for I := 0 to 15 do Inc(N, D[Q + 1 + I]);  // add up the code counts
          if (Tc > 1) or (Th > 3) then raise EJpegRot.Create('unsupported DHT');
          BuildDec(Dht[Tc, Th], D, Q + 1, Q + 17, N);  // build the decoding table
          Inc(Q, 17 + N);  // move to the next table
        end;
      end
      else if M = $DD then
        Dri := U16At(D, Body)  // restart interval
      else if M = $DB then  // quantization table
      begin
        Q := Body;  // first table in the segment
        while Q < P + 2 + L do
        begin
          if ((D[Q] shr 4) <> 0) or ((D[Q] and 15) > 3) or (Q + 65 > P + 2 + L) then  // only 8-bit tables are supported
            raise EJpegRot.Create('unsupported DQT');
          Move(D[Q + 1], Dqt[D[Q] and 15, 0], 64);  // copy the 64 values
          HaveDqt[D[Q] and 15] := True;  // remember that the table exists
          Inc(Q, 65);  // move to the next table
        end;
      end
      else if M = $DA then  // start of scan
      begin
        Ns := D[Body];  // number of components in the scan
        if (Ns < 1) or (Ns > NComp) or (Body + 1 + Ns * 2 + 3 > Length(D)) then  // check the component count and the header size
          raise EJpegRot.Create('bad scan');
        for I := 0 to Ns - 1 do  // every scan component
        begin
          ScanCi[I] := -1;  // not found yet
          for CI := 0 to NComp - 1 do  // search the frame components
            if Comp[CI].Id = D[Body + 1 + I * 2] then  // same component id
            begin
              ScanCi[I] := CI;  // remember the component index
              Comp[CI].Td := D[Body + 2 + I * 2] shr 4;  // DC table
              Comp[CI].Ta := D[Body + 2 + I * 2] and 15;  // AC table
              if (Comp[CI].Td > 3) or (Comp[CI].Ta > 3) then raise EJpegRot.Create('bad scan');
            end;
          if ScanCi[I] < 0 then raise EJpegRot.Create('scan component missing');  // every component must be in the frame
        end;
        Ss := D[Body + 1 + Ns * 2];  // first coefficient of the band
        Se := D[Body + 2 + Ns * 2];  // last coefficient of the band
        Ah := D[Body + 3 + Ns * 2] shr 4;  // previous approximation bit
        Al := D[Body + 3 + Ns * 2] and 15;  // current approximation bit
        Dc := (Ss = 0);  // DC scan when the band starts at 0
        if (Se > 63) or (Se < Ss) or (Al > 13) or (Dc and (Se <> 0)) or ((not Dc) and (Ns <> 1)) then  // check the band parameters
          raise EJpegRot.Create('bad scan parameters');
        for I := 0 to Ns - 1 do  // every scan component
        begin
          if Dc and (Ah = 0) and (not Dht[0, Comp[ScanCi[I]].Td].Ok) then raise EJpegRot.Create('missing Huffman table');  // DC table must exist for the first DC pass
          if (not Dc) and (not Dht[1, Comp[ScanCi[I]].Ta].Ok) then raise EJpegRot.Create('missing Huffman table');  // AC table must exist for AC scans
        end;
        P1 := 1 shl Al;  // value added when a coefficient grows
        M1 := -P1;  // value added when a coefficient shrinks
        for I := 0 to 3 do Pred[I] := 0;  // reset the DC predictors
        EobRun := 0;  // no end-of-band run
        BR.Pos := P + 2 + L;  // scan data starts after the header
        BR.Acc := 0;  // empty accumulator
        BR.Cnt := 0;  // no bits yet
        Interleaved := (Ns > 1);  // several components means interleaved MCUs
        McuCount := 0;  // no MCUs decoded yet
        if Interleaved then
        begin
          for MY := 0 to McuY - 1 do  // every MCU row
            for MX := 0 to McuX - 1 do  // every MCU column
            begin
              if (Dri > 0) and (McuCount > 0) and ((McuCount mod Dri) = 0) then  // restart marker due
              begin
                BR.Restart;  // skip the restart marker
                for I := 0 to 3 do Pred[I] := 0;  // reset the DC predictors
                EobRun := 0;  // end the end-of-band run
              end;
              Inc(McuCount);  // count the MCU
              for Si := 0 to Ns - 1 do  // every scan component
              begin
                CI := ScanCi[Si];  // component index
                for VI := 0 to Comp[CI].V - 1 do  // blocks down inside the MCU
                  for HI := 0 to Comp[CI].H - 1 do  // blocks across inside the MCU
                  begin
                    Base := (((MY * Comp[CI].V + VI) * Comp[CI].Bw) + (MX * Comp[CI].H + HI)) * 64;  // start of the block in the coefficient array
                    DoBlock(Base, CI);  // decode the block
                  end;
              end;
            end;
        end
        else
        begin
          CI := ScanCi[0];  // only component of the scan
          // a single component covers only the blocks that hold real picture area
          BlkW := (((W * Comp[CI].H + HMax - 1) div HMax) + 7) div 8;  // blocks across that hold picture area
          BlkH := (((H * Comp[CI].V + VMax - 1) div VMax) + 7) div 8;  // blocks down that hold picture area
          for MY := 0 to BlkH - 1 do  // every block row
            for MX := 0 to BlkW - 1 do  // every block column
            begin
              if (Dri > 0) and (McuCount > 0) and ((McuCount mod Dri) = 0) then  // restart marker due
              begin
                BR.Restart;  // skip the restart marker
                for I := 0 to 3 do Pred[I] := 0;  // reset the DC predictors
                EobRun := 0;  // end the end-of-band run
              end;
              Inc(McuCount);  // count the block
              DoBlock((MY * Comp[CI].Bw + MX) * 64, CI);  // decode the block
            end;
        end;
        // continue after the entropy-coded data: the next marker that is not a restart
        P := BR.Pos;  // continue behind the scan data
        while P + 1 < Length(D) do  // search for the next marker
        begin
          if (D[P] = $FF) and (D[P + 1] <> 0) and (D[P + 1] <> $FF) and
             ((D[P + 1] < $D0) or (D[P + 1] > $D7)) then Break;
          Inc(P);  // next byte
        end;
        Continue;  // handle that marker
      end;
      Inc(P, 2 + L);  // skip the segment
    end;
  finally
    BR.Free;  // free the bit reader
  end;
end;

{ Swaps rows and columns of the picture (transposes every block and the block grid). }
procedure TRotator.Transpose;
var
  CI, X, Y, R, C, Src, Dst: Integer;  // CI: component; X, Y: block position; R, C: row and column inside a block; Src, Dst: block offsets
  NewC: TCoefs;  // NewC: transposed coefficients
  T: Integer;  // T: swap helper
begin
  NewC := nil;  // release any old array
  for CI := 0 to NComp - 1 do  // every component
  begin
    SetLength(NewC, Length(Comp[CI].Coef));  // reserve the new coefficients
    for Y := 0 to Comp[CI].Bh - 1 do  // every block row
      for X := 0 to Comp[CI].Bw - 1 do  // every block column
      begin
        Src := (Y * Comp[CI].Bw + X) * 64;  // offset of the source block
        Dst := (X * Comp[CI].Bh + Y) * 64;  // offset of the block at the mirrored grid position
        for R := 0 to 7 do  // every row of the block
          for C := 0 to 7 do  // every column of the block
            NewC[Dst + R * 8 + C] := Comp[CI].Coef[Src + C * 8 + R];  // swap row and column
      end;
    Comp[CI].Coef := NewC;  // use the new coefficients
    NewC := nil;  // release the helper
    T := Comp[CI].Bw;  // swap block counts
    Comp[CI].Bw := Comp[CI].Bh;  // width becomes height
    Comp[CI].Bh := T;  // height becomes width
    T := Comp[CI].H;  // swap sampling factors
    Comp[CI].H := Comp[CI].V;  // horizontal becomes vertical
    Comp[CI].V := T;  // vertical becomes horizontal
  end;
  T := W;  // swap picture size
  W := H;  // width becomes height
  H := T;  // height becomes width
end;

{ Drops the blocks at the right edge so that the width becomes NewW. }
procedure TRotator.CutColumns(NewW: Integer);
var
  CI, Y, NewBw: Integer;  // CI: component; Y: block row; NewBw: blocks across after cutting
  NewC: TCoefs;  // NewC: cut coefficients
begin
  NewC := nil;  // release any old array
  W := NewW;  // new picture width
  for CI := 0 to NComp - 1 do  // every component
  begin
    NewBw := (W div (8 * HMax)) * Comp[CI].H;  // blocks across after cutting
    SetLength(NewC, NewBw * Comp[CI].Bh * 64);  // reserve the new coefficients
    for Y := 0 to Comp[CI].Bh - 1 do  // every block row
      if NewBw > 0 then  // only when blocks remain
        Move(Comp[CI].Coef[(Y * Comp[CI].Bw) * 64], NewC[(Y * NewBw) * 64],  // copy the rows that remain
          NewBw * 64 * SizeOf(SmallInt));
    Comp[CI].Coef := NewC;  // use the new coefficients
    NewC := nil;  // release the helper
    Comp[CI].Bw := NewBw;  // new block count
  end;
end;

{ Drops the blocks at the bottom edge so that the height becomes NewH. }
procedure TRotator.CutRows(NewH: Integer);
var
  CI, NewBh: Integer;  // CI: component; NewBh: blocks down after cutting
begin
  H := NewH;  // new picture height
  for CI := 0 to NComp - 1 do  // every component
  begin
    NewBh := (H div (8 * VMax)) * Comp[CI].V;  // blocks down after cutting
    SetLength(Comp[CI].Coef, NewBh * Comp[CI].Bw * 64);  // shorten the coefficient array
    Comp[CI].Bh := NewBh;  // new block count
  end;
end;

{ Mirrors the picture left to right in the DCT domain. }
procedure TRotator.FlipH;
var
  CI, Y, X, I, A, B: Integer;  // CI: component; Y, X: block position; I: coefficient; A, B: offsets of the two blocks
  T: SmallInt;  // T: swap helper
begin
  for CI := 0 to NComp - 1 do  // every component
    for Y := 0 to Comp[CI].Bh - 1 do  // every block row
    begin
      for X := 0 to Comp[CI].Bw div 2 - 1 do  // first half of the row
      begin
        A := (Y * Comp[CI].Bw + X) * 64;  // offset of the left block
        B := (Y * Comp[CI].Bw + (Comp[CI].Bw - 1 - X)) * 64;  // offset of the mirrored block on the right
        for I := 0 to 63 do  // swap all 64 coefficients
        begin
          T := Comp[CI].Coef[A + I];  // keep the left value
          Comp[CI].Coef[A + I] := Comp[CI].Coef[B + I];  // copy the right value over
          Comp[CI].Coef[B + I] := T;  // store the left value on the right
        end;
      end;
      // horizontal frequencies of odd index change sign
      for X := 0 to Comp[CI].Bw - 1 do  // every block of the row
      begin
        A := (Y * Comp[CI].Bw + X) * 64;  // offset of the block
        I := 1;  // first odd horizontal frequency
        while I < 64 do  // every second coefficient
        begin
          Comp[CI].Coef[A + I] := -Comp[CI].Coef[A + I];  // change the sign
          Inc(I, 2);  // next odd coefficient
        end;
      end;
    end;
end;

{ Mirrors the picture top to bottom in the DCT domain. }
procedure TRotator.FlipV;
var
  CI, Y, X, I, A, B: Integer;  // CI: component; Y, X: block position; I: coefficient; A, B: offsets of the two blocks
  T: SmallInt;  // T: swap helper
begin
  for CI := 0 to NComp - 1 do  // every component
  begin
    for Y := 0 to Comp[CI].Bh div 2 - 1 do  // first half of the block rows
      for X := 0 to Comp[CI].Bw - 1 do  // every block of the row
      begin
        A := (Y * Comp[CI].Bw + X) * 64;  // offset of the upper block
        B := ((Comp[CI].Bh - 1 - Y) * Comp[CI].Bw + X) * 64;  // offset of the mirrored block below
        for I := 0 to 63 do  // swap all 64 coefficients
        begin
          T := Comp[CI].Coef[A + I];  // keep the upper value
          Comp[CI].Coef[A + I] := Comp[CI].Coef[B + I];  // copy the lower value over
          Comp[CI].Coef[B + I] := T;  // store the upper value below
        end;
      end;
    // vertical frequencies of odd index change sign
    for Y := 0 to Comp[CI].Bh - 1 do  // every block row
      for X := 0 to Comp[CI].Bw - 1 do  // every block of the row
      begin
        A := (Y * Comp[CI].Bw + X) * 64;  // offset of the block
        for I := 8 to 63 do  // all rows of a block except the first
          if ((I shr 3) and 1) = 1 then  // odd vertical frequency
            Comp[CI].Coef[A + I] := -Comp[CI].Coef[A + I];  // change the sign
      end;
  end;
end;

{ Applies the EXIF orientation: transpose, then flip as needed. }
procedure TRotator.Transform(Orient: Integer; out Transposed: Boolean);
var
  Tr, Hf, Vf: Boolean;  // Tr: transpose; Hf: flip horizontally; Vf: flip vertically
begin
  Tr := Orient in [5, 6, 7, 8];  // orientations 5 to 8 transpose
  Hf := Orient in [2, 3, 6, 7];  // orientations 2, 3, 6 and 7 flip left to right
  Vf := Orient in [3, 4, 7, 8];  // orientations 3, 4, 7 and 8 flip top to bottom
  Transposed := Tr;  // tell the caller whether the tables must be transposed
  if Tr then Transpose;  // swap rows and columns
  // partial blocks on a mirrored edge are dropped (jpegtran -trim)
  if Hf and ((W mod (8 * HMax)) <> 0) then  // width is not a multiple of the block size
  begin
    if W < 8 * HMax then raise EJpegRot.Create('too small');  // picture is smaller than one block
    CutColumns((W div (8 * HMax)) * (8 * HMax));  // cut to whole blocks
  end;
  if Vf and ((H mod (8 * VMax)) <> 0) then  // height is not a multiple of the block size
  begin
    if H < 8 * VMax then raise EJpegRot.Create('too small');  // picture is smaller than one block
    CutRows((H div (8 * VMax)) * (8 * VMax));  // cut to whole blocks
  end;
  if Hf then FlipH;  // mirror left to right
  if Vf then FlipV;  // mirror top to bottom
end;

{ Writes the turned picture as a sequential JPEG with the standard Huffman tables. }
procedure TRotator.Encode(Dest: TStream; Transposed: Boolean);
var
  I, J, Z, CI, VI, HI, MX, MY, McuX, McuY, Base, Diff, A, Sz, Run, V, Tb: Integer;  // I, J, Z: loop counters and table index; CI: component; VI, HI: block inside the MCU; MX, MY: MCU position; McuX, McuY: MCUs across and down; Base: block start; Diff: DC difference; A: absolute value; Sz: bit size; Run: zero run; V: coefficient; Tb: table number
  Pred: array[0..2] of Integer;  // DC predictor of each component
  Nat: array[0..63] of Byte;  // quantization table in natural order
  Tmp: array[0..64] of Byte;  // quantization table bytes to write
  Hdr: array[0..300] of Byte;  // segment header and data
  Dc: array[0..1] of THuffEnc;  // DC Huffman encoders (luminance, chrominance)
  Ac: array[0..1] of THuffEnc;  // AC Huffman encoders (luminance, chrominance)
  BW: TBitWriter;  // BW: bit writer for the scan data
  Seg: TBytes;  // Seg: copy of a kept segment
  Mem: TMemoryStream;  // Mem: the JPEG built in memory
  B: Byte;  // B: single byte to write

  { Writes a DHT segment for one standard table. }
  procedure PutHuff(Tc, Th: Integer; const Bits: array of Byte; const Vals: array of Byte);
  var
    N, K: Integer;  // N: number of symbols; K: loop counter
  begin
    N := 0;  // no symbols yet
    for K := 0 to 15 do Inc(N, Bits[K]);  // add up the code counts
    Hdr[0] := (Tc shl 4) or Th;  // table class and table number
    for K := 0 to 15 do Hdr[1 + K] := Bits[K];  // copy the code counts
    for K := 0 to N - 1 do Hdr[17 + K] := Vals[K];  // copy the symbols
    WriteSeg(Mem, $C4, Hdr, 17 + N);  // write the segment
  end;

begin
  {$PUSH}{$HINTS OFF}
  FillChar(Dc, SizeOf(Dc), 0);  // clear the DC encoders
  FillChar(Ac, SizeOf(Ac), 0);  // clear the AC encoders
  {$POP}
  Mem := TMemoryStream.Create;  // memory stream for the result
  BW := TBitWriter.Create;  // bit writer
  try
    B := $FF; Mem.WriteBuffer(B, 1);  // SOI marker, first byte
    B := $D8; Mem.WriteBuffer(B, 1);  // SOI marker, second byte
    for I := 0 to High(Segs) do  // write the kept segments
    begin
      Seg := Segs[I].Data;  // segment data
      if Segs[I].Marker = $E1 then PatchOrientation(Seg);  // set the orientation to upright
      if Length(Seg) > 0 then  // write segments with data
        WriteSeg(Mem, Segs[I].Marker, Seg, Length(Seg))  // write the kept segment
      else
        WriteSeg(Mem, Segs[I].Marker, Hdr, 0);  // write a segment without data
    end;
    for Tb := 0 to 3 do  // every quantization table
      if HaveDqt[Tb] then  // only defined tables
      begin
        for Z := 0 to 63 do Nat[ZZ[Z]] := Dqt[Tb, Z];  // convert the table to natural order
        Tmp[0] := Tb;  // table number
        if Transposed then  // the picture was transposed
          for Z := 0 to 63 do
            Tmp[1 + Z] := Nat[(ZZ[Z] mod 8) * 8 + (ZZ[Z] div 8)]  // transpose the table as well
        else
          for Z := 0 to 63 do
            Tmp[1 + Z] := Dqt[Tb, Z];  // copy the table unchanged
        WriteSeg(Mem, $DB, Tmp, 65);  // write the DQT segment
      end;
    // frame header (baseline)
    Hdr[0] := 8;  // 8-bit precision
    Hdr[1] := H shr 8; Hdr[2] := H and $FF;  // picture height
    Hdr[3] := W shr 8; Hdr[4] := W and $FF;  // picture width
    Hdr[5] := NComp;  // number of components
    for CI := 0 to NComp - 1 do
    begin
      Hdr[6 + CI * 3] := Comp[CI].Id;  // component id
      Hdr[7 + CI * 3] := (Comp[CI].H shl 4) or Comp[CI].V;  // sampling factors
      Hdr[8 + CI * 3] := Comp[CI].Tq;  // quantization table number
    end;
    WriteSeg(Mem, $C0, Hdr, 6 + NComp * 3);  // write the frame header
    PutHuff(0, 0, DcLumBits, DcLumVals);  // standard luminance DC table
    PutHuff(1, 0, AcLumBits, AcLumVals);  // standard luminance AC table
    BuildEnc(Dc[0], DcLumBits, DcLumVals);  // build the luminance DC encoder
    BuildEnc(Ac[0], AcLumBits, AcLumVals);  // build the luminance AC encoder
    if NComp > 1 then
    begin
      PutHuff(0, 1, DcChrBits, DcChrVals);  // standard chrominance DC table
      PutHuff(1, 1, AcChrBits, AcChrVals);  // standard chrominance AC table
      BuildEnc(Dc[1], DcChrBits, DcChrVals);  // build the chrominance DC encoder
      BuildEnc(Ac[1], AcChrBits, AcChrVals);  // build the chrominance AC encoder
    end;
    Hdr[0] := NComp;  // number of components in the scan
    for CI := 0 to NComp - 1 do
    begin
      Hdr[1 + CI * 2] := Comp[CI].Id;  // component id
      if CI = 0 then Hdr[2 + CI * 2] := $00 else Hdr[2 + CI * 2] := $11;  // luminance uses table 0, chrominance table 1
    end;
    Hdr[1 + NComp * 2] := 0;  // first coefficient
    Hdr[2 + NComp * 2] := 63;  // last coefficient
    Hdr[3 + NComp * 2] := 0;  // no successive approximation
    WriteSeg(Mem, $DA, Hdr, 4 + NComp * 2);  // write the scan header

    McuX := (W + 8 * HMax - 1) div (8 * HMax);  // MCUs across
    McuY := (H + 8 * VMax - 1) div (8 * VMax);  // MCUs down
    BW.Strm := Mem;  // write into the memory stream
    BW.Acc := 0;  // empty accumulator
    BW.Cnt := 0;  // no bits yet
    for I := 0 to 2 do Pred[I] := 0;  // reset the DC predictors
    for MY := 0 to McuY - 1 do  // every MCU row
      for MX := 0 to McuX - 1 do  // every MCU column
        for CI := 0 to NComp - 1 do  // every component
        begin
          J := 0;  // table set 0 for luminance
          if CI > 0 then J := 1;  // table set 1 for chrominance
          for VI := 0 to Comp[CI].V - 1 do  // blocks down inside the MCU
            for HI := 0 to Comp[CI].H - 1 do  // blocks across inside the MCU
            begin
              Base := (((MY * Comp[CI].V + VI) * Comp[CI].Bw) + (MX * Comp[CI].H + HI)) * 64;  // start of the block in the coefficient array
              Diff := Comp[CI].Coef[Base] - Pred[CI];  // DC difference to the previous block
              Pred[CI] := Comp[CI].Coef[Base];  // new predictor
              A := Abs(Diff);  // magnitude of the difference
              Sz := BitCount(A);  // bits needed
              if Sz > 11 then raise EJpegRot.Create('DC too large');  // DC size is at most 11
              BW.Put(Dc[J].Code[Sz], Dc[J].Len[Sz]);  // write the size code
              if Sz > 0 then  // write the value bits
              begin
                if Diff > 0 then V := Diff else V := Diff + (1 shl Sz) - 1;  // negative values are stored in complement form
                BW.Put(Cardinal(V), Sz);  // write the value bits
              end;
              Run := 0;  // no zeros yet
              for Z := 1 to 63 do  // every AC coefficient in zigzag order
              begin
                V := Comp[CI].Coef[Base + ZZ[Z]];  // coefficient value
                if V = 0 then  // zero coefficients are only counted
                begin
                  Inc(Run);  // count the zero
                  Continue;
                end;
                while Run > 15 do  // runs of 16 zeros are written as ZRL
                begin
                  BW.Put(Ac[J].Code[$F0], Ac[J].Len[$F0]);  // write ZRL
                  Dec(Run, 16);  // 16 zeros done
                end;
                A := Abs(V);  // magnitude of the coefficient
                Sz := BitCount(A);  // bits needed
                if Sz > 10 then raise EJpegRot.Create('coefficient too large');  // AC size is at most 10
                BW.Put(Ac[J].Code[(Run shl 4) or Sz], Ac[J].Len[(Run shl 4) or Sz]);  // write run and size code
                if V > 0 then Diff := V else Diff := V + (1 shl Sz) - 1;  // negative values are stored in complement form
                BW.Put(Cardinal(Diff), Sz);  // write the value bits
                Run := 0;  // start a new run
              end;
              if Run > 0 then BW.Put(Ac[J].Code[0], Ac[J].Len[0]);  // end of block when zeros remain
            end;
        end;
    BW.Finish;  // pad the last byte
    B := $FF; Mem.WriteBuffer(B, 1);  // EOI marker, first byte
    B := $D9; Mem.WriteBuffer(B, 1);  // EOI marker, second byte
    Mem.Position := 0;  // rewind
    Dest.CopyFrom(Mem, Mem.Size);  // copy the result to the destination
  finally
    BW.Free;  // free the bit writer
    Mem.Free;  // free the memory stream
  end;
end;

{ Turns a JPEG file according to its EXIF orientation: 1 = rotated, 0 = nothing to do, -1 = not possible. }
function AutoRotateJpegFile(const FileName: string): Integer;
var
  Rot: TRotator;  // Rot: the rotator
  FS: TFileStream;  // FS: input file
  Outp: TFileStream;  // Outp: temporary output file
  Orient, N: Integer;  // Orient: EXIF orientation; N: file size
  Transposed: Boolean;  // True when rows and columns were swapped
  TmpName, BakName: string;  // names of the temporary and backup files
  Age: LongInt;  // file date to restore
begin
  Result := -1;  // assume failure
  RotateLastError := '';  // clear the last error
  Rot := TRotator.Create;  // create the rotator
  try
    try
      FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
      try
        N := Integer(FS.Size);  // file size
        if (N < 100) or (N > 400 * 1024 * 1024) then Exit;  // reject tiny and huge files
        SetLength(Rot.D, N);  // reserve the buffer
        FS.ReadBuffer(Rot.D[0], N);  // read the file
      finally
        FS.Free;  // close the file
      end;
      Rot.Parse;  // read the markers
      Orient := Rot.Orientation;  // orientation from the EXIF data
      if (Orient < 2) or (Orient > 8) then  // only 2 to 8 need work
      begin
        Result := 0;  // nothing to do
        Exit;
      end;
      Rot.DecodeScan;  // decode the coefficients
      Rot.Transform(Orient, Transposed);  // turn the picture
      TmpName := FileName + '.rot.tmp';  // temporary file next to the original
      Outp := TFileStream.Create(TmpName, fmCreate);  // create the temporary file
      try
        Rot.Encode(Outp, Transposed);  // write the new JPEG
      finally
        Outp.Free;  // close the file
      end;
      Age := FileAgeUTF8(FileName);  // remember the file date
      BakName := FileName + '.rot.bak';  // backup file name
      DeleteFileUTF8(BakName);  // remove an old backup
      if not RenameFileUTF8(FileName, BakName) then  // move the original aside
      begin
        DeleteFileUTF8(TmpName);  // remove the temporary file
        Exit;
      end;
      if not RenameFileUTF8(TmpName, FileName) then  // move the new file into place
      begin
        RenameFileUTF8(BakName, FileName);   // put the original back
        DeleteFileUTF8(TmpName);  // remove the temporary file
        Exit;
      end;
      DeleteFileUTF8(BakName);  // remove the backup
      if Age <> -1 then FileSetDateUTF8(FileName, Age);  // restore the file date
      Result := 1;  // success
    except
      on E: Exception do
      begin
        DeleteFileUTF8(FileName + '.rot.tmp');  // remove the temporary file
        RotateLastError := E.ClassName + ': ' + E.Message;  // remember the reason
        Result := -1;  // failure
      end;
    end;
  finally
    Rot.Free;  // free the rotator
  end;
end;

end.
