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

{ Copies an embedded baseline/progressive JPEG (the preview RAW files carry) to Dest.
  Rank 0 is the largest one, 1 the next largest, and so on. W/H are its pixel size. }
function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Dest: TStream;
  out W, H: Integer): Boolean;

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

function JpegDims(const B: TBytes; Start, Limit: Integer; out W, H: Integer): Boolean;
var
  P, Mk, L: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
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
      if P + 9 > Limit then Exit;
      H := (B[P + 5] shl 8) or B[P + 6];
      W := (B[P + 7] shl 8) or B[P + 8];
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
  Len: Integer;
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
  Result := JpegDims(Buf, 0, Len, W, H);
end;

type
  TJpegCand = record
    Pos, Len, W, H: Integer;
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
  P, E, CW, CH, N: Integer;
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
        if JpegDims(B, P, Len, CW, CH) then
        begin
          SetLength(C, N + 1);
          C[N].Pos := P;
          C[N].Len := E - P;
          C[N].W := CW;
          C[N].H := CH;
          Inc(N);
          if N >= 24 then Exit;
        end;
        P := E;            // skip this JPEG, including any thumbnail nested inside it
        Continue;
      end;
    end;
    Inc(P);
  end;
end;

function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Dest: TStream;
  out W, H: Integer): Boolean;
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
  if (BestLen < 20000) and (FLen > Got) then
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
