unit uRotate;

{$mode objfpc}{$H+}

{ Lossless JPEG rotation for "Auto-rotate JPEGs after downloading".

  The picture is turned according to the EXIF Orientation tag by working on the
  quantised DCT coefficients (like jpegtran): nothing is decoded to pixels, so no
  picture quality is lost. The result is written with the standard Huffman tables.
  As jpegtran -trim does, up to 15 pixel rows/columns that do not fill a complete
  block are dropped on the edge that ends up mirrored.

  Supported: baseline/extended sequential JPEG, 8 bit, 1 or 3 components, one scan,
  restart markers. Anything else (progressive, CMYK, ...) is left untouched. }

interface

{ Returns 1 = rotated, 0 = nothing to do (no EXIF orientation or already upright),
  -1 = not possible (the file is left unchanged). }
function AutoRotateJpegFile(const FileName: string): Integer;

{ Display helpers for the EXIF orientation values 2..8: size of the turned picture and where
  the pixel (X, Y) of a W x H picture ends up. }
procedure OrientDims(Orient, W, H: Integer; out NW, NH: Integer);
procedure OrientPoint(Orient, W, H, X, Y: Integer; out NX, NY: Integer);

implementation

uses
  Classes, SysUtils, LazFileUtils;

const
  ZZ: array[0..63] of Byte = (
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63);
  DcLumBits: array[0..15] of Byte = (
    0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0);
  DcLumVals: array[0..11] of Byte = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  DcChrBits: array[0..15] of Byte = (
    0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0);
  DcChrVals: array[0..11] of Byte = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  AcLumBits: array[0..15] of Byte = (
    0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125);
  AcLumVals: array[0..161] of Byte = (
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
  AcChrBits: array[0..15] of Byte = (
    0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119);
  AcChrVals: array[0..161] of Byte = (
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
  EJpegRot = class(Exception);

  THuffDec = record
    MinC, MaxC, Ptr: array[1..16] of Integer;
    Vals: array[0..255] of Byte;
    Ok: Boolean;
  end;

  THuffEnc = record
    Code: array[0..255] of Cardinal;
    Len: array[0..255] of Byte;
  end;

  TCoefs = array of SmallInt;

  TComp = record
    Id, H, V, Tq, Bw, Bh, Td, Ta: Integer;
    Coef: TCoefs;                   // ((Y * Bw + X) * 64) + natural coefficient index
  end;

  TSeg = record
    Marker: Byte;
    Data: TBytes;
  end;

  { TBitReader }
  TBitReader = class
  public
    D: TBytes;
    Pos: Integer;
    Acc, Cnt: Integer;
    function GetBit: Integer;
    function GetBits(K: Integer): Integer;
    function Decode(const T: THuffDec): Integer;
    procedure Restart;
  end;

  { TBitWriter }
  TBitWriter = class
  public
    Strm: TMemoryStream;
    Acc, Cnt: Integer;
    procedure Put(Code: Cardinal; Len: Integer);
    procedure Finish;
  end;

function TBitReader.GetBit: Integer;
var
  B: Integer;
begin
  if Cnt = 0 then
  begin
    if Pos >= Length(D) then raise EJpegRot.Create('end of data');
    B := D[Pos];
    if B = $FF then
    begin
      if Pos + 1 >= Length(D) then raise EJpegRot.Create('end of data');
      if D[Pos + 1] = 0 then
        Inc(Pos, 2)
      else
        raise EJpegRot.Create('marker inside scan data');
    end
    else
      Inc(Pos);
    Acc := B;
    Cnt := 8;
  end;
  Dec(Cnt);
  Result := (Acc shr Cnt) and 1;
end;

function TBitReader.GetBits(K: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to K do Result := (Result shl 1) or GetBit;
end;

function TBitReader.Decode(const T: THuffDec): Integer;
var
  L, Code: Integer;
begin
  Code := 0;
  for L := 1 to 16 do
  begin
    Code := (Code shl 1) or GetBit;
    if (T.MaxC[L] >= 0) and (Code <= T.MaxC[L]) and (Code >= T.MinC[L]) then
    begin
      Result := T.Vals[T.Ptr[L] + Code - T.MinC[L]];
      Exit;
    end;
  end;
  raise EJpegRot.Create('bad Huffman code');
end;

procedure TBitReader.Restart;
begin
  Cnt := 0;
  while (Pos < Length(D)) and (D[Pos] <> $FF) do Inc(Pos);
  while (Pos < Length(D)) and (D[Pos] = $FF) do Inc(Pos);
  Inc(Pos);                          // the RSTn marker byte
end;

procedure TBitWriter.Put(Code: Cardinal; Len: Integer);
var
  I: Integer;
  B: Byte;
begin
  for I := Len - 1 downto 0 do
  begin
    Acc := (Acc shl 1) or Integer((Code shr I) and 1);
    Inc(Cnt);
    if Cnt = 8 then
    begin
      B := Acc and $FF;
      Strm.WriteBuffer(B, 1);
      if B = $FF then
      begin
        B := 0;
        Strm.WriteBuffer(B, 1);
      end;
      Acc := 0;
      Cnt := 0;
    end;
  end;
end;

procedure TBitWriter.Finish;
begin
  while Cnt <> 0 do Put(1, 1);
end;

function BitCount(V: Integer): Integer;
begin
  Result := 0;
  while V > 0 do
  begin
    Inc(Result);
    V := V shr 1;
  end;
end;

procedure BuildDec(var T: THuffDec; const B: TBytes; BitsPos, ValsPos, N: Integer);
var
  L, K, Code, C, I: Integer;
begin
  if (N > 256) or (ValsPos + N > Length(B)) then raise EJpegRot.Create('bad DHT');
  Code := 0;
  K := 0;
  for L := 1 to 16 do
  begin
    C := B[BitsPos + L - 1];
    T.Ptr[L] := K;
    T.MinC[L] := Code;
    Inc(Code, C);
    Inc(K, C);
    if C > 0 then T.MaxC[L] := Code - 1 else T.MaxC[L] := -1;
    Code := Code shl 1;
  end;
  for I := 0 to 255 do T.Vals[I] := 0;
  for I := 0 to N - 1 do T.Vals[I] := B[ValsPos + I];
  T.Ok := True;
end;

procedure BuildEnc(var E: THuffEnc; const Bits: array of Byte; const Vals: array of Byte);
var
  L, I, K: Integer;
  Code: Cardinal;
begin
  for I := 0 to 255 do
  begin
    E.Code[I] := 0;
    E.Len[I] := 0;
  end;
  Code := 0;
  K := 0;
  for L := 1 to 16 do
  begin
    for I := 1 to Bits[L - 1] do
    begin
      E.Code[Vals[K]] := Code;
      E.Len[Vals[K]] := L;
      Inc(Code);
      Inc(K);
    end;
    Code := Code shl 1;
  end;
end;

procedure OrientDims(Orient, W, H: Integer; out NW, NH: Integer);
begin
  if Orient in [5, 6, 7, 8] then
  begin
    NW := H;
    NH := W;
  end
  else
  begin
    NW := W;
    NH := H;
  end;
end;

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
    D: TBytes;
    Segs: array of TSeg;
    Dqt: array[0..3, 0..63] of Byte;
    HaveDqt: array[0..3] of Boolean;
    Dht: array[0..1, 0..3] of THuffDec;
    Dri, W, H, NComp, DataPos, NScan: Integer;
    Comp: array[0..2] of TComp;
    ScanId, ScanTd, ScanTa: array[0..2] of Integer;
    HaveSof: Boolean;
    function Orientation: Integer;
    procedure Parse;
    procedure DecodeScan;
    procedure Transform(Orient: Integer; out Transposed: Boolean);
    procedure Encode(Dest: TStream; Transposed: Boolean);
  private
    procedure PatchOrientation(var Data: TBytes);
    procedure Transpose;
    procedure CutColumns(NewW: Integer);
    procedure CutRows(NewH: Integer);
    procedure FlipH;
    procedure FlipV;
    function HMax: Integer;
    function VMax: Integer;
  end;

function U16At(const B: TBytes; P: Integer): Integer;
begin
  Result := (B[P] shl 8) or B[P + 1];
end;

procedure WriteSeg(S: TStream; Marker: Byte; const Data: array of Byte; Len: Integer);
var
  M: array[0..3] of Byte;
begin
  M[0] := $FF;
  M[1] := Marker;
  M[2] := (Len + 2) shr 8;
  M[3] := (Len + 2) and $FF;
  S.WriteBuffer(M, 4);
  if Len > 0 then S.WriteBuffer(Data[0], Len);
end;

{ finds the Orientation tag in an EXIF APP1 segment; returns its value (0 if absent) and,
  when Patch is True, sets it to 1 }
function ExifOrientation(var Data: TBytes; Patch: Boolean): Integer;
var
  T, Off, N, I, X: Integer;
  Big: Boolean;

  function R16(P: Integer): Integer;
  begin
    if (P < 0) or (P + 2 > Length(Data)) then Exit(0);
    if Big then Result := (Data[P] shl 8) or Data[P + 1] else Result := Data[P] or (Data[P + 1] shl 8);
  end;

  function R32(P: Integer): Integer;
  begin
    if (P < 0) or (P + 4 > Length(Data)) then Exit(0);
    if Big then
      Result := (Data[P] shl 24) or (Data[P + 1] shl 16) or (Data[P + 2] shl 8) or Data[P + 3]
    else
      Result := Data[P] or (Data[P + 1] shl 8) or (Data[P + 2] shl 16) or (Data[P + 3] shl 24);
  end;

begin
  Result := 0;
  if (Length(Data) < 14) or (Data[0] <> Ord('E')) or (Data[1] <> Ord('x')) or
     (Data[2] <> Ord('i')) or (Data[3] <> Ord('f')) or (Data[4] <> 0) or (Data[5] <> 0) then Exit;
  T := 6;
  Big := (Data[T] = $4D) and (Data[T + 1] = $4D);
  if (not Big) and not ((Data[T] = $49) and (Data[T + 1] = $49)) then Exit;
  Off := R32(T + 4);
  if (Off < 8) or (Off > 65536) then Exit;
  N := R16(T + Off);
  if N > 300 then N := 300;
  for I := 0 to N - 1 do
  begin
    X := T + Off + 2 + I * 12;
    if X + 12 > Length(Data) then Break;
    if R16(X) = $0112 then
    begin
      Result := R16(X + 8);
      if Patch then
        if Big then
        begin
          Data[X + 8] := 0;
          Data[X + 9] := 1;
        end
        else
        begin
          Data[X + 8] := 1;
          Data[X + 9] := 0;
        end;
      Exit;
    end;
  end;
end;

function TRotator.Orientation: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Segs) do
    if Segs[I].Marker = $E1 then
    begin
      Result := ExifOrientation(Segs[I].Data, False);
      if Result <> 0 then Exit;
    end;
end;

procedure TRotator.PatchOrientation(var Data: TBytes);
begin
  ExifOrientation(Data, True);
end;

function TRotator.HMax: Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 0 to NComp - 1 do
    if Comp[I].H > Result then Result := Comp[I].H;
end;

function TRotator.VMax: Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 0 to NComp - 1 do
    if Comp[I].V > Result then Result := Comp[I].V;
end;

procedure TRotator.Parse;
var
  P, M, L, Q, I, N, Tc, Th, Pq, Tq, Ns: Integer;
  Body: Integer;
  S: TSeg;
begin
  if (Length(D) < 4) or (D[0] <> $FF) or (D[1] <> $D8) then raise EJpegRot.Create('not a JPEG');
  P := 2;
  Dri := 0;
  NComp := 0;
  HaveSof := False;
  for I := 0 to 3 do HaveDqt[I] := False;
  for Tc := 0 to 1 do
    for Th := 0 to 3 do Dht[Tc, Th].Ok := False;
  while True do
  begin
    if P + 4 > Length(D) then raise EJpegRot.Create('truncated');
    if D[P] <> $FF then raise EJpegRot.Create('bad marker');
    M := D[P + 1];
    if M = $FF then
    begin
      Inc(P);
      Continue;
    end;
    L := U16At(D, P + 2);
    Body := P + 4;
    if (L < 2) or (P + 2 + L > Length(D)) then raise EJpegRot.Create('bad segment');
    if ((M >= $E0) and (M <= $EF)) or (M = $FE) then
    begin
      S.Marker := M;
      SetLength(S.Data, L - 2);
      if L > 2 then Move(D[Body], S.Data[0], L - 2);
      SetLength(Segs, Length(Segs) + 1);
      Segs[High(Segs)] := S;
    end
    else if M = $DB then
    begin
      Q := Body;
      while Q < P + 2 + L do
      begin
        Pq := D[Q] shr 4;
        Tq := D[Q] and 15;
        Inc(Q);
        if (Pq <> 0) or (Tq > 3) or (Q + 64 > P + 2 + L) then raise EJpegRot.Create('unsupported DQT');
        Move(D[Q], Dqt[Tq, 0], 64);
        HaveDqt[Tq] := True;
        Inc(Q, 64);
      end;
    end
    else if (M = $C0) or (M = $C1) then
    begin
      if D[Body] <> 8 then raise EJpegRot.Create('not 8 bit');
      H := U16At(D, Body + 1);
      W := U16At(D, Body + 3);
      NComp := D[Body + 5];
      if not (NComp in [1, 3]) or (H = 0) or (W = 0) then raise EJpegRot.Create('unsupported layout');
      for I := 0 to NComp - 1 do
      begin
        Comp[I].Id := D[Body + 6 + I * 3];
        Comp[I].H := D[Body + 7 + I * 3] shr 4;
        Comp[I].V := D[Body + 7 + I * 3] and 15;
        Comp[I].Tq := D[Body + 8 + I * 3];
        if (Comp[I].H < 1) or (Comp[I].H > 4) or (Comp[I].V < 1) or (Comp[I].V > 4) or
           (Comp[I].Tq > 3) then raise EJpegRot.Create('unsupported sampling');
      end;
      HaveSof := True;
    end
    else if (M = $C2) or (M = $C3) or ((M >= $C5) and (M <= $CF) and (M <> $C8) and (M <> $CC) and (M <> $C4)) then
      raise EJpegRot.Create('unsupported JPEG type')
    else if M = $C4 then
    begin
      Q := Body;
      while Q + 17 <= P + 2 + L do
      begin
        Tc := D[Q] shr 4;
        Th := D[Q] and 15;
        N := 0;
        for I := 0 to 15 do Inc(N, D[Q + 1 + I]);
        if (Tc > 1) or (Th > 3) then raise EJpegRot.Create('unsupported DHT');
        BuildDec(Dht[Tc, Th], D, Q + 1, Q + 17, N);
        Inc(Q, 17 + N);
      end;
    end
    else if M = $DD then
      Dri := U16At(D, Body)
    else if M = $DA then
    begin
      if not HaveSof then raise EJpegRot.Create('no frame header');
      Ns := D[Body];
      if Ns <> NComp then raise EJpegRot.Create('several scans');
      NScan := Ns;
      for I := 0 to Ns - 1 do
      begin
        ScanId[I] := D[Body + 1 + I * 2];
        ScanTd[I] := D[Body + 2 + I * 2] shr 4;
        ScanTa[I] := D[Body + 2 + I * 2] and 15;
        if (ScanTd[I] > 3) or (ScanTa[I] > 3) then raise EJpegRot.Create('bad scan');
      end;
      DataPos := P + 2 + L;
      Exit;
    end;
    P := P + 2 + L;
  end;
end;

procedure TRotator.DecodeScan;
var
  Mw, Mh, McuX, McuY, MX, MY, CI, VI, HI, I, K, Si, T, R, S, Base, Count: Integer;
  Pred: array[0..2] of Integer;
  BR: TBitReader;
  Diff, V: Integer;
  Found: Boolean;
begin
  Mw := 8 * HMax;
  Mh := 8 * VMax;
  McuX := (W + Mw - 1) div Mw;
  McuY := (H + Mh - 1) div Mh;
  for CI := 0 to NComp - 1 do
  begin
    Comp[CI].Bw := McuX * Comp[CI].H;
    Comp[CI].Bh := McuY * Comp[CI].V;
    Count := Comp[CI].Bw * Comp[CI].Bh * 64;
    SetLength(Comp[CI].Coef, Count);
    if Count > 0 then FillChar(Comp[CI].Coef[0], Count * SizeOf(SmallInt), 0);
    Found := False;
    for Si := 0 to NScan - 1 do
      if ScanId[Si] = Comp[CI].Id then
      begin
        Comp[CI].Td := ScanTd[Si];
        Comp[CI].Ta := ScanTa[Si];
        Found := True;
      end;
    if not Found then raise EJpegRot.Create('scan component missing');
    if (not Dht[0, Comp[CI].Td].Ok) or (not Dht[1, Comp[CI].Ta].Ok) then
      raise EJpegRot.Create('missing Huffman table');
  end;
  for I := 0 to 2 do Pred[I] := 0;
  BR := TBitReader.Create;
  try
    BR.D := D;
    BR.Pos := DataPos;
    BR.Acc := 0;
    BR.Cnt := 0;
    Count := 0;
    for MY := 0 to McuY - 1 do
      for MX := 0 to McuX - 1 do
      begin
        if (Dri > 0) and (Count > 0) and ((Count mod Dri) = 0) then
        begin
          BR.Restart;
          for I := 0 to 2 do Pred[I] := 0;
        end;
        Inc(Count);
        for CI := 0 to NComp - 1 do
          for VI := 0 to Comp[CI].V - 1 do
            for HI := 0 to Comp[CI].H - 1 do
            begin
              Base := (((MY * Comp[CI].V + VI) * Comp[CI].Bw) + (MX * Comp[CI].H + HI)) * 64;
              T := BR.Decode(Dht[0, Comp[CI].Td]);
              if T > 11 then raise EJpegRot.Create('bad DC');
              if T > 0 then
              begin
                Diff := BR.GetBits(T);
                if Diff < (1 shl (T - 1)) then Diff := Diff - (1 shl T) + 1;
              end
              else
                Diff := 0;
              Inc(Pred[CI], Diff);
              Comp[CI].Coef[Base] := SmallInt(Pred[CI]);
              K := 1;
              while K < 64 do
              begin
                V := BR.Decode(Dht[1, Comp[CI].Ta]);
                R := V shr 4;
                S := V and 15;
                if S = 0 then
                begin
                  if R = 15 then
                  begin
                    Inc(K, 16);
                    Continue;
                  end;
                  Break;
                end;
                Inc(K, R);
                if K > 63 then raise EJpegRot.Create('coefficient overflow');
                V := BR.GetBits(S);
                if V < (1 shl (S - 1)) then V := V - (1 shl S) + 1;
                Comp[CI].Coef[Base + ZZ[K]] := SmallInt(V);
                Inc(K);
              end;
            end;
      end;
  finally
    BR.Free;
  end;
end;

procedure TRotator.Transpose;
var
  CI, X, Y, R, C, Src, Dst: Integer;
  NewC: TCoefs;
  T: Integer;
begin
  NewC := nil;
  for CI := 0 to NComp - 1 do
  begin
    SetLength(NewC, Length(Comp[CI].Coef));
    for Y := 0 to Comp[CI].Bh - 1 do
      for X := 0 to Comp[CI].Bw - 1 do
      begin
        Src := (Y * Comp[CI].Bw + X) * 64;
        Dst := (X * Comp[CI].Bh + Y) * 64;
        for R := 0 to 7 do
          for C := 0 to 7 do
            NewC[Dst + R * 8 + C] := Comp[CI].Coef[Src + C * 8 + R];
      end;
    Comp[CI].Coef := NewC;
    NewC := nil;
    T := Comp[CI].Bw;
    Comp[CI].Bw := Comp[CI].Bh;
    Comp[CI].Bh := T;
    T := Comp[CI].H;
    Comp[CI].H := Comp[CI].V;
    Comp[CI].V := T;
  end;
  T := W;
  W := H;
  H := T;
end;

procedure TRotator.CutColumns(NewW: Integer);
var
  CI, Y, NewBw: Integer;
  NewC: TCoefs;
begin
  NewC := nil;
  W := NewW;
  for CI := 0 to NComp - 1 do
  begin
    NewBw := (W div (8 * HMax)) * Comp[CI].H;
    SetLength(NewC, NewBw * Comp[CI].Bh * 64);
    for Y := 0 to Comp[CI].Bh - 1 do
      if NewBw > 0 then
        Move(Comp[CI].Coef[(Y * Comp[CI].Bw) * 64], NewC[(Y * NewBw) * 64],
          NewBw * 64 * SizeOf(SmallInt));
    Comp[CI].Coef := NewC;
    NewC := nil;
    Comp[CI].Bw := NewBw;
  end;
end;

procedure TRotator.CutRows(NewH: Integer);
var
  CI, NewBh: Integer;
begin
  H := NewH;
  for CI := 0 to NComp - 1 do
  begin
    NewBh := (H div (8 * VMax)) * Comp[CI].V;
    SetLength(Comp[CI].Coef, NewBh * Comp[CI].Bw * 64);
    Comp[CI].Bh := NewBh;
  end;
end;

procedure TRotator.FlipH;
var
  CI, Y, X, I, A, B: Integer;
  T: SmallInt;
begin
  for CI := 0 to NComp - 1 do
    for Y := 0 to Comp[CI].Bh - 1 do
    begin
      for X := 0 to Comp[CI].Bw div 2 - 1 do
      begin
        A := (Y * Comp[CI].Bw + X) * 64;
        B := (Y * Comp[CI].Bw + (Comp[CI].Bw - 1 - X)) * 64;
        for I := 0 to 63 do
        begin
          T := Comp[CI].Coef[A + I];
          Comp[CI].Coef[A + I] := Comp[CI].Coef[B + I];
          Comp[CI].Coef[B + I] := T;
        end;
      end;
      // horizontal frequencies of odd index change sign
      for X := 0 to Comp[CI].Bw - 1 do
      begin
        A := (Y * Comp[CI].Bw + X) * 64;
        I := 1;
        while I < 64 do
        begin
          Comp[CI].Coef[A + I] := -Comp[CI].Coef[A + I];
          Inc(I, 2);
        end;
      end;
    end;
end;

procedure TRotator.FlipV;
var
  CI, Y, X, I, A, B: Integer;
  T: SmallInt;
begin
  for CI := 0 to NComp - 1 do
  begin
    for Y := 0 to Comp[CI].Bh div 2 - 1 do
      for X := 0 to Comp[CI].Bw - 1 do
      begin
        A := (Y * Comp[CI].Bw + X) * 64;
        B := ((Comp[CI].Bh - 1 - Y) * Comp[CI].Bw + X) * 64;
        for I := 0 to 63 do
        begin
          T := Comp[CI].Coef[A + I];
          Comp[CI].Coef[A + I] := Comp[CI].Coef[B + I];
          Comp[CI].Coef[B + I] := T;
        end;
      end;
    // vertical frequencies of odd index change sign
    for Y := 0 to Comp[CI].Bh - 1 do
      for X := 0 to Comp[CI].Bw - 1 do
      begin
        A := (Y * Comp[CI].Bw + X) * 64;
        for I := 8 to 63 do
          if ((I shr 3) and 1) = 1 then
            Comp[CI].Coef[A + I] := -Comp[CI].Coef[A + I];
      end;
  end;
end;

procedure TRotator.Transform(Orient: Integer; out Transposed: Boolean);
var
  Tr, Hf, Vf: Boolean;
begin
  Tr := Orient in [5, 6, 7, 8];
  Hf := Orient in [2, 3, 6, 7];
  Vf := Orient in [3, 4, 7, 8];
  Transposed := Tr;
  if Tr then Transpose;
  // partial blocks on a mirrored edge are dropped (jpegtran -trim)
  if Hf and ((W mod (8 * HMax)) <> 0) then
  begin
    if W < 8 * HMax then raise EJpegRot.Create('too small');
    CutColumns((W div (8 * HMax)) * (8 * HMax));
  end;
  if Vf and ((H mod (8 * VMax)) <> 0) then
  begin
    if H < 8 * VMax then raise EJpegRot.Create('too small');
    CutRows((H div (8 * VMax)) * (8 * VMax));
  end;
  if Hf then FlipH;
  if Vf then FlipV;
end;

procedure TRotator.Encode(Dest: TStream; Transposed: Boolean);
var
  I, J, Z, CI, VI, HI, MX, MY, McuX, McuY, Base, Diff, A, Sz, Run, V, Tb: Integer;
  Pred: array[0..2] of Integer;
  Nat: array[0..63] of Byte;
  Tmp: array[0..64] of Byte;
  Hdr: array[0..300] of Byte;
  Dc: array[0..1] of THuffEnc;
  Ac: array[0..1] of THuffEnc;
  BW: TBitWriter;
  Seg: TBytes;
  Mem: TMemoryStream;
  B: Byte;

  procedure PutHuff(Tc, Th: Integer; const Bits: array of Byte; const Vals: array of Byte);
  var
    N, K: Integer;
  begin
    N := 0;
    for K := 0 to 15 do Inc(N, Bits[K]);
    Hdr[0] := (Tc shl 4) or Th;
    for K := 0 to 15 do Hdr[1 + K] := Bits[K];
    for K := 0 to N - 1 do Hdr[17 + K] := Vals[K];
    WriteSeg(Mem, $C4, Hdr, 17 + N);
  end;

begin
  FillChar(Dc, SizeOf(Dc), 0);
  FillChar(Ac, SizeOf(Ac), 0);
  Mem := TMemoryStream.Create;
  BW := TBitWriter.Create;
  try
    B := $FF; Mem.WriteBuffer(B, 1);
    B := $D8; Mem.WriteBuffer(B, 1);
    for I := 0 to High(Segs) do
    begin
      Seg := Segs[I].Data;
      if Segs[I].Marker = $E1 then PatchOrientation(Seg);
      if Length(Seg) > 0 then
        WriteSeg(Mem, Segs[I].Marker, Seg, Length(Seg))
      else
        WriteSeg(Mem, Segs[I].Marker, Hdr, 0);
    end;
    for Tb := 0 to 3 do
      if HaveDqt[Tb] then
      begin
        for Z := 0 to 63 do Nat[ZZ[Z]] := Dqt[Tb, Z];
        Tmp[0] := Tb;
        if Transposed then
          for Z := 0 to 63 do
            Tmp[1 + Z] := Nat[(ZZ[Z] mod 8) * 8 + (ZZ[Z] div 8)]
        else
          for Z := 0 to 63 do
            Tmp[1 + Z] := Dqt[Tb, Z];
        WriteSeg(Mem, $DB, Tmp, 65);
      end;
    // frame header (baseline)
    Hdr[0] := 8;
    Hdr[1] := H shr 8; Hdr[2] := H and $FF;
    Hdr[3] := W shr 8; Hdr[4] := W and $FF;
    Hdr[5] := NComp;
    for CI := 0 to NComp - 1 do
    begin
      Hdr[6 + CI * 3] := Comp[CI].Id;
      Hdr[7 + CI * 3] := (Comp[CI].H shl 4) or Comp[CI].V;
      Hdr[8 + CI * 3] := Comp[CI].Tq;
    end;
    WriteSeg(Mem, $C0, Hdr, 6 + NComp * 3);
    PutHuff(0, 0, DcLumBits, DcLumVals);
    PutHuff(1, 0, AcLumBits, AcLumVals);
    BuildEnc(Dc[0], DcLumBits, DcLumVals);
    BuildEnc(Ac[0], AcLumBits, AcLumVals);
    if NComp > 1 then
    begin
      PutHuff(0, 1, DcChrBits, DcChrVals);
      PutHuff(1, 1, AcChrBits, AcChrVals);
      BuildEnc(Dc[1], DcChrBits, DcChrVals);
      BuildEnc(Ac[1], AcChrBits, AcChrVals);
    end;
    Hdr[0] := NComp;
    for CI := 0 to NComp - 1 do
    begin
      Hdr[1 + CI * 2] := Comp[CI].Id;
      if CI = 0 then Hdr[2 + CI * 2] := $00 else Hdr[2 + CI * 2] := $11;
    end;
    Hdr[1 + NComp * 2] := 0;
    Hdr[2 + NComp * 2] := 63;
    Hdr[3 + NComp * 2] := 0;
    WriteSeg(Mem, $DA, Hdr, 4 + NComp * 2);

    McuX := (W + 8 * HMax - 1) div (8 * HMax);
    McuY := (H + 8 * VMax - 1) div (8 * VMax);
    BW.Strm := Mem;
    BW.Acc := 0;
    BW.Cnt := 0;
    for I := 0 to 2 do Pred[I] := 0;
    for MY := 0 to McuY - 1 do
      for MX := 0 to McuX - 1 do
        for CI := 0 to NComp - 1 do
        begin
          J := 0;
          if CI > 0 then J := 1;
          for VI := 0 to Comp[CI].V - 1 do
            for HI := 0 to Comp[CI].H - 1 do
            begin
              Base := (((MY * Comp[CI].V + VI) * Comp[CI].Bw) + (MX * Comp[CI].H + HI)) * 64;
              Diff := Comp[CI].Coef[Base] - Pred[CI];
              Pred[CI] := Comp[CI].Coef[Base];
              A := Abs(Diff);
              Sz := BitCount(A);
              if Sz > 11 then raise EJpegRot.Create('DC too large');
              BW.Put(Dc[J].Code[Sz], Dc[J].Len[Sz]);
              if Sz > 0 then
              begin
                if Diff > 0 then V := Diff else V := Diff + (1 shl Sz) - 1;
                BW.Put(Cardinal(V), Sz);
              end;
              Run := 0;
              for Z := 1 to 63 do
              begin
                V := Comp[CI].Coef[Base + ZZ[Z]];
                if V = 0 then
                begin
                  Inc(Run);
                  Continue;
                end;
                while Run > 15 do
                begin
                  BW.Put(Ac[J].Code[$F0], Ac[J].Len[$F0]);
                  Dec(Run, 16);
                end;
                A := Abs(V);
                Sz := BitCount(A);
                if Sz > 10 then raise EJpegRot.Create('coefficient too large');
                BW.Put(Ac[J].Code[(Run shl 4) or Sz], Ac[J].Len[(Run shl 4) or Sz]);
                if V > 0 then Diff := V else Diff := V + (1 shl Sz) - 1;
                BW.Put(Cardinal(Diff), Sz);
                Run := 0;
              end;
              if Run > 0 then BW.Put(Ac[J].Code[0], Ac[J].Len[0]);
            end;
        end;
    BW.Finish;
    B := $FF; Mem.WriteBuffer(B, 1);
    B := $D9; Mem.WriteBuffer(B, 1);
    Mem.Position := 0;
    Dest.CopyFrom(Mem, Mem.Size);
  finally
    BW.Free;
    Mem.Free;
  end;
end;

function AutoRotateJpegFile(const FileName: string): Integer;
var
  Rot: TRotator;
  FS: TFileStream;
  Outp: TFileStream;
  Orient, N: Integer;
  Transposed: Boolean;
  TmpName, BakName: string;
  Age: LongInt;
begin
  Result := -1;
  Rot := TRotator.Create;
  try
    try
      FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        N := Integer(FS.Size);
        if (N < 100) or (N > 400 * 1024 * 1024) then Exit;
        SetLength(Rot.D, N);
        FS.ReadBuffer(Rot.D[0], N);
      finally
        FS.Free;
      end;
      Rot.Parse;
      Orient := Rot.Orientation;
      if (Orient < 2) or (Orient > 8) then
      begin
        Result := 0;
        Exit;
      end;
      Rot.DecodeScan;
      Rot.Transform(Orient, Transposed);
      TmpName := FileName + '.rot.tmp';
      Outp := TFileStream.Create(TmpName, fmCreate);
      try
        Rot.Encode(Outp, Transposed);
      finally
        Outp.Free;
      end;
      Age := FileAgeUTF8(FileName);
      BakName := FileName + '.rot.bak';
      DeleteFileUTF8(BakName);
      if not RenameFileUTF8(FileName, BakName) then
      begin
        DeleteFileUTF8(TmpName);
        Exit;
      end;
      if not RenameFileUTF8(TmpName, FileName) then
      begin
        RenameFileUTF8(BakName, FileName);   // put the original back
        DeleteFileUTF8(TmpName);
        Exit;
      end;
      DeleteFileUTF8(BakName);
      if Age <> -1 then FileSetDateUTF8(FileName, Age);
      Result := 1;
    except
      on E: Exception do
      begin
        DeleteFileUTF8(FileName + '.rot.tmp');
        Result := -1;
      end;
    end;
  finally
    Rot.Free;
  end;
end;

end.
