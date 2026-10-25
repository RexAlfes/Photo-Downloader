unit uExif;

{$mode objfpc}{$H+}

{ Minimal EXIF reader. Works on JPEG (APP1 segment) and on TIFF-based raw
  files (NEF, CR2, DNG, ARW ...) where the TIFF header is at offset 0. }

interface

uses
  Classes, SysUtils, LazFileUtils;

type
  TExifInfo = record
    Valid: Boolean;
    Make, Model, Artist, Owner, Serial: string;
    DateTaken: TDateTime;
    HasDate: Boolean;
    ISO: Integer;
    Orientation: Integer;
  end;

function ReadExifFromFile(const FileName: string; out Info: TExifInfo): Boolean;
{ Adds the EXIF Artist and/or Copyright tags to a JPEG file in place, but only
  for a field that is missing or empty in the file; existing values are never
  overwritten. Returns True if the file is now in the wanted state. }
function WriteExifOwnerFields(const FileName, Artist, Copyright: string): Boolean;
{ Largest picture size stored in a HEIC/HEIF file (its 'ispe' property), before any rotation. }
function ReadHeifStoredSize(const FileName: string; out W, H: Integer): Boolean;

{ Copies an embedded baseline/progressive JPEG (the preview RAW files carry) to Dest.
  Rank 0 is the largest one, 1 the next largest, and so on. W/H are its pixel size. }
function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Deep: Boolean;
  Dest: TStream; out W, H: Integer): Boolean;

{ Deep = False limits the search to the first 4 MB (used for TIFF and DNG, whose
  files can be huge); Deep = True may scan up to 96 MB (RAW files). }

type
  TInt64Array = array of Int64;
  { An uncompressed, chunky 8 or 16 bit grey or RGB image inside a TIFF/DNG file }
  TTiffRgb = record
    Big: Boolean;
    W, H, Bits, Spp, Photo, RowsPerStrip: Integer;
    Offsets: TInt64Array;
  end;

{ Finds the largest uncompressed grey/RGB image in a TIFF or DNG file (IFD chain and SubIFDs). }
function FindTiffRgb(const FileName: string; out R: TTiffRgb): Boolean;
{ Reads one row of that image into Buf. }
function ReadTiffRgbRow(Strm: TStream; const R: TTiffRgb; Row: Integer; var Buf: TBytes): Boolean;

{ Pixel size of a JPEG file, read from its header only. }
function ReadJpegDims(const FileName: string; out W, H: Integer): Boolean;

implementation

type
  TTiff = record
    Buf: TBytes;
    Base: Integer;
    Big: Boolean;
  end;

function U16(const T: TTiff; Ofs: Integer): Integer;
begin
  Result := 0;
  if (Ofs < 0) or (Ofs + 2 > Length(T.Buf)) then Exit;
  if T.Big then
    Result := (T.Buf[Ofs] shl 8) or T.Buf[Ofs + 1]
  else
    Result := T.Buf[Ofs] or (T.Buf[Ofs + 1] shl 8);
end;

function U32(const T: TTiff; Ofs: Integer): Int64;
var
  B0, B1, B2, B3: Int64;
begin
  Result := 0;
  if (Ofs < 0) or (Ofs + 4 > Length(T.Buf)) then Exit;
  B0 := T.Buf[Ofs]; B1 := T.Buf[Ofs + 1]; B2 := T.Buf[Ofs + 2]; B3 := T.Buf[Ofs + 3];
  if T.Big then
    Result := (B0 shl 24) or (B1 shl 16) or (B2 shl 8) or B3
  else
    Result := B0 or (B1 shl 8) or (B2 shl 16) or (B3 shl 24);
end;

function GetStr(const T: TTiff; E: Integer): string;
var
  Cnt, Off: Int64;
  P, I: Integer;
  B: Byte;
begin
  Result := '';
  Cnt := U32(T, E + 4);
  if Cnt <= 0 then Exit;
  if Cnt <= 4 then
    P := E + 8
  else
  begin
    Off := U32(T, E + 8);
    if Off + T.Base >= Length(T.Buf) then Exit;
    P := T.Base + Integer(Off);
  end;
  if (P < 0) or (P >= Length(T.Buf)) then Exit;
  if Cnt > 128 then Cnt := 128;
  for I := 0 to Integer(Cnt) - 1 do
  begin
    if P + I >= Length(T.Buf) then Break;
    B := T.Buf[P + I];
    if B = 0 then Break;
    Result := Result + Chr(B);
  end;
  Result := Trim(Result);
end;

function ParseExifDate(const S: string; out DT: TDateTime): Boolean;
var
  Y, M, D, H, N, Sec: Integer;
  Tm: TDateTime;
begin
  Result := False;
  DT := 0;
  if Length(S) < 19 then Exit;
  Y := StrToIntDef(Copy(S, 1, 4), 0);
  M := StrToIntDef(Copy(S, 6, 2), 0);
  D := StrToIntDef(Copy(S, 9, 2), 0);
  H := StrToIntDef(Copy(S, 12, 2), 0);
  N := StrToIntDef(Copy(S, 15, 2), 0);
  Sec := StrToIntDef(Copy(S, 18, 2), 0);
  if Y < 1900 then Exit;
  if not TryEncodeDate(Y, M, D, DT) then Exit;
  if not TryEncodeTime(H, N, Sec, 0, Tm) then Tm := 0;
  DT := DT + Tm;
  Result := True;
end;

procedure ReadIFD(const T: TTiff; IfdRel: Int64; Depth: Integer; var Info: TExifInfo);
var
  P, N, I, E, Tag: Integer;
  DT: TDateTime;
  S: string;
begin
  if (Depth > 3) or (IfdRel <= 0) or (IfdRel > Length(T.Buf)) then Exit;
  P := T.Base + Integer(IfdRel);
  if P + 2 > Length(T.Buf) then Exit;
  N := U16(T, P);
  if N > 300 then Exit;
  for I := 0 to N - 1 do
  begin
    E := P + 2 + I * 12;
    if E + 12 > Length(T.Buf) then Break;
    Tag := U16(T, E);
    case Tag of
      $010F: Info.Make := GetStr(T, E);
      $0110: Info.Model := GetStr(T, E);
      $013B: Info.Artist := GetStr(T, E);
      $0112: Info.Orientation := U16(T, E + 8);
      $0132:
        if not Info.HasDate then
        begin
          S := GetStr(T, E);
          if ParseExifDate(S, DT) then
          begin
            Info.DateTaken := DT;
            Info.HasDate := True;
          end;
        end;
      $9003:
        begin
          S := GetStr(T, E);
          if ParseExifDate(S, DT) then
          begin
            Info.DateTaken := DT;
            Info.HasDate := True;
          end;
        end;
      $8827: Info.ISO := U16(T, E + 8);
      $A430: Info.Owner := GetStr(T, E);
      $A431: Info.Serial := GetStr(T, E);
      $8769: ReadIFD(T, U32(T, E + 8), Depth + 1, Info);
    end;
  end;
