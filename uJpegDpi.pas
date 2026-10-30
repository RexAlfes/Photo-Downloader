unit uJpegDpi;

{$mode objfpc}{$H+}

{ Sets the resolution (DPI or dots per centimeter) of a JPEG file without decoding or recompressing
  the picture. The resolution does not change the image data; programs such as Photoshop and
  Photoshop Elements use it to work out the print size.

  A JPEG can hold its resolution in two places, and both are set when they are there:
  - the JFIF header (APP0 "JFIF"#0): a unit byte (1 = dots per inch, 2 = dots per cm) and whole-number
    horizontal and vertical densities;
  - the EXIF data (APP1 "Exif"#0#0), first image directory (IFD0): XResolution and YResolution
    (rationals) and ResolutionUnit (2 = inch, 3 = centimeter). The thumbnail directory is left alone.
  The EXIF values are changed in place (same size). When the file has no JFIF header and its EXIF data
  has no resolution entries, a JFIF header is added right after the start of the file. The file is
  written to a temporary file first and then replaces the original, so a failure never leaves a
  half-written picture behind.

  Used by the built-in plug-in "JPEG resolution". }

interface

uses
  Classes, SysUtils;

{ Sets the resolution of JpegFile to Value dots per inch, or per centimeter when PerCm is True
  (Value > 0; EXIF keeps two decimals, JFIF a whole number). Returns 1 = changed, 0 = the file had
  this resolution already, -1 = failed (Err tells why). }
function SetJpegResolution(const JpegFile: string; Value: Double; PerCm: Boolean; out Err: string): Integer;
{ Reads the resolution of a JPEG: the EXIF values when present, else the JFIF values. False when the
  file has neither. }
function GetJpegResolution(const JpegFile: string; out Value: Double; out PerCm: Boolean): Boolean;
{ Reads the plug-in choices (key=value lines Value=<number with a dot>, Unit=dpi or cm); 300 dpi when
  nothing usable is stored. }
procedure ParseResolutionOpts(const Lines: string; out Value: Double; out PerCm: Boolean);
{ The plug-in choices as key=value lines (the value with a dot as decimal separator). }
function ResolutionOptsText(Value: Double; PerCm: Boolean): string;

implementation

uses
  Math, LazFileUtils;

const
  TagXRes = $011A;  // EXIF XResolution (RATIONAL)
  TagYRes = $011B;  // EXIF YResolution (RATIONAL)
  TagResUnit = $0128;  // EXIF ResolutionUnit (SHORT: 2 = inch, 3 = centimeter)

type
  { Where the resolution fields of one file are (1-based positions, 0 = not there) }
  TResPlaces = record
    Jfif: Integer;  // position of the JFIF unit byte (densities follow)
    Tiff: Integer;  // position of the EXIF TIFF header
    Intel: Boolean;  // EXIF byte order: True = little-endian ("II")
    XRes, YRes: Integer;  // positions of the XResolution / YResolution rationals
    ResUnit: Integer;  // position of the ResolutionUnit value
    Sos: Integer;  // position of the start-of-scan segment (0 = not a usable JPEG)
  end;

{ Reads a whole file into a byte string. }
function ReadAll(const FileName: string): RawByteString;
var
  F: TFileStream;  // F: the open file
begin
  Result := '';  // nothing yet
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);  // open it read-only
  try
    SetLength(Result, F.Size);  // room for the bytes
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);  // read them
  finally
    F.Free;  // close it
  end;
end;

{ Big-endian 16-bit number at the 1-based position P. }
function BE16(const S: RawByteString; P: Integer): Integer;
begin
  Result := (Ord(S[P]) shl 8) or Ord(S[P + 1]);  // two bytes
end;

{ 16-bit number at P in the EXIF byte order. }
function Rd16(const S: RawByteString; P: Integer; Intel: Boolean): Integer;
begin
  if Intel then Result := Ord(S[P]) or (Ord(S[P + 1]) shl 8)  // little-endian
  else Result := (Ord(S[P]) shl 8) or Ord(S[P + 1]);  // big-endian