end;

{ ---- stream helpers ---- }

function StreamRead(Strm: TStream; Ofs: Int64; var Buf; Count: Integer): Boolean;
begin
  Result := False;
  if (Ofs < 0) or (Count <= 0) or (Ofs + Count > Strm.Size) then Exit;
  Strm.Position := Ofs;
  Result := Strm.Read(Buf, Count) = Count;
end;

function StreamLE16(Strm: TStream; Ofs: Int64): Integer;
var
  B: array[0..1] of Byte;
begin
  Result := 0;
  B[0] := 0;
  B[1] := 0;
  if StreamRead(Strm, Ofs, B, 2) then Result := B[0] or (B[1] shl 8);
end;

function StreamLE32(Strm: TStream; Ofs: Int64): Int64;
var
  B: array[0..3] of Byte;
begin
  Result := 0;
  B[0] := 0;
  B[1] := 0;
  B[2] := 0;
  B[3] := 0;
  if StreamRead(Strm, Ofs, B, 4) then
    Result := Int64(B[0]) or (Int64(B[1]) shl 8) or (Int64(B[2]) shl 16) or (Int64(B[3]) shl 24);
end;

function RdU16(Strm: TStream; Big: Boolean; Ofs: Int64): Integer;
var
  B: array[0..1] of Byte;
begin
  Result := 0;
  B[0] := 0;
  B[1] := 0;
  if StreamRead(Strm, Ofs, B, 2) then
    if Big then Result := (B[0] shl 8) or B[1] else Result := B[0] or (B[1] shl 8);
end;

function RdU32(Strm: TStream; Big: Boolean; Ofs: Int64): Int64;
var
  B: array[0..3] of Byte;
begin
  Result := 0;
  B[0] := 0;
  B[1] := 0;
  B[2] := 0;
  B[3] := 0;
  if StreamRead(Strm, Ofs, B, 4) then
  begin
    if Big then
      Result := (Int64(B[0]) shl 24) or (Int64(B[1]) shl 16) or (Int64(B[2]) shl 8) or Int64(B[3])
    else
      Result := Int64(B[0]) or (Int64(B[1]) shl 8) or (Int64(B[2]) shl 16) or (Int64(B[3]) shl 24);
  end;
end;

{ ---- Canon CRW (CIFF container, not TIFF) ---- }

procedure CiffWalk(Strm: TStream; Start, Stop: Int64; Depth: Integer; var Info: TExifInfo);
var
  Tbl, P, RecLen, RecOff, DataPos, T: Int64;
  N, I, K, Cnt, Code, Typ, TagId: Integer;
  Buf: array[0..95] of Byte;
  S1, S2: string;
  InlineRec: Boolean;
begin
  if (Depth > 6) or (Stop - Start < 10) then Exit;
  Tbl := Start + StreamLE32(Strm, Stop - 4);       // record table offset sits in the last 4 bytes
  if (Tbl < Start) or (Tbl + 2 > Stop) then Exit;
  N := StreamLE16(Strm, Tbl);
  if (N > 300) or (Tbl + 2 + N * 10 > Stop) then Exit;
  for I := 0 to N - 1 do
  begin
    P := Tbl + 2 + I * 10;
    Code := StreamLE16(Strm, P);
    RecLen := StreamLE32(Strm, P + 2);
    RecOff := StreamLE32(Strm, P + 6);
    Typ := Code and $3800;
    TagId := Code and $3FFF;
    InlineRec := (Code and $C000) = $4000;
    if (not InlineRec) and ((Typ = $2800) or (Typ = $3000)) then
      CiffWalk(Strm, Start + RecOff, Start + RecOff + RecLen, Depth + 1, Info)   // sub directory
    else
    begin
      if InlineRec then
      begin
        DataPos := P + 2;
        RecLen := 8;
      end
      else
        DataPos := Start + RecOff;
      if TagId = $080A then
      begin
        // camera make and model: two NUL terminated strings
        Cnt := Integer(RecLen);
        if Cnt > SizeOf(Buf) then Cnt := SizeOf(Buf);
        for K := 0 to High(Buf) do Buf[K] := 0;
        if StreamRead(Strm, DataPos, Buf, Cnt) then
        begin
          S1 := '';
          K := 0;
          while (K < Cnt) and (Buf[K] <> 0) do
          begin
            S1 := S1 + Chr(Buf[K]);
            Inc(K);
          end;
          Inc(K);
          S2 := '';
          while (K < Cnt) and (Buf[K] <> 0) do
          begin
            S2 := S2 + Chr(Buf[K]);
            Inc(K);
          end;
          Info.Make := Trim(S1);
          Info.Model := Trim(S2);
        end;
      end
      else if (TagId = $180E) and (RecLen >= 4) then
      begin
        // capture time stored as seconds since 1970
        T := StreamLE32(Strm, DataPos);
        if T > 0 then
        begin
          Info.DateTaken := EncodeDate(1970, 1, 1) + T / 86400;
          Info.HasDate := True;
        end;
      end;
    end;
  end;
end;

function IsCiff(const B: TBytes): Boolean;
begin
  Result := (Length(B) >= 14) and (B[6] = Ord('H')) and (B[7] = Ord('E')) and
    (B[8] = Ord('A')) and (B[9] = Ord('P')) and (B[10] = Ord('C')) and
    (B[11] = Ord('C')) and (B[12] = Ord('D')) and (B[13] = Ord('R'));
end;

function ReadCiffFromFile(const FileName: string; var Info: TExifInfo): Boolean;
var
  Strm: TFileStream;
  HL: Int64;
begin
  Result := False;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    HL := StreamLE32(Strm, 2);                       // header length = start of the root heap
    if (HL < 14) or (HL >= Strm.Size) then Exit;
    CiffWalk(Strm, HL, Strm.Size, 0, Info);
    Result := (Info.Model <> '') or Info.HasDate;
  finally
    Strm.Free;
  end;
end;

{ ---- uncompressed TIFF / DNG image data (used for thumbnails) ---- }

type
  TTiffWalk = record
    Strm: TStream;
    Big: Boolean;
    Size: Int64;
    Seen: array of Int64;
    Best: TTiffRgb;
    Found: Boolean;
  end;

{ reads the integer values of one IFD entry (BYTE, SHORT, LONG, IFD types) }
function ReadTagInts(Strm: TStream; Big: Boolean; E: Int64; MaxN: Integer;
  out V: TInt64Array): Boolean;
var
  Typ, Sz, I: Integer;
  Cnt, Total, Src: Int64;
  Raw: TBytes;
begin
  Result := False;
  V := nil;
  Raw := nil;
  Typ := RdU16(Strm, Big, E + 2);
  Cnt := RdU32(Strm, Big, E + 4);
  case Typ of
    1, 6, 7: Sz := 1;
    3, 8: Sz := 2;
    4, 9, 13: Sz := 4;
  else
    Exit;
  end;
  if (Cnt < 1) or (Cnt > MaxN) then Exit;
  Total := Cnt * Sz;
  if Total <= 4 then Src := E + 8 else Src := RdU32(Strm, Big, E + 8);
  SetLength(Raw, Integer(Total));
  if not StreamRead(Strm, Src, Raw[0], Integer(Total)) then Exit;
  SetLength(V, Integer(Cnt));
  for I := 0 to Integer(Cnt) - 1 do
    case Sz of
      1: V[I] := Raw[I];
      2: if Big then V[I] := (Raw[I * 2] shl 8) or Raw[I * 2 + 1]
         else V[I] := Raw[I * 2] or (Raw[I * 2 + 1] shl 8);
    else
      if Big then
        V[I] := (Int64(Raw[I * 4]) shl 24) or (Int64(Raw[I * 4 + 1]) shl 16) or
                (Int64(Raw[I * 4 + 2]) shl 8) or Int64(Raw[I * 4 + 3])
      else
        V[I] := Int64(Raw[I * 4]) or (Int64(Raw[I * 4 + 1]) shl 8) or
                (Int64(Raw[I * 4 + 2]) shl 16) or (Int64(Raw[I * 4 + 3]) shl 24);
    end;
  Result := True;
end;

procedure TiffWalkIfd(var Ctx: TTiffWalk; Off: Int64; Depth: Integer);
var
  N, I, K, Tag: Integer;
  E, W, H, Comp, Photo, Spp, Rps, Planar, Next: Int64;
  V, Offs, Subs, BitsA: TInt64Array;
  HavePredictor, BitsOk: Boolean;
begin
  if (Off < 8) or (Off + 2 > Ctx.Size) or (Depth > 6) or (Length(Ctx.Seen) >= 24) then Exit;
  for I := 0 to High(Ctx.Seen) do
    if Ctx.Seen[I] = Off then Exit;
  SetLength(Ctx.Seen, Length(Ctx.Seen) + 1);
  Ctx.Seen[High(Ctx.Seen)] := Off;
  N := RdU16(Ctx.Strm, Ctx.Big, Off);
  if (N < 1) or (N > 400) then Exit;

  W := 0; H := 0; Comp := 1; Photo := -1; Spp := 1; Rps := 0; Planar := 1;
  HavePredictor := False;
  V := nil; Offs := nil; Subs := nil; BitsA := nil;
  for I := 0 to N - 1 do
  begin
    E := Off + 2 + I * 12;
    Tag := RdU16(Ctx.Strm, Ctx.Big, E);
    case Tag of
      $0100: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then W := V[0];
      $0101: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then H := V[0];
      $0102: ReadTagInts(Ctx.Strm, Ctx.Big, E, 4, BitsA);
      $0103: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Comp := V[0];
      $0106: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Photo := V[0];
      $0111: ReadTagInts(Ctx.Strm, Ctx.Big, E, 100000, Offs);
      $0115: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Spp := V[0];
      $0116: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Rps := V[0];
      $011C: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Planar := V[0];
      $013D: HavePredictor := True;
      $014A: ReadTagInts(Ctx.Strm, Ctx.Big, E, 16, Subs);
    end;
  end;

  // is this an image we can read directly?
  BitsOk := Length(BitsA) >= 1;
  if BitsOk then
  begin
    for K := 1 to High(BitsA) do
      if BitsA[K] <> BitsA[0] then BitsOk := False;
    if (BitsA[0] <> 8) and (BitsA[0] <> 16) then BitsOk := False;
    if (Length(BitsA) <> Spp) and (Length(BitsA) <> 1) then BitsOk := False;
  end;
  if (Rps <= 0) or (Rps > H) then Rps := H;
  if (W > 0) and (H > 0) and (Comp = 1) and (Planar = 1) and (not HavePredictor) and BitsOk and
     ((Spp = 1) or (Spp = 3)) and ((Photo = 0) or (Photo = 1) or (Photo = 2)) and
     ((Photo = 2) = (Spp = 3)) and (Length(Offs) > 0) and
     (Int64(Length(Offs)) >= (H + Rps - 1) div Rps) then
  begin
    if (not Ctx.Found) or (W * H > Int64(Ctx.Best.W) * Ctx.Best.H) then
    begin
      Ctx.Found := True;
      Ctx.Best.Big := Ctx.Big;
      Ctx.Best.W := Integer(W);
      Ctx.Best.H := Integer(H);
      Ctx.Best.Bits := Integer(BitsA[0]);
      Ctx.Best.Spp := Integer(Spp);
      Ctx.Best.Photo := Integer(Photo);
      Ctx.Best.RowsPerStrip := Integer(Rps);
      Ctx.Best.Offsets := Offs;
    end;
  end;

  for K := 0 to High(Subs) do
    TiffWalkIfd(Ctx, Subs[K], Depth + 1);
  Next := RdU32(Ctx.Strm, Ctx.Big, Off + 2 + N * 12);
  TiffWalkIfd(Ctx, Next, Depth);
end;

function FindTiffRgb(const FileName: string; out R: TTiffRgb): Boolean;
var
  Ctx: TTiffWalk;
  Strm: TFileStream;
  Hdr: array[0..7] of Byte;
begin
  Result := False;
  R.Big := False;
  R.W := 0;
  R.H := 0;
  R.Bits := 0;
  R.Spp := 0;
  R.Photo := 0;
  R.RowsPerStrip := 1;
  R.Offsets := nil;
  Ctx.Strm := nil;
  Ctx.Big := False;
  Ctx.Size := 0;
  Ctx.Seen := nil;
  Ctx.Found := False;
  Ctx.Best.Big := False;
  Ctx.Best.W := 0;
  Ctx.Best.H := 0;
  Ctx.Best.Bits := 0;
  Ctx.Best.Spp := 0;
  Ctx.Best.Photo := 0;
  Ctx.Best.RowsPerStrip := 1;
  Ctx.Best.Offsets := nil;
  Hdr[0] := 0;
  Hdr[1] := 0;
  Hdr[2] := 0;
  Hdr[3] := 0;
  Hdr[4] := 0;
  Hdr[5] := 0;
  Hdr[6] := 0;
  Hdr[7] := 0;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Ctx.Strm := Strm;
    Ctx.Size := Strm.Size;
    if not StreamRead(Strm, 0, Hdr, 8) then Exit;
    if (Hdr[0] = $49) and (Hdr[1] = $49) then Ctx.Big := False
    else if (Hdr[0] = $4D) and (Hdr[1] = $4D) then Ctx.Big := True
    else Exit;
    if RdU16(Strm, Ctx.Big, 2) <> 42 then Exit;
    TiffWalkIfd(Ctx, RdU32(Strm, Ctx.Big, 4), 0);
  finally
    Strm.Free;
  end;
  if Ctx.Found then
  begin
    R := Ctx.Best;
    Result := True;
  end;