end;

{ 32-bit number at P in the EXIF byte order. }
function Rd32(const S: RawByteString; P: Integer; Intel: Boolean): Int64;
begin
  if Intel then
    Result := Int64(Ord(S[P])) or (Int64(Ord(S[P + 1])) shl 8) or (Int64(Ord(S[P + 2])) shl 16) or (Int64(Ord(S[P + 3])) shl 24)
  else
    Result := (Int64(Ord(S[P])) shl 24) or (Int64(Ord(S[P + 1])) shl 16) or (Int64(Ord(S[P + 2])) shl 8) or Int64(Ord(S[P + 3]));
end;

{ Writes a 16-bit number at P in the EXIF byte order. }
procedure Wr16(var S: RawByteString; P, V: Integer; Intel: Boolean);
begin
  if Intel then begin S[P] := Chr(V and $FF); S[P + 1] := Chr((V shr 8) and $FF); end
  else begin S[P] := Chr((V shr 8) and $FF); S[P + 1] := Chr(V and $FF); end;
end;

{ Writes a 32-bit number at P in the EXIF byte order. }
procedure Wr32(var S: RawByteString; P: Integer; V: Int64; Intel: Boolean);
var
  I: Integer;  // I: byte index
begin
  for I := 0 to 3 do
    if Intel then S[P + I] := Chr((V shr (8 * I)) and $FF)  // lowest byte first
    else S[P + 3 - I] := Chr((V shr (8 * I)) and $FF);  // highest byte first
end;

{ Finds the resolution fields in IFD0 of the EXIF segment whose TIFF header starts at T; SegEnd is the
  last position of the segment (entries pointing outside it are ignored). }
procedure ScanExif(const D: RawByteString; T, SegEnd: Integer; var R: TResPlaces);
var
  Ifd, N, I, E, Tag, Typ: Integer;  // Ifd: position of IFD0; N: entries; E: one entry; Tag/Typ: its tag and type
  Off: Int64;  // Off: offset of a rational
begin
  if T + 8 > SegEnd then Exit;  // too short for a TIFF header
  if Copy(D, T, 2) = 'II' then R.Intel := True
  else if Copy(D, T, 2) = 'MM' then R.Intel := False
  else Exit;  // not a TIFF header
  R.Tiff := T;  // found
  Off := Rd32(D, T + 4, R.Intel);  // offset of IFD0
  if (Off < 8) or (T + Off + 2 > SegEnd) then Exit;  // outside the segment
  Ifd := T + Integer(Off);  // position of IFD0
  N := Rd16(D, Ifd, R.Intel);  // number of entries
  for I := 0 to N - 1 do
  begin
    E := Ifd + 2 + 12 * I;  // the entry
    if E + 12 > SegEnd + 1 then Break;  // outside the segment
    Tag := Rd16(D, E, R.Intel);  // its tag
    Typ := Rd16(D, E + 2, R.Intel);  // its type
    if ((Tag = TagXRes) or (Tag = TagYRes)) and (Typ = 5) then  // a rational: 8 bytes at an offset
    begin
      Off := Rd32(D, E + 8, R.Intel);  // where it is
      if (Off >= 8) and (T + Off + 8 <= SegEnd + 1) then
        if Tag = TagXRes then R.XRes := T + Integer(Off) else R.YRes := T + Integer(Off);
    end
    else if (Tag = TagResUnit) and (Typ = 3) then  // a short: stored in the entry itself
      R.ResUnit := E + 8;
  end;
end;

{ Walks the header segments of a JPEG and notes where the resolution fields are. }
function ScanJpeg(const D: RawByteString): TResPlaces;
var
  P, M, N: Integer;  // P: position of the FF marker; M: marker code; N: segment size with its marker