end;

function ReadTiffRgbRow(Strm: TStream; const R: TTiffRgb; Row: Integer; var Buf: TBytes): Boolean;
var
  RowBytes, Strip: Integer;
  Ofs: Int64;
begin
  Result := False;
  if (Row < 0) or (Row >= R.H) or (R.RowsPerStrip < 1) then Exit;
  RowBytes := R.W * R.Spp * (R.Bits div 8);
  Strip := Row div R.RowsPerStrip;
  if Strip > High(R.Offsets) then Exit;
  Ofs := R.Offsets[Strip] + Int64(Row mod R.RowsPerStrip) * RowBytes;
  if Length(Buf) < RowBytes then SetLength(Buf, RowBytes);
  Result := StreamRead(Strm, Ofs, Buf[0], RowBytes);
end;


{ ---- ISO base media files: Canon CR3 and HEIC/HEIF ---- }

function BoxHeader(Strm: TStream; Pos, Stop: Int64; out Typ: string;
  out Payload, BoxEnd: Int64): Boolean;
var
  Sz: Int64;
  B: array[0..3] of Byte;
  I: Integer;
begin
  Result := False;
  Typ := '';
  Payload := 0;
  BoxEnd := 0;
  if Pos + 8 > Stop then Exit;
  Sz := RdU32(Strm, True, Pos);
  B[0] := 0; B[1] := 0; B[2] := 0; B[3] := 0;
  if not StreamRead(Strm, Pos + 4, B, 4) then Exit;
  for I := 0 to 3 do Typ := Typ + Chr(B[I]);
  Payload := Pos + 8;
  if Sz = 1 then
  begin
    Sz := RdU32(Strm, True, Pos + 8) * 4294967296 + RdU32(Strm, True, Pos + 12);
    Payload := Pos + 16;
  end
  else if Sz = 0 then
    Sz := Stop - Pos;
  if Sz < 8 then Exit;
  BoxEnd := Pos + Sz;
  if BoxEnd > Stop then BoxEnd := Stop;
  Result := Payload <= BoxEnd;
end;

function FindChild(Strm: TStream; Start, Stop: Int64; const Want: string;
  out Payload, BoxEnd: Int64): Boolean;
var
  P, PL, BE: Int64;
  Typ: string;
  Guard: Integer;
begin
  Result := False;
  Payload := 0;
  BoxEnd := 0;
  P := Start;
  Guard := 0;
  while (Guard < 4096) and BoxHeader(Strm, P, Stop, Typ, PL, BE) do
  begin
    if Typ = Want then
    begin
      Payload := PL;
      BoxEnd := BE;
      Result := True;
      Exit;
    end;
    if BE <= P then Break;
    P := BE;
    Inc(Guard);
  end;
end;

{ copies a TIFF structure (II*/MM*) from the file into T, with Base = 0 }
function LoadTiffBlock(Strm: TStream; Ofs, Count: Int64; out T: TTiff): Boolean;
begin
  Result := False;
  T.Buf := nil;
  T.Base := 0;
  T.Big := False;
  if (Count < 16) or (Count > 1048576) then Exit;
  SetLength(T.Buf, Integer(Count));
  if not StreamRead(Strm, Ofs, T.Buf[0], Integer(Count)) then Exit;
  if (T.Buf[0] = $4D) and (T.Buf[1] = $4D) then
    T.Big := True
  else if not ((T.Buf[0] = $49) and (T.Buf[1] = $49)) then
    Exit;
  Result := U16(T, 2) = 42;
end;

{ the Canon-specific string tag 0x0096 (body serial) from a maker note block }
function CanonMakerSerial(const T: TTiff): string;
var
  P, N, I, E: Integer;
begin
  Result := '';
  P := Integer(U32(T, 4));
  if (P <= 0) or (P + 2 > Length(T.Buf)) then Exit;
  N := U16(T, P);
  if N > 300 then Exit;
  for I := 0 to N - 1 do
  begin
    E := P + 2 + I * 12;
    if E + 12 > Length(T.Buf) then Break;
    if U16(T, E) = $0096 then
    begin
      Result := GetStr(T, E);
      Exit;
    end;
  end;
end;

function ReadCr3Exif(Strm: TStream; MoovStart, MoovEnd: Int64; var Info: TExifInfo): Boolean;
const
  CanonUuid: array[0..15] of Byte =
    ($85, $C0, $B6, $87, $82, $0F, $11, $E0, $81, $11, $F4, $CE, $46, $2B, $6A, $48);
var
  P, PL, BE, CP, CE: Int64;
  Typ: string;
  U: array[0..15] of Byte;
  I, Guard: Integer;
  Same: Boolean;
  T: TTiff;
begin
  Result := False;
  P := MoovStart;
  Guard := 0;
  while (Guard < 256) and BoxHeader(Strm, P, MoovEnd, Typ, PL, BE) do
  begin
    Inc(Guard);
    if Typ = 'uuid' then
    begin
      for I := 0 to 15 do U[I] := 0;
      Same := StreamRead(Strm, PL, U, 16);
      if Same then
        for I := 0 to 15 do
          if U[I] <> CanonUuid[I] then Same := False;
      if Same then
      begin
        // CMT1 = TIFF IFD0, CMT2 = EXIF IFD, CMT3 = Canon maker note
        if FindChild(Strm, PL + 16, BE, 'CMT1', CP, CE) and LoadTiffBlock(Strm, CP, CE - CP, T) then
          ReadIFD(T, U32(T, 4), 0, Info);
        if FindChild(Strm, PL + 16, BE, 'CMT2', CP, CE) and LoadTiffBlock(Strm, CP, CE - CP, T) then
          ReadIFD(T, U32(T, 4), 0, Info);
        if (Info.Serial = '') and FindChild(Strm, PL + 16, BE, 'CMT3', CP, CE) and
           LoadTiffBlock(Strm, CP, CE - CP, T) then
          Info.Serial := CanonMakerSerial(T);
        Result := True;
        Exit;
      end;
    end;
    if BE <= P then Break;
    P := BE;
  end;
end;

function RdN(Strm: TStream; Ofs: Int64; N: Integer): Int64;
begin
  case N of
    4: Result := RdU32(Strm, True, Ofs);
    8: Result := RdU32(Strm, True, Ofs) * 4294967296 + RdU32(Strm, True, Ofs + 4);
  else
    Result := 0;
  end;
end;

function ReadHeifExif(Strm: TStream; MetaStart, MetaEnd: Int64; var Info: TExifInfo): Boolean;
var
  IinfP, IinfE, IlocP, IlocE, P, PL, BE, Q, ExtOfs, ExtLen, BaseOfs, ExtOne, HdrOfs: Int64;
  Typ: string;
  Ver, Cnt, I, J, OffSz, LenSz, BaseSz, IdxSz, K, ExtCnt: Integer;
  ExifId, ItemId: Int64;
  B: array[0..3] of Byte;
  T: TTiff;
  Guard: Integer;
begin
  Result := False;
  if not FindChild(Strm, MetaStart, MetaEnd, 'iinf', IinfP, IinfE) then Exit;
  if not FindChild(Strm, MetaStart, MetaEnd, 'iloc', IlocP, IlocE) then Exit;

  // 1. item id of the Exif item
  ExifId := -1;
  B[0] := 0; B[1] := 0; B[2] := 0; B[3] := 0;
  StreamRead(Strm, IinfP, B, 1);
  if B[0] = 0 then P := IinfP + 4 + 2 else P := IinfP + 4 + 4;
  Guard := 0;
  while (Guard < 4096) and BoxHeader(Strm, P, IinfE, Typ, PL, BE) do
  begin
    Inc(Guard);
    if Typ = 'infe' then
    begin
      B[0] := 0;
      StreamRead(Strm, PL, B, 1);
      if B[0] = 2 then
      begin
        ItemId := RdU16(Strm, True, PL + 4);
        K := 8;
      end
      else if B[0] = 3 then
      begin
        ItemId := RdU32(Strm, True, PL + 4);
        K := 10;
      end
      else
      begin
        ItemId := -1;
        K := 0;
      end;
      if (ItemId >= 0) and StreamRead(Strm, PL + K, B, 4) then
        if (B[0] = Ord('E')) and (B[1] = Ord('x')) and (B[2] = Ord('i')) and (B[3] = Ord('f')) then
        begin
          ExifId := ItemId;
          Break;
        end;
    end;
    if BE <= P then Break;
    P := BE;
  end;
  if ExifId < 0 then Exit;

  // 2. its location (iloc, construction method 0 = offset in the file)
  B[0] := 0;
  StreamRead(Strm, IlocP, B, 1);
  Ver := B[0];
  if Ver > 2 then Exit;
  StreamRead(Strm, IlocP + 4, B, 2);
  OffSz := B[0] shr 4;
  LenSz := B[0] and 15;
  BaseSz := B[1] shr 4;
  if Ver = 0 then IdxSz := 0 else IdxSz := B[1] and 15;
  if Ver < 2 then
  begin
    Cnt := RdU16(Strm, True, IlocP + 6);
    Q := IlocP + 8;
  end
  else
  begin
    Cnt := Integer(RdU32(Strm, True, IlocP + 6));
    Q := IlocP + 10;
  end;
  if Cnt > 20000 then Exit;
  for I := 0 to Cnt - 1 do
  begin
    if Ver < 2 then
    begin
      ItemId := RdU16(Strm, True, Q);
      Inc(Q, 2);
    end
    else
    begin
      ItemId := RdU32(Strm, True, Q);
      Inc(Q, 4);
    end;
    if Ver >= 1 then
    begin
      K := RdU16(Strm, True, Q) and 15;   // construction method
      Inc(Q, 2);
    end
    else
      K := 0;
    Inc(Q, 2);                             // data reference index
    BaseOfs := RdN(Strm, Q, BaseSz);
    Inc(Q, BaseSz);
    ExtCnt := RdU16(Strm, True, Q);
    Inc(Q, 2);
    ExtOne := -1;
    ExtLen := 0;
    for J := 0 to ExtCnt - 1 do
    begin
      if IdxSz > 0 then Inc(Q, IdxSz);
      ExtOfs := RdN(Strm, Q, OffSz);
      Inc(Q, OffSz);
      ExtLen := RdN(Strm, Q, LenSz);
      Inc(Q, LenSz);
      if J = 0 then ExtOne := BaseOfs + ExtOfs;
    end;
    if (ItemId = ExifId) and (K = 0) and (ExtOne >= 0) and (ExtLen > 8) then
    begin
      // payload = 4 byte offset to the TIFF header, then the data
      HdrOfs := RdU32(Strm, True, ExtOne);
      if (HdrOfs < 0) or (HdrOfs + 4 >= ExtLen) then Exit;
      if LoadTiffBlock(Strm, ExtOne + 4 + HdrOfs, ExtLen - 4 - HdrOfs, T) then
      begin
        ReadIFD(T, U32(T, 4), 0, Info);
        Result := True;
      end;
      Exit;
    end;
  end;
end;

{ Canon CR3 and HEIC/HEIF: EXIF data from the container boxes }
function ReadBmffFromFile(const FileName: string; var Info: TExifInfo): Boolean;
var
  Strm: TFileStream;
  Size, P, PL, BE: Int64;
  Typ: string;
  Guard: Integer;
begin
  Result := False;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Size := Strm.Size;
    P := 0;
    Guard := 0;
    while (Guard < 64) and BoxHeader(Strm, P, Size, Typ, PL, BE) do
    begin
      Inc(Guard);
      if Typ = 'moov' then
        ReadCr3Exif(Strm, PL, BE, Info)
      else if Typ = 'meta' then
        ReadHeifExif(Strm, PL + 4, BE, Info);
      if BE <= P then Break;
      P := BE;
    end;
  finally
    Strm.Free;
  end;
  Result := (Info.Make <> '') or (Info.Model <> '') or Info.HasDate;
end;

function ReadHeifStoredSize(const FileName: string; out W, H: Integer): Boolean;
var
  Strm: TFileStream;
  Size, P, PL, BE, IP, IE, CP, CE, Q, QL, QE, AW, AH, Best: Int64;
  Typ, Typ2: string;
  Guard, G2: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Size := Strm.Size;
    P := 0;
    Guard := 0;
    while (Guard < 64) and BoxHeader(Strm, P, Size, Typ, PL, BE) do
    begin
      Inc(Guard);
      if Typ = 'meta' then
        if FindChild(Strm, PL + 4, BE, 'iprp', IP, IE) and FindChild(Strm, IP, IE, 'ipco', CP, CE) then
        begin
          Q := CP;
          G2 := 0;
          Best := 0;
          while (G2 < 4096) and BoxHeader(Strm, Q, CE, Typ2, QL, QE) do
          begin
            Inc(G2);
            if Typ2 = 'ispe' then
            begin
              AW := RdU32(Strm, True, QL + 4);
              AH := RdU32(Strm, True, QL + 8);
              if AW * AH > Best then
              begin
                Best := AW * AH;
                W := Integer(AW);
                H := Integer(AH);
              end;
            end;
            if QE <= Q then Break;
            Q := QE;
          end;
          Result := Best > 0;
          Exit;
        end;
      if BE <= P then Break;
      P := BE;
    end;
  finally
    Strm.Free;
  end;