begin
  Result := Default(TResPlaces);  // nothing found yet
  if (Length(D) < 4) or (D[1] <> #$FF) or (D[2] <> #$D8) then Exit;  // not a JPEG
  P := 3;  // first segment
  while P + 3 <= Length(D) do
  begin
    if D[P] <> #$FF then Exit;  // lost the segment chain
    M := Ord(D[P + 1]);  // marker
    if M = $FF then begin Inc(P); Continue; end;  // fill byte
    if M = $DA then begin Result.Sos := P; Exit; end;  // start of scan: the picture data follows
    N := 2 + BE16(D, P + 2);  // segment size
    if P + N - 1 > Length(D) then Exit;  // cut off
    if (M = $E0) and (Result.Jfif = 0) and (N >= 18) and (Copy(D, P + 4, 5) = 'JFIF'#0) then
      Result.Jfif := P + 11  // unit byte after "JFIF"#0 and the version
    else if (M = $E1) and (Result.Tiff = 0) and (Copy(D, P + 4, 6) = 'Exif'#0#0) then
      ScanExif(D, P + 10, P + N - 1, Result);  // the EXIF data
    P := P + N;  // next segment
  end;
end;

{ Replaces JpegFile with the bytes D (temporary file first, the old file put back on failure). }
procedure WriteReplace(const JpegFile: string; const D: RawByteString);
var
  Tmp: string;  // Tmp: the temporary file
  F: TFileStream;  // F: the new file
begin
  Tmp := JpegFile + '.dpi.tmp';  // temporary name
  try
    F := TFileStream.Create(Tmp, fmCreate);  // the new file
    try
      F.WriteBuffer(D[1], Length(D));  // write it
    finally
      F.Free;  // close it
    end;
    if FileExistsUTF8(JpegFile + '.dpi.old') then DeleteFileUTF8(JpegFile + '.dpi.old');  // a left-over
    if not RenameFileUTF8(JpegFile, JpegFile + '.dpi.old') then raise Exception.Create('cannot replace the file');
    if not RenameFileUTF8(Tmp, JpegFile) then  // put the new one in place
    begin
      RenameFileUTF8(JpegFile + '.dpi.old', JpegFile);  // put the old one back
      raise Exception.Create('cannot rename ' + Tmp);
    end;
    DeleteFileUTF8(JpegFile + '.dpi.old');  // the old file is no longer needed
  except
    if FileExistsUTF8(Tmp) then DeleteFileUTF8(Tmp);  // no left-over
    raise;  // the caller reports it
  end;
end;

function SetJpegResolution(const JpegFile: string; Value: Double; PerCm: Boolean; out Err: string): Integer;
var
  D, Old: RawByteString;  // D: the file (changed); Old: as it was
  R: TResPlaces;  // R: where the fields are
  Num, Den: Int64;  // Num/Den: the EXIF rational
  Dens, U: Integer;  // Dens: JFIF density; U: unit code
  Seg: RawByteString;  // Seg: a new JFIF header
begin
  Result := -1;  // assume failure
  Err := '';  // no error yet
  if not (Value > 0) or (Value > 65535) then begin Err := 'the resolution must be between 1 and 65535'; Exit; end;
  try
    D := ReadAll(JpegFile);  // the picture
  except
    on E: Exception do begin Err := 'cannot read: ' + E.Message; Exit; end;
  end;
  Old := D;  // to see whether anything changed
  UniqueString(D);  // D is changed below
  R := ScanJpeg(D);  // where the fields are
  if R.Sos = 0 then begin Err := 'not a JPEG file, or its header is damaged'; Exit; end;
  // EXIF: two decimals as a rational (300 -> 300/1, 118.11 -> 11811/100)
  Num := Round(Value * 100);  // hundredths
  Den := 100;
  while (Den > 1) and (Num mod 10 = 0) do begin Num := Num div 10; Den := Den div 10; end;  // shorten
  if PerCm then U := 3 else U := 2;  // EXIF unit
  if R.XRes > 0 then begin Wr32(D, R.XRes, Num, R.Intel); Wr32(D, R.XRes + 4, Den, R.Intel); end;
  if R.YRes > 0 then begin Wr32(D, R.YRes, Num, R.Intel); Wr32(D, R.YRes + 4, Den, R.Intel); end;
  if R.ResUnit > 0 then Wr16(D, R.ResUnit, U, R.Intel);
  // JFIF: whole numbers
  Dens := Max(1, Min(65535, Round(Value)));  // density
  if PerCm then U := 2 else U := 1;  // JFIF unit
  if R.Jfif > 0 then
  begin
    D[R.Jfif] := Chr(U);  // unit
    D[R.Jfif + 1] := Chr(Dens shr 8); D[R.Jfif + 2] := Chr(Dens and $FF);  // horizontal density
    D[R.Jfif + 3] := Chr(Dens shr 8); D[R.Jfif + 4] := Chr(Dens and $FF);  // vertical density
  end
  else if (R.XRes = 0) and (R.YRes = 0) then  // no place for the resolution: add a JFIF header
  begin
    Seg := #$FF#$E0#$00#$10'JFIF'#0#1#2 + Chr(U) + Chr(Dens shr 8) + Chr(Dens and $FF) +
      Chr(Dens shr 8) + Chr(Dens and $FF) + #0#0;  // version 1.02, no thumbnail
    D := Copy(D, 1, 2) + Seg + Copy(D, 3, MaxInt);  // right after the start of the file
  end;
  if D = Old then Exit(0);  // it had this resolution already
  try
    WriteReplace(JpegFile, D);  // write it
  except
    on E: Exception do begin Err := E.Message; Exit; end;
  end;
  Result := 1;  // changed
end;

{ Number format with a dot as decimal separator, whatever the system uses. }
function DotFormat: TFormatSettings;
begin
  Result := DefaultFormatSettings;  // start from the defaults
  Result.DecimalSeparator := '.';  // always a dot in the settings file
  Result.ThousandSeparator := #0;  // no thousands separator
end;

procedure ParseResolutionOpts(const Lines: string; out Value: Double; out PerCm: Boolean);
var
  L: TStringList;  // L: the lines
begin
  L := TStringList.Create;  // create the list
  try
    L.Text := Lines;  // split into lines
    Value := StrToFloatDef(Trim(L.Values['Value']), 300, DotFormat);  // the value (300 when missing)
    PerCm := SameText(Trim(L.Values['Unit']), 'cm');  // the unit (dpi when missing)
  finally
    L.Free;  // free the list
  end;
  if (Value < 1) or (Value > 65535) then Value := 300;  // not usable: the default
end;

function ResolutionOptsText(Value: Double; PerCm: Boolean): string;
begin
  Result := 'Value=' + FormatFloat('0.##', Value, DotFormat) + LineEnding;  // the value
  if PerCm then Result := Result + 'Unit=cm' + LineEnding  // dots per centimeter
  else Result := Result + 'Unit=dpi' + LineEnding;  // dots per inch
end;

function GetJpegResolution(const JpegFile: string; out Value: Double; out PerCm: Boolean): Boolean;
var
  D: RawByteString;  // D: the file
  R: TResPlaces;  // R: where the fields are
  Den: Int64;  // Den: denominator of the rational
begin
  Result := False;  // nothing found yet
  Value := 0;
  PerCm := False;
  try
    D := ReadAll(JpegFile);  // the picture
  except
    Exit;  // not readable
  end;
  R := ScanJpeg(D);  // where the fields are
  if R.XRes > 0 then  // EXIF first
  begin
    Den := Rd32(D, R.XRes + 4, R.Intel);  // denominator
    if Den > 0 then Value := Rd32(D, R.XRes, R.Intel) / Den;  // the value
    PerCm := (R.ResUnit > 0) and (Rd16(D, R.ResUnit, R.Intel) = 3);  // centimeters
    Exit(True);
  end;
  if R.Jfif > 0 then  // else JFIF
  begin
    Value := BE16(D, R.Jfif + 1);  // horizontal density
    PerCm := Ord(D[R.Jfif]) = 2;  // dots per cm
    Result := Ord(D[R.Jfif]) <> 0;  // 0 = only an aspect ratio, no resolution
  end;
end;

end.