end;

function ReadExifFromFile(const FileName: string; out Info: TExifInfo): Boolean;
var
  FS: TFileStream;
  Len, Pos, Mk, L: Integer;
  T: TTiff;
begin
  Result := False;
  T.Buf := nil;
  T.Base := -1;
  T.Big := False;
  Info.Valid := False;
  Info.Make := ''; Info.Model := ''; Info.Artist := ''; Info.Owner := '';
  Info.Serial := ''; Info.DateTaken := 0; Info.HasDate := False;
  Info.ISO := 0; Info.Orientation := 0;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Len := FS.Size;
    if Len > 262144 then Len := 262144;
    SetLength(T.Buf, Len);
    if Len > 0 then FS.ReadBuffer(T.Buf[0], Len);
  finally
    FS.Free;
  end;
  if Len < 12 then Exit;

  if IsCiff(T.Buf) then
  begin
    // Canon CRW is not a TIFF file: read make, model and time from its CIFF directories
    Info.Valid := ReadCiffFromFile(FileName, Info);
    Result := Info.Valid;
    Exit;
  end;

  if (T.Buf[4] = Ord('f')) and (T.Buf[5] = Ord('t')) and (T.Buf[6] = Ord('y')) and
     (T.Buf[7] = Ord('p')) then
  begin
    // Canon CR3 and HEIC/HEIF are ISO base media files
    Info.Valid := ReadBmffFromFile(FileName, Info);
    Result := Info.Valid;
    Exit;
  end;

  T.Base := -1;
  if (T.Buf[0] = $FF) and (T.Buf[1] = $D8) then
  begin
    Pos := 2;
    while Pos + 4 <= Len do
    begin
      if T.Buf[Pos] <> $FF then Break;
      Mk := T.Buf[Pos + 1];
      if Mk = $FF then begin Inc(Pos); Continue; end;
      if (Mk = $D9) or (Mk = $DA) then Break;
      L := (T.Buf[Pos + 2] shl 8) or T.Buf[Pos + 3];
      if (Mk = $E1) and (Pos + 10 <= Len) and (T.Buf[Pos + 4] = Ord('E')) and
         (T.Buf[Pos + 5] = Ord('x')) and (T.Buf[Pos + 6] = Ord('i')) and
         (T.Buf[Pos + 7] = Ord('f')) then
      begin
        T.Base := Pos + 10;
        Break;
      end;
      Pos := Pos + 2 + L;
    end;
  end
  else if ((T.Buf[0] = $49) and (T.Buf[1] = $49)) or
          ((T.Buf[0] = $4D) and (T.Buf[1] = $4D)) then
    T.Base := 0;

  if (T.Base < 0) or (T.Base + 8 > Len) then Exit;
  T.Big := T.Buf[T.Base] = $4D;
  if U16(T, T.Base + 2) <> 42 then Exit;
  ReadIFD(T, U32(T, T.Base + 4), 0, Info);
  Info.Valid := (Info.Make <> '') or (Info.Model <> '') or Info.HasDate;
  Result := Info.Valid;
end;

{ ---- JPEG helpers (previews and thumbnails) ---- }

function IsUsableSof(Mk: Integer): Boolean;
begin
  // baseline, extended sequential, progressive; not lossless (C3) as used for raw data
  Result := (Mk = $C0) or (Mk = $C1) or (Mk = $C2);
end;

function JpegDims(const B: TBytes; Start, Limit: Integer; out W, H, Comps: Integer): Boolean;
var
  P, Mk, L: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  Comps := 0;
  P := Start + 2;
  while P + 4 <= Limit do
  begin
    if B[P] <> $FF then Exit;
    Mk := B[P + 1];
    if Mk = $FF then begin Inc(P); Continue; end;
    if (Mk = $01) or ((Mk >= $D0) and (Mk <= $D8)) then begin Inc(P, 2); Continue; end;
    if (Mk = $D9) or (Mk = $DA) then Exit;
    L := (B[P + 2] shl 8) or B[P + 3];
    if L < 2 then Exit;
    if IsUsableSof(Mk) then
    begin
      if P + 10 > Limit then Exit;
      H := (B[P + 5] shl 8) or B[P + 6];
      W := (B[P + 7] shl 8) or B[P + 8];
      Comps := B[P + 9];
      Result := (W > 0) and (H > 0);
      Exit;
    end;
    P := P + 2 + L;
  end;
end;

{ returns the offset just after the EOI marker of the JPEG that starts at Start, or -1 }
function JpegEnd(const B: TBytes; Start, Limit: Integer): Integer;
var
  P, Mk, L: Integer;
  SawSof: Boolean;
begin
  Result := -1;
  SawSof := False;
  P := Start + 2;
  while P + 2 <= Limit do
  begin
    if B[P] <> $FF then Exit;
    Mk := B[P + 1];
    if Mk = $FF then begin Inc(P); Continue; end;
    if (Mk = $01) or ((Mk >= $D0) and (Mk <= $D7)) then begin Inc(P, 2); Continue; end;
    if Mk = $D9 then
    begin
      if SawSof then Result := P + 2;
      Exit;
    end;
    if P + 4 > Limit then Exit;
    L := (B[P + 2] shl 8) or B[P + 3];
    if L < 2 then Exit;
    if IsUsableSof(Mk) then SawSof := True;
    if Mk = $DA then
    begin
      if not SawSof then Exit;
      P := P + 2 + L;
      // entropy coded data: runs until a marker that is not a restart or stuffed FF 00
      while P + 1 < Limit do
      begin
        if (B[P] = $FF) and (B[P + 1] <> 0) and (B[P + 1] <> $FF) and
           not ((B[P + 1] >= $D0) and (B[P + 1] <= $D7)) then Break;
        Inc(P);
      end;
      if P + 1 >= Limit then Exit;
      Continue;
    end;
    P := P + 2 + L;
  end;
end;

function ReadJpegDims(const FileName: string; out W, H: Integer): Boolean;
var
  Strm: TFileStream;
  Buf: TBytes;
  Len, Comps: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  Buf := nil;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Len := Strm.Size;
    if Len > 262144 then Len := 262144;
    SetLength(Buf, Len);
    if Len > 0 then Strm.ReadBuffer(Buf[0], Len);
  finally
    Strm.Free;
  end;
  if (Len < 12) or (Buf[0] <> $FF) or (Buf[1] <> $D8) then Exit;
  Result := JpegDims(Buf, 0, Len, W, H, Comps);
end;

type
  TJpegCand = record
    Pos, Len, W, H, Comps: Integer;
  end;
  TJpegCands = array of TJpegCand;

{ reads up to MaxBytes from the start of the file; returns the number of bytes read }
function ReadPrefix(const FileName: string; MaxBytes: Integer; out Buf: TBytes;
  out FileLen: Int64): Integer;
var
  Strm: TFileStream;
begin
  Result := 0;
  Buf := nil;
  FileLen := 0;
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    FileLen := Strm.Size;
    if FileLen > MaxBytes then Result := MaxBytes else Result := Integer(FileLen);
    SetLength(Buf, Result);
    if Result > 0 then Strm.ReadBuffer(Buf[0], Result);
  finally
    Strm.Free;
  end;
end;

procedure FindJpegs(const B: TBytes; Len: Integer; var C: TJpegCands);
var
  P, E, CW, CH, CC, N, I, K: Integer;
  HaveColor: Boolean;
begin
  C := nil;
  N := 0;
  P := 0;
  while P + 4 < Len do
  begin
    if (B[P] = $FF) and (B[P + 1] = $D8) and (B[P + 2] = $FF) then
    begin
      E := JpegEnd(B, P, Len);
      if E > P then
      begin
        if JpegDims(B, P, Len, CW, CH, CC) then
        begin
          SetLength(C, N + 1);
          C[N].Pos := P;
          C[N].Len := E - P;
          C[N].W := CW;
          C[N].H := CH;
          C[N].Comps := CC;
          Inc(N);
          if N >= 24 then Break;
        end;
        P := E;            // skip this JPEG, including any thumbnail nested inside it
        Continue;
      end;
    end;
    Inc(P);
  end;
  // Some RAW formats (Canon CRW) store the sensor data as a single-component JPEG,
  // which looks like a huge grey image. When colour previews exist, ignore those.
  HaveColor := False;
  for I := 0 to High(C) do
    if C[I].Comps = 3 then HaveColor := True;
  if HaveColor then
  begin
    K := 0;
    for I := 0 to High(C) do
      if C[I].Comps = 3 then
      begin
        C[K] := C[I];
        Inc(K);
      end;
    SetLength(C, K);
  end;
end;

function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Deep: Boolean;
  Dest: TStream; out W, H: Integer): Boolean;
var
  Buf: TBytes;
  Got, I, J: Integer;
  FLen: Int64;
  C: TJpegCands;
  Tmp: TJpegCand;
  BestLen: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  Buf := nil;
  C := nil;
  Got := ReadPrefix(FileName, 4 * 1024 * 1024, Buf, FLen);
  if Got = 0 then Exit;
  FindJpegs(Buf, Got, C);
  BestLen := 0;
  for I := 0 to High(C) do
    if C[I].Len > BestLen then BestLen := C[I].Len;
  // nothing sizeable in the first 4 MB: some cameras store the preview later in the file
  if Deep and (BestLen < 20000) and (FLen > Got) then
  begin
    Got := ReadPrefix(FileName, 96 * 1024 * 1024, Buf, FLen);
    FindJpegs(Buf, Got, C);
  end;
  // largest first
  for I := 1 to High(C) do
  begin
    Tmp := C[I];
    J := I - 1;
    while (J >= 0) and (C[J].Len < Tmp.Len) do
    begin
      C[J + 1] := C[J];
      Dec(J);
    end;
    C[J + 1] := Tmp;
  end;
  if (Rank < 0) or (Rank > High(C)) then Exit;
  if C[Rank].Len < 4096 then Exit;
  Dest.WriteBuffer(Buf[C[Rank].Pos], C[Rank].Len);
  W := C[Rank].W;
  H := C[Rank].H;
  Result := True;
end;

{ ---- writing ---- }

type
  TEntry = record
    Tag: Integer;
    Raw: TBytes;          // the 12-byte IFD entry
  end;

procedure PutU16(var B: TBytes; Ofs, V: Integer; Big: Boolean);
begin
  if Big then
  begin
    B[Ofs] := (V shr 8) and $FF;
    B[Ofs + 1] := V and $FF;
  end
  else
  begin
    B[Ofs] := V and $FF;
    B[Ofs + 1] := (V shr 8) and $FF;
  end;
end;

procedure PutU32(var B: TBytes; Ofs: Integer; V: Int64; Big: Boolean);
var
  I: Integer;
begin
  for I := 0 to 3 do
    if Big then
      B[Ofs + 3 - I] := (V shr (8 * I)) and $FF
    else
      B[Ofs + I] := (V shr (8 * I)) and $FF;
end;

{ appends N zero bytes and returns the old length }
function Grow(var B: TBytes; N: Integer): Integer;
begin
  Result := Length(B);
  SetLength(B, Result + N);
  FillChar(B[Result], N, 0);
end;

function WriteExifOwnerFields(const FileName, Artist, Copyright: string): Boolean;
var
  Src, Tiff, Outp: TBytes;
  Entries: array of TEntry;
  Len, Pos, Mk, L, SegStart, SegEnd, Base, Cnt, I, J, K, Ofs, InsertAt, Pre, Post: Integer;
  T: TTiff;
  Big, Found: Boolean;
  Strm: TFileStream;
  Next: Int64;
  Tmp: TEntry;
  TmpName: string;
  ArtistExists, CopyExists, WantArtist, WantCopy: Boolean;

  procedure AddAscii(ATag: Integer; const S: string);
  var
    N, Data, C: Integer;
    E: TEntry;
  begin
    if S = '' then Exit;
    N := Length(S) + 1;
    E.Tag := ATag;
    E.Raw := nil;
    SetLength(E.Raw, 12);
    FillChar(E.Raw[0], 12, 0);
    PutU16(E.Raw, 0, ATag, Big);
    PutU16(E.Raw, 2, 2, Big);              // type 2 = ASCII
    PutU32(E.Raw, 4, N, Big);
    if N <= 4 then
    begin
      for C := 1 to Length(S) do
        E.Raw[7 + C] := Ord(S[C]);          // stored inline in the value field
    end
    else
    begin
      if Odd(Length(Tiff)) then Grow(Tiff, 1);
      Data := Grow(Tiff, N);
      for C := 1 to Length(S) do
        Tiff[Data + C - 1] := Ord(S[C]);
      PutU32(E.Raw, 8, Data, Big);
    end;
    SetLength(Entries, Length(Entries) + 1);
    Entries[High(Entries)] := E;
  end;

begin
  Result := False;
  Src := nil;
  Tiff := nil;
  Outp := nil;
  Entries := nil;
  T.Buf := nil;
  T.Base := 0;
  T.Big := False;
  Next := 0;
  Big := False;
  ArtistExists := False;
  CopyExists := False;
  if (Artist = '') and (Copyright = '') then
  begin
    Result := True;
    Exit;
  end;

  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    Exit;
  end;
  try
    Len := Strm.Size;
    SetLength(Src, Len);
    if Len > 0 then Strm.ReadBuffer(Src[0], Len);
  finally
    Strm.Free;
  end;
  if (Len < 4) or (Src[0] <> $FF) or (Src[1] <> $D8) then Exit;

  // locate the Exif APP1 segment; remember where to insert one if there is none
  Found := False;
  SegStart := 0;
  SegEnd := 0;
  InsertAt := 2;
  Pos := 2;
  while Pos + 4 <= Len do
  begin
    if Src[Pos] <> $FF then Break;
    Mk := Src[Pos + 1];
    if Mk = $FF then begin Inc(Pos); Continue; end;
    if (Mk = $D9) or (Mk = $DA) then Break;
    L := (Src[Pos + 2] shl 8) or Src[Pos + 3];
    if L < 2 then Break;
    if (Mk = $E1) and (Pos + 10 <= Len) and (Src[Pos + 4] = Ord('E')) and
       (Src[Pos + 5] = Ord('x')) and (Src[Pos + 6] = Ord('i')) and (Src[Pos + 7] = Ord('f')) then
    begin
      Found := True;
      SegStart := Pos;
      SegEnd := Pos + 2 + L;
      Break;
    end;
    if (Mk = $E0) and (Pos = 2) then InsertAt := Pos + 2 + L;   // keep JFIF first
    Pos := Pos + 2 + L;
  end;

  if Found then
  begin
    if SegEnd > Len then Exit;
    Base := SegStart + 10;
    if Base + 8 > SegEnd then Exit;
    T.Buf := Src;
    T.Base := Base;
    T.Big := Src[Base] = $4D;
    if U16(T, Base + 2) <> 42 then Exit;
    Big := T.Big;
    Ofs := Base + Integer(U32(T, Base + 4));
    if (Ofs < Base) or (Ofs + 2 > SegEnd) then Exit;
    Cnt := U16(T, Ofs);
    if Ofs + 2 + Cnt * 12 + 4 > SegEnd then Exit;
    Next := U32(T, Ofs + 2 + Cnt * 12);
    SetLength(Tiff, SegEnd - Base);
    Move(Src[Base], Tiff[0], SegEnd - Base);
    SetLength(Entries, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Entries[I].Tag := U16(T, Ofs + 2 + I * 12);
      Entries[I].Raw := nil;
      SetLength(Entries[I].Raw, 12);
      Move(Src[Ofs + 2 + I * 12], Entries[I].Raw[0], 12);
      if Entries[I].Tag = $013B then ArtistExists := GetStr(T, Ofs + 2 + I * 12) <> '';
      if Entries[I].Tag = $8298 then CopyExists := GetStr(T, Ofs + 2 + I * 12) <> '';
    end;
  end
  else
  begin
    if InsertAt > Len then Exit;
    SetLength(Tiff, 8);
    FillChar(Tiff[0], 8, 0);
    Tiff[0] := $49;
    Tiff[1] := $49;
    PutU16(Tiff, 2, 42, False);
    Big := False;
    Next := 0;
  end;

  // only fill fields that are missing or empty; never overwrite existing values
  WantArtist := (Artist <> '') and (not ArtistExists);
  WantCopy := (Copyright <> '') and (not CopyExists);
  if not (WantArtist or WantCopy) then
  begin
    Result := True;
    Exit;
  end;

  // drop the empty tags we are about to replace
  K := 0;
  for I := 0 to High(Entries) do
    if not (((Entries[I].Tag = $013B) and WantArtist) or
            ((Entries[I].Tag = $8298) and WantCopy)) then
    begin
      Entries[K] := Entries[I];
      Inc(K);
    end;
  SetLength(Entries, K);
  if WantArtist then AddAscii($013B, Artist);
  if WantCopy then AddAscii($8298, Copyright);

  // IFD entries must be sorted by tag
  for I := 1 to High(Entries) do
  begin
    Tmp := Entries[I];
    J := I - 1;
    while (J >= 0) and (Entries[J].Tag > Tmp.Tag) do
    begin
      Entries[J + 1] := Entries[J];
      Dec(J);
    end;
    Entries[J + 1] := Tmp;
  end;

  // write a new IFD0 at the end of the TIFF block; existing value offsets stay valid
  if Odd(Length(Tiff)) then Grow(Tiff, 1);
  Ofs := Grow(Tiff, 2 + Length(Entries) * 12 + 4);
  PutU16(Tiff, Ofs, Length(Entries), Big);
  for I := 0 to High(Entries) do
    Move(Entries[I].Raw[0], Tiff[Ofs + 2 + I * 12], 12);
  PutU32(Tiff, Ofs + 2 + Length(Entries) * 12, Next, Big);
  PutU32(Tiff, 4, Ofs, Big);

  L := 2 + 6 + Length(Tiff);
  if L > 65535 then Exit;          // would not fit in one APP1 segment

  if Found then
  begin
    Pre := SegStart;
    Post := SegEnd;
  end
  else
  begin
    Pre := InsertAt;
    Post := InsertAt;
  end;
  SetLength(Outp, Pre + 10 + Length(Tiff) + (Len - Post));
  Move(Src[0], Outp[0], Pre);
  Outp[Pre] := $FF;
  Outp[Pre + 1] := $E1;
  Outp[Pre + 2] := (L shr 8) and $FF;
  Outp[Pre + 3] := L and $FF;
  Outp[Pre + 4] := Ord('E');
  Outp[Pre + 5] := Ord('x');
  Outp[Pre + 6] := Ord('i');
  Outp[Pre + 7] := Ord('f');
  Outp[Pre + 8] := 0;
  Outp[Pre + 9] := 0;
  Move(Tiff[0], Outp[Pre + 10], Length(Tiff));
  if Len - Post > 0 then
    Move(Src[Post], Outp[Pre + 10 + Length(Tiff)], Len - Post);

  TmpName := FileName + '.tmp';
  try
    Strm := TFileStream.Create(TmpName, fmCreate);
    try
      Strm.WriteBuffer(Outp[0], Length(Outp));
    finally
      Strm.Free;
    end;
    Result := DeleteFileUTF8(FileName) and RenameFileUTF8(TmpName, FileName);
  except
    Result := False;
  end;
  if not Result then DeleteFileUTF8(TmpName);
end;

end.
