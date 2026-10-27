unit uExif;

{$mode objfpc}{$H+}

{ Minimal EXIF reader. Works on JPEG (APP1 segment) and on TIFF-based raw
  files (NEF, CR2, DNG, ARW ...) where the TIFF header is at offset 0. }

interface

uses
  Classes, SysUtils, LazFileUtils;

type
  TExifInfo = record  // EXIF data of one picture
    Valid: Boolean;  // True when the data was read
    Make, Model, Artist, Owner, Serial: string;  // Make: camera maker; Model: camera model; Artist: artist; Owner: owner; Serial: camera serial number
    DateTaken: TDateTime;  // capture date and time
    HasDate: Boolean;  // True when a capture date was found
    ISO: Integer;  // ISO speed
    Orientation: Integer;  // orientation 1..8 (0 = unknown)
  end;

function ReadExifFromFile(const FileName: string; out Info: TExifInfo): Boolean;  // Reads the EXIF data of a file; False when there is none.
{ Adds the EXIF Artist and/or Copyright tags to a JPEG file in place, but only
  for a field that is missing or empty in the file; existing values are never
  overwritten. Returns True if the file is now in the wanted state. }
function WriteExifOwnerFields(const FileName, Artist, Copyright: string): Boolean;  // Adds missing Artist and Copyright tags to a JPEG file.
{ Largest picture size stored in a HEIC/HEIF file (its 'ispe' property), before any rotation. }
function ReadHeifStoredSize(const FileName: string; out W, H: Integer): Boolean;  // Reads the stored size of a HEIC file.

{ Copies an embedded baseline/progressive JPEG (the preview RAW files carry) to Dest.
  Rank 0 is the largest one, 1 the next largest, and so on. W/H are its pixel size. }
function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Deep: Boolean;  // Copies an embedded JPEG preview of a raw file to Dest.
  Dest: TStream; out W, H: Integer): Boolean;

{ Deep = False limits the search to the first 4 MB (used for TIFF and DNG, whose
  files can be huge); Deep = True may scan up to 96 MB (RAW files). }

type
  TInt64Array = array of Int64;  // list of 64-bit values
  { An uncompressed, chunky 8 or 16 bit gray or RGB image inside a TIFF/DNG file }
  TTiffRgb = record
    Big: Boolean;  // True for big-endian files
    W, H, Bits, Spp, Photo, RowsPerStrip: Integer;  // W, H: size; Bits: bits per sample; Spp: samples per pixel; Photo: photometric type; RowsPerStrip: rows per strip
    Offsets: TInt64Array;  // file offsets of the strips
  end;

{ Finds the largest uncompressed gray/RGB image in a TIFF or DNG file (IFD chain and SubIFDs). }
function FindTiffRgb(const FileName: string; out R: TTiffRgb): Boolean;  // Finds the largest plain picture of a TIFF or DNG file.
{ Reads one row of that image into Buf. }
function ReadTiffRgbRow(Strm: TStream; const R: TTiffRgb; Row: Integer; var Buf: TBytes): Boolean;  // Reads one row of that picture into Buf.

{ Reads the movie header (mvhd box) of an MP4, MOV or LRV file: the creation time as stored (HasDate is
  False when it is missing or implausible) and the length of the clip in seconds. }
function ReadMovieHeader(const FileName: string; out Created: TDateTime; out HasDate: Boolean;
  out Duration: Double): Boolean;
{ Copies the cover picture stored inside a movie (moov/udta/meta/ilst/covr) to Dest; IsPng tells the
  picture format (JPEG otherwise). False when the movie has no cover. }
function ExtractMovieCover(const FileName: string; Dest: TStream; out IsPng: Boolean): Boolean;

{ Pixel size of a JPEG file, read from its header only. }
function ReadJpegDims(const FileName: string; out W, H: Integer): Boolean;  // Reads the pixel size of a JPEG file from its header.

implementation

{ A TIFF structure held in memory. }
type
  TTiff = record
    Buf: TBytes;  // the bytes
    Base: Integer;  // offset of the TIFF header in the buffer
    Big: Boolean;  // True for big-endian data
  end;

{ Reads a 16-bit value at Ofs, in the byte order of the data. }
function U16(const T: TTiff; Ofs: Integer): Integer;
begin
  Result := 0;  // zero when outside the data
  if (Ofs < 0) or (Ofs + 2 > Length(T.Buf)) then Exit;  // outside the data
  if T.Big then
    Result := (T.Buf[Ofs] shl 8) or T.Buf[Ofs + 1]  // big-endian value
  else
    Result := T.Buf[Ofs] or (T.Buf[Ofs + 1] shl 8);  // little-endian value
end;

{ Reads a 32-bit value at Ofs, in the byte order of the data. }
function U32(const T: TTiff; Ofs: Integer): Int64;
var
  B0, B1, B2, B3: Int64;  // B0..B3: the four bytes
begin
  Result := 0;  // zero when outside the data
  if (Ofs < 0) or (Ofs + 4 > Length(T.Buf)) then Exit;  // outside the data
  B0 := T.Buf[Ofs]; B1 := T.Buf[Ofs + 1]; B2 := T.Buf[Ofs + 2]; B3 := T.Buf[Ofs + 3];  // read the four bytes
  if T.Big then
    Result := (B0 shl 24) or (B1 shl 16) or (B2 shl 8) or B3  // big-endian value
  else
    Result := B0 or (B1 shl 8) or (B2 shl 16) or (B3 shl 24);  // little-endian value
end;

{ Reads the text value of the directory entry at E (at most 128 characters). }
function GetStr(const T: TTiff; E: Integer): string;
var
  Cnt, Off: Int64;  // Cnt: number of characters; Off: offset of the text
  P, I: Integer;  // P: position of the text; I: loop counter
  B: Byte;  // B: current byte
begin
  Result := '';  // empty by default
  Cnt := U32(T, E + 4);  // number of characters
  if Cnt <= 0 then Exit;  // nothing to read
  if Cnt <= 4 then  // short texts are stored in the entry itself
    P := E + 8  // position inside the entry
  else
  begin
    Off := U32(T, E + 8);  // offset of the text
    if Off + T.Base >= Length(T.Buf) then Exit;  // offset outside the data
    P := T.Base + Integer(Off);  // position of the text
  end;
  if (P < 0) or (P >= Length(T.Buf)) then Exit;  // position outside the data
  if Cnt > 128 then Cnt := 128;  // limit the length
  for I := 0 to Integer(Cnt) - 1 do  // every character
  begin
    if P + I >= Length(T.Buf) then Break;  // stop at the end of the data
    B := T.Buf[P + I];  // current byte
    if B = 0 then Break;  // stop at a zero byte
    Result := Result + Chr(B);  // add the character
  end;
  Result := Trim(Result);  // remove surrounding blanks
end;

{ Converts an EXIF date text (yyyy:mm:dd hh:nn:ss) to a date; False when invalid. }
function ParseExifDate(const S: string; out DT: TDateTime): Boolean;
var
  Y, M, D, H, N, Sec: Integer;  // Y, M, D: year, month, day; H, N, Sec: hour, minute, second
  Tm: TDateTime;  // Tm: time part
begin
  Result := False;  // assume failure
  DT := 0;  // no date yet
  if Length(S) < 19 then Exit;  // too short
  Y := StrToIntDef(Copy(S, 1, 4), 0);  // year
  M := StrToIntDef(Copy(S, 6, 2), 0);  // month
  D := StrToIntDef(Copy(S, 9, 2), 0);  // day
  H := StrToIntDef(Copy(S, 12, 2), 0);  // hour
  N := StrToIntDef(Copy(S, 15, 2), 0);  // minute
  Sec := StrToIntDef(Copy(S, 18, 2), 0);  // second
  if Y < 1900 then Exit;  // implausible year
  if not TryEncodeDate(Y, M, D, DT) then Exit;  // build the date
  if not TryEncodeTime(H, N, Sec, 0, Tm) then Tm := 0;  // build the time, midnight when invalid
  DT := DT + Tm;  // add the time to the date
  Result := True;  // success
end;

{ Reads one EXIF directory and stores the tags that are of interest. }
procedure ReadIFD(const T: TTiff; IfdRel: Int64; Depth: Integer; var Info: TExifInfo);
var
  P, N, I, E, Tag: Integer;  // P: directory position; N: entry count; I: loop counter; E: entry position; Tag: tag number
  DT: TDateTime;  // DT: date read
  S: string;  // S: text read
begin
  if (Depth > 3) or (IfdRel <= 0) or (IfdRel > Length(T.Buf)) then Exit;  // limit the nesting depth and check the offset
  P := T.Base + Integer(IfdRel);  // position of the directory
  if P + 2 > Length(T.Buf) then Exit;  // directory outside the data
  N := U16(T, P);  // number of entries
  if N > 300 then Exit;  // reject an implausible count
  for I := 0 to N - 1 do  // every entry
  begin
    E := P + 2 + I * 12;  // position of the entry
    if E + 12 > Length(T.Buf) then Break;  // entry outside the data
    Tag := U16(T, E);  // tag number
    case Tag of
      $010F: Info.Make := GetStr(T, E);  // camera maker
      $0110: Info.Model := GetStr(T, E);  // camera model
      $013B: Info.Artist := GetStr(T, E);  // artist
      $0112: Info.Orientation := U16(T, E + 8);  // orientation
      $0132:  // modification date, used when there is no capture date
        if not Info.HasDate then  // only when no date is known yet
        begin
          S := GetStr(T, E);  // date text
          if ParseExifDate(S, DT) then  // convert it
          begin
            Info.DateTaken := DT;  // store the date
            Info.HasDate := True;  // a date is known now
          end;
        end;
      $9003:
        begin
          S := GetStr(T, E);  // original capture date text
          if ParseExifDate(S, DT) then  // convert it
          begin
            Info.DateTaken := DT;  // store the date
            Info.HasDate := True;  // a date is known now
          end;
        end;
      $8827: Info.ISO := U16(T, E + 8);  // ISO speed
      $A430: Info.Owner := GetStr(T, E);  // owner name
      $A431: Info.Serial := GetStr(T, E);  // camera serial number
      $8769: ReadIFD(T, U32(T, E + 8), Depth + 1, Info);  // EXIF sub directory
    end;
  end;
end;

{ ---- stream helpers ---- }

{ Reads Count bytes at Ofs from a stream; False when outside the stream. }
function StreamRead(Strm: TStream; Ofs: Int64; var Buf; Count: Integer): Boolean;
begin
  Result := False;  // assume failure
  if (Ofs < 0) or (Count <= 0) or (Ofs + Count > Strm.Size) then Exit;  // check the range
  Strm.Position := Ofs;  // go to the position
  Result := Strm.Read(Buf, Count) = Count;  // success when all bytes were read
end;

{ Reads a little-endian 16-bit value from a stream. }
function StreamLE16(Strm: TStream; Ofs: Int64): Integer;
var
  B: array[0..1] of Byte;  // B: the two bytes
begin
  Result := 0;  // zero when not readable
  B[0] := 0;  // clear the bytes
  B[1] := 0;  // clear the bytes
  if StreamRead(Strm, Ofs, B, 2) then Result := B[0] or (B[1] shl 8);  // combine the bytes
end;

{ Reads a little-endian 32-bit value from a stream. }
function StreamLE32(Strm: TStream; Ofs: Int64): Int64;
var
  B: array[0..3] of Byte;  // B: the four bytes
begin
  Result := 0;  // zero when not readable
  B[0] := 0;  // clear the bytes
  B[1] := 0;  // clear the bytes
  B[2] := 0;  // clear the bytes
  B[3] := 0;  // clear the bytes
  if StreamRead(Strm, Ofs, B, 4) then
    Result := Int64(B[0]) or (Int64(B[1]) shl 8) or (Int64(B[2]) shl 16) or (Int64(B[3]) shl 24);  // combine the bytes
end;

{ Reads a 16-bit value from a stream in the given byte order. }
function RdU16(Strm: TStream; Big: Boolean; Ofs: Int64): Integer;
var
  B: array[0..1] of Byte;  // B: the two bytes
begin
  Result := 0;  // zero when not readable
  B[0] := 0;  // clear the bytes
  B[1] := 0;  // clear the bytes
  if StreamRead(Strm, Ofs, B, 2) then
    if Big then Result := (B[0] shl 8) or B[1] else Result := B[0] or (B[1] shl 8);  // combine the bytes
end;

{ Reads a 32-bit value from a stream in the given byte order. }
function RdU32(Strm: TStream; Big: Boolean; Ofs: Int64): Int64;
var
  B: array[0..3] of Byte;  // B: the four bytes
begin
  Result := 0;  // zero when not readable
  B[0] := 0;  // clear the bytes
  B[1] := 0;  // clear the bytes
  B[2] := 0;  // clear the bytes
  B[3] := 0;  // clear the bytes
  if StreamRead(Strm, Ofs, B, 4) then
  begin
    if Big then
      Result := (Int64(B[0]) shl 24) or (Int64(B[1]) shl 16) or (Int64(B[2]) shl 8) or Int64(B[3])  // big-endian value
    else
      Result := Int64(B[0]) or (Int64(B[1]) shl 8) or (Int64(B[2]) shl 16) or (Int64(B[3]) shl 24);  // little-endian value
  end;
end;

{ ---- Canon CRW (CIFF container, not TIFF) ---- }

{ Walks a Canon CRW directory and reads camera make, model and capture time. }
procedure CiffWalk(Strm: TStream; Start, Stop: Int64; Depth: Integer; var Info: TExifInfo);
var
  Tbl, P, RecLen, RecOff, DataPos, T: Int64;  // Tbl: record table position; P: record position; RecLen: record length; RecOff: record offset; DataPos: data position; T: time in seconds
  N, I, K, Cnt, Code, Typ, TagId: Integer;  // N: record count; I, K: loop counters; Cnt: byte count; Code: record code; Typ: record type; TagId: tag number
  Buf: array[0..95] of Byte;  // Buf: record data
  S1, S2: string;  // S1, S2: the two texts
  InlineRec: Boolean;  // True when the data is stored in the record itself
begin
  if (Depth > 6) or (Stop - Start < 10) then Exit;  // limit the nesting depth and check the size
  Tbl := Start + StreamLE32(Strm, Stop - 4);       // record table offset sits in the last 4 bytes
  if (Tbl < Start) or (Tbl + 2 > Stop) then Exit;  // table outside the directory
  N := StreamLE16(Strm, Tbl);  // number of records
  if (N > 300) or (Tbl + 2 + N * 10 > Stop) then Exit;  // reject an implausible count
  for I := 0 to N - 1 do  // every record
  begin
    P := Tbl + 2 + I * 10;  // position of the record
    Code := StreamLE16(Strm, P);  // record code
    RecLen := StreamLE32(Strm, P + 2);  // record length
    RecOff := StreamLE32(Strm, P + 6);  // record offset
    Typ := Code and $3800;  // record type
    TagId := Code and $3FFF;  // tag number
    InlineRec := (Code and $C000) = $4000;  // data stored in the record
    if (not InlineRec) and ((Typ = $2800) or (Typ = $3000)) then
      CiffWalk(Strm, Start + RecOff, Start + RecOff + RecLen, Depth + 1, Info)   // sub directory
    else
    begin
      if InlineRec then
      begin
        DataPos := P + 2;  // data follows the code
        RecLen := 8;  // inline data has 8 bytes
      end
      else
        DataPos := Start + RecOff;  // position of the data
      if TagId = $080A then  // camera make and model
      begin
        // camera make and model: two NUL terminated strings
        Cnt := Integer(RecLen);  // number of bytes
        if Cnt > SizeOf(Buf) then Cnt := SizeOf(Buf);  // limit to the buffer
        for K := 0 to High(Buf) do Buf[K] := 0;  // clear the buffer
        if StreamRead(Strm, DataPos, Buf, Cnt) then  // read the data
        begin
          S1 := '';  // no maker yet
          K := 0;  // start at the first byte
          while (K < Cnt) and (Buf[K] <> 0) do  // read the first text
          begin
            S1 := S1 + Chr(Buf[K]);  // add the character
            Inc(K);  // next byte
          end;
          Inc(K);  // skip the zero byte
          S2 := '';  // no model yet
          while (K < Cnt) and (Buf[K] <> 0) do  // read the second text
          begin
            S2 := S2 + Chr(Buf[K]);  // add the character
            Inc(K);  // next byte
          end;
          Info.Make := Trim(S1);  // camera maker
          Info.Model := Trim(S2);  // camera model
        end;
      end
      else if (TagId = $180E) and (RecLen >= 4) then  // capture time
      begin
        // capture time stored as seconds since 1970
        T := StreamLE32(Strm, DataPos);  // seconds since 1970
        if T > 0 then  // valid time
        begin
          Info.DateTaken := EncodeDate(1970, 1, 1) + T / 86400;  // convert to a date
          Info.HasDate := True;  // a date is known now
        end;
      end;
    end;
  end;
end;

{ True when the bytes start with a Canon CRW header. }
function IsCiff(const B: TBytes): Boolean;
begin
  Result := (Length(B) >= 14) and (B[6] = Ord('H')) and (B[7] = Ord('E')) and  // signature check, first part
    (B[8] = Ord('A')) and (B[9] = Ord('P')) and (B[10] = Ord('C')) and
    (B[11] = Ord('C')) and (B[12] = Ord('D')) and (B[13] = Ord('R'));
end;

{ Reads the EXIF data of a Canon CRW file. }
function ReadCiffFromFile(const FileName: string; var Info: TExifInfo): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  HL: Int64;  // HL: header length
begin
  Result := False;  // assume failure
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try  // header length is the start of the root heap
    HL := StreamLE32(Strm, 2);                       // header length = start of the root heap
    if (HL < 14) or (HL >= Strm.Size) then Exit;  // implausible header length
    CiffWalk(Strm, HL, Strm.Size, 0, Info);  // walk the root heap
    Result := (Info.Model <> '') or Info.HasDate;  // success when a model or a date was found
  finally
    Strm.Free;  // close the file
  end;
end;

{ ---- uncompressed TIFF / DNG image data (used for thumbnails) ---- }

type
  { State of the search for a plain picture in a TIFF file. }
  TTiffWalk = record
    Strm: TStream;  // the file
    Big: Boolean;  // True for big-endian files
    Size: Int64;  // file size
    Seen: array of Int64;  // directory offsets already visited
    Best: TTiffRgb;  // largest plain picture found so far
    Found: Boolean;  // True when a picture was found
  end;

{ reads the integer values of one IFD entry (BYTE, SHORT, LONG, IFD types) }
function ReadTagInts(Strm: TStream; Big: Boolean; E: Int64; MaxN: Integer;
  out V: TInt64Array): Boolean;
var
  Typ, Sz, I: Integer;  // Typ: data type; Sz: bytes per value; I: loop counter
  Cnt, Total, Src: Int64;  // Cnt: number of values; Total: bytes of values; Src: position of the values
  Raw: TBytes;  // Raw: raw bytes
begin
  Result := False;  // assume failure
  V := nil;  // no values yet
  Raw := nil;  // release any old array
  Typ := RdU16(Strm, Big, E + 2);  // data type
  Cnt := RdU32(Strm, Big, E + 4);  // number of values
  case Typ of
    1, 6, 7: Sz := 1;  // byte types
    3, 8: Sz := 2;  // 16-bit types
    4, 9, 13: Sz := 4;  // 32-bit types
  else
    Exit;
  end;
  if (Cnt < 1) or (Cnt > MaxN) then Exit;  // reject an empty or too long list
  Total := Cnt * Sz;  // number of bytes
  if Total <= 4 then Src := E + 8 else Src := RdU32(Strm, Big, E + 8);  // short lists are stored in the entry itself
  SetLength(Raw, Integer(Total));  // reserve the raw bytes
  if not StreamRead(Strm, Src, Raw[0], Integer(Total)) then Exit;  // read the raw bytes
  SetLength(V, Integer(Cnt));  // reserve the values
  for I := 0 to Integer(Cnt) - 1 do  // every value
    case Sz of
      1: V[I] := Raw[I];  // byte value
      2: if Big then V[I] := (Raw[I * 2] shl 8) or Raw[I * 2 + 1]  // 16-bit value
         else V[I] := Raw[I * 2] or (Raw[I * 2 + 1] shl 8);  // 16-bit value, little-endian
    else
      if Big then
        V[I] := (Int64(Raw[I * 4]) shl 24) or (Int64(Raw[I * 4 + 1]) shl 16) or  // 32-bit value, big-endian
                (Int64(Raw[I * 4 + 2]) shl 8) or Int64(Raw[I * 4 + 3])
      else
        V[I] := Int64(Raw[I * 4]) or (Int64(Raw[I * 4 + 1]) shl 8) or  // 32-bit value, little-endian
                (Int64(Raw[I * 4 + 2]) shl 16) or (Int64(Raw[I * 4 + 3]) shl 24);
    end;
  Result := True;
end;

{ Walks one TIFF directory and its sub directories and remembers the largest plain picture. }
procedure TiffWalkIfd(var Ctx: TTiffWalk; Off: Int64; Depth: Integer);
var
  N, I, K, Tag: Integer;  // N: entry count; I, K: loop counters; Tag: tag number
  E, W, H, Comp, Photo, Spp, Rps, Planar, Next: Int64;  // E: entry position; W, H: picture size; Comp: compression; Photo: photometric type; Spp: samples per pixel; Rps: rows per strip; Planar: planar configuration; Next: offset of the next directory
  V, Offs, Subs, BitsA: TInt64Array;  // V: tag values; Offs: strip offsets; Subs: sub directory offsets; BitsA: bits per sample
  HavePredictor, BitsOk: Boolean;  // HavePredictor: a predictor is used; BitsOk: bits per sample are usable
begin
  if (Off < 8) or (Off + 2 > Ctx.Size) or (Depth > 6) or (Length(Ctx.Seen) >= 24) then Exit;  // limit the depth and check the offset
  for I := 0 to High(Ctx.Seen) do  // check the visited directories
    if Ctx.Seen[I] = Off then Exit;  // already visited
  SetLength(Ctx.Seen, Length(Ctx.Seen) + 1);  // make room in the list
  Ctx.Seen[High(Ctx.Seen)] := Off;  // remember this directory
  N := RdU16(Ctx.Strm, Ctx.Big, Off);  // number of entries
  if (N < 1) or (N > 400) then Exit;  // reject an implausible count

  W := 0; H := 0; Comp := 1; Photo := -1; Spp := 1; Rps := 0; Planar := 1;  // default values
  HavePredictor := False;  // no predictor yet
  V := nil; Offs := nil; Subs := nil; BitsA := nil;  // release any old arrays
  for I := 0 to N - 1 do  // every entry
  begin
    E := Off + 2 + I * 12;  // position of the entry
    Tag := RdU16(Ctx.Strm, Ctx.Big, E);  // tag number
    case Tag of
      $0100: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then W := V[0];  // image width
      $0101: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then H := V[0];  // image height
      $0102: ReadTagInts(Ctx.Strm, Ctx.Big, E, 4, BitsA);  // bits per sample
      $0103: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Comp := V[0];  // compression
      $0106: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Photo := V[0];  // photometric type
      $0111: ReadTagInts(Ctx.Strm, Ctx.Big, E, 100000, Offs);  // strip offsets
      $0115: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Spp := V[0];  // samples per pixel
      $0116: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Rps := V[0];  // rows per strip
      $011C: if ReadTagInts(Ctx.Strm, Ctx.Big, E, 1, V) then Planar := V[0];  // planar configuration
      $013D: HavePredictor := True;  // predictor present
      $014A: ReadTagInts(Ctx.Strm, Ctx.Big, E, 16, Subs);  // sub directories
    end;
  end;

  // is this an image we can read directly?
  BitsOk := Length(BitsA) >= 1;  // bits per sample are known
  if BitsOk then
  begin
    for K := 1 to High(BitsA) do  // all samples must have the same size
      if BitsA[K] <> BitsA[0] then BitsOk := False;
    if (BitsA[0] <> 8) and (BitsA[0] <> 16) then BitsOk := False;  // only 8 and 16 bits are supported
    if (Length(BitsA) <> Spp) and (Length(BitsA) <> 1) then BitsOk := False;  // one value per sample or a single value
  end;
  if (Rps <= 0) or (Rps > H) then Rps := H;  // a missing rows per strip value means one strip
  if (W > 0) and (H > 0) and (Comp = 1) and (Planar = 1) and (not HavePredictor) and BitsOk and  // plain, chunky 8 or 16-bit gray or RGB data with a full strip table
     ((Spp = 1) or (Spp = 3)) and ((Photo = 0) or (Photo = 1) or (Photo = 2)) and
     ((Photo = 2) = (Spp = 3)) and (Length(Offs) > 0) and
     (Int64(Length(Offs)) >= (H + Rps - 1) div Rps) then
  begin
    if (not Ctx.Found) or (W * H > Int64(Ctx.Best.W) * Ctx.Best.H) then  // keep the largest picture
    begin
      Ctx.Found := True;  // a picture was found
      Ctx.Best.Big := Ctx.Big;  // byte order
      Ctx.Best.W := Integer(W);  // width
      Ctx.Best.H := Integer(H);  // height
      Ctx.Best.Bits := Integer(BitsA[0]);  // bits per sample
      Ctx.Best.Spp := Integer(Spp);  // samples per pixel
      Ctx.Best.Photo := Integer(Photo);  // photometric type
      Ctx.Best.RowsPerStrip := Integer(Rps);  // rows per strip
      Ctx.Best.Offsets := Offs;  // strip offsets
    end;
  end;

  for K := 0 to High(Subs) do  // visit the sub directories
    TiffWalkIfd(Ctx, Subs[K], Depth + 1);
  Next := RdU32(Ctx.Strm, Ctx.Big, Off + 2 + N * 12);  // offset of the next directory
  TiffWalkIfd(Ctx, Next, Depth);  // visit it
end;

{ Finds the largest plain gray or RGB picture in a TIFF or DNG file. }
function FindTiffRgb(const FileName: string; out R: TTiffRgb): Boolean;
var
  Ctx: TTiffWalk;  // Ctx: search state
  Strm: TFileStream;  // Strm: the open file
  Hdr: array[0..7] of Byte;  // Hdr: file header
begin
  Result := False;  // assume failure
  R.Big := False;  // clear the result
  R.W := 0;  // clear the result
  R.H := 0;  // clear the result
  R.Bits := 0;  // clear the result
  R.Spp := 0;  // clear the result
  R.Photo := 0;  // clear the result
  R.RowsPerStrip := 1;  // clear the result
  R.Offsets := nil;  // clear the result
  Ctx.Strm := nil;  // clear the search state
  Ctx.Big := False;  // clear the search state
  Ctx.Size := 0;  // clear the search state
  Ctx.Seen := nil;  // clear the search state
  Ctx.Found := False;  // clear the search state
  Ctx.Best.Big := False;  // clear the search state
  Ctx.Best.W := 0;  // clear the search state
  Ctx.Best.H := 0;  // clear the search state
  Ctx.Best.Bits := 0;  // clear the search state
  Ctx.Best.Spp := 0;  // clear the search state
  Ctx.Best.Photo := 0;  // clear the search state
  Ctx.Best.RowsPerStrip := 1;  // clear the search state
  Ctx.Best.Offsets := nil;  // clear the search state
  Hdr[0] := 0;  // clear the header
  Hdr[1] := 0;  // clear the header
  Hdr[2] := 0;  // clear the header
  Hdr[3] := 0;  // clear the header
  Hdr[4] := 0;  // clear the header
  Hdr[5] := 0;  // clear the header
  Hdr[6] := 0;  // clear the header
  Hdr[7] := 0;  // clear the header
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Ctx.Strm := Strm;  // keep the file
    Ctx.Size := Strm.Size;  // keep the size
    if not StreamRead(Strm, 0, Hdr, 8) then Exit;  // read the header
    if (Hdr[0] = $49) and (Hdr[1] = $49) then Ctx.Big := False  // II marks little-endian
    else if (Hdr[0] = $4D) and (Hdr[1] = $4D) then Ctx.Big := True  // MM marks big-endian
    else Exit;
    if RdU16(Strm, Ctx.Big, 2) <> 42 then Exit;  // 42 is the TIFF version
    TiffWalkIfd(Ctx, RdU32(Strm, Ctx.Big, 4), 0);  // walk the first directory
  finally
    Strm.Free;  // close the file
  end;
  if Ctx.Found then  // a picture was found
  begin
    R := Ctx.Best;  // return it
    Result := True;  // success
  end;
end;

{ Reads one row of the plain picture into Buf. }
function ReadTiffRgbRow(Strm: TStream; const R: TTiffRgb; Row: Integer; var Buf: TBytes): Boolean;
var
  RowBytes, Strip: Integer;  // RowBytes: bytes per row; Strip: strip number
  Ofs: Int64;  // Ofs: position of the row
begin
  Result := False;  // assume failure
  if (Row < 0) or (Row >= R.H) or (R.RowsPerStrip < 1) then Exit;  // check the row number
  RowBytes := R.W * R.Spp * (R.Bits div 8);  // bytes per row
  Strip := Row div R.RowsPerStrip;  // strip of the row
  if Strip > High(R.Offsets) then Exit;  // strip outside the table
  Ofs := R.Offsets[Strip] + Int64(Row mod R.RowsPerStrip) * RowBytes;  // position of the row in the file
  if Length(Buf) < RowBytes then SetLength(Buf, RowBytes);  // make room for the row
  Result := StreamRead(Strm, Ofs, Buf[0], RowBytes);  // read the row
end;


{ ---- ISO base media files: Canon CR3 and HEIC/HEIF ---- }

{ Reads the header of the box at Pos: type, start of the payload and end of the box. }
function BoxHeader(Strm: TStream; Pos, Stop: Int64; out Typ: string;
  out Payload, BoxEnd: Int64): Boolean;
var
  Sz: Int64;  // Sz: size of the box
  B: array[0..3] of Byte;  // B: type bytes
  I: Integer;  // I: loop counter
begin
  Result := False;  // assume failure
  Typ := '';  // no type yet
  Payload := 0;  // no payload yet
  BoxEnd := 0;  // no end yet
  if Pos + 8 > Stop then Exit;  // a header needs 8 bytes
  Sz := RdU32(Strm, True, Pos);  // box size
  B[0] := 0; B[1] := 0; B[2] := 0; B[3] := 0;  // clear the type bytes
  if not StreamRead(Strm, Pos + 4, B, 4) then Exit;  // read the type
  for I := 0 to 3 do Typ := Typ + Chr(B[I]);  // build the type text
  Payload := Pos + 8;  // payload follows the header
  if Sz = 1 then  // size 1 means a 64-bit size follows
  begin
    Sz := RdU32(Strm, True, Pos + 8) * 4294967296 + RdU32(Strm, True, Pos + 12);  // 64-bit size
    Payload := Pos + 16;  // payload follows the long header
  end
  else if Sz = 0 then
    Sz := Stop - Pos;  // size 0 means the box reaches the end
  if Sz < 8 then Exit;  // implausible size
  BoxEnd := Pos + Sz;  // end of the box
  if BoxEnd > Stop then BoxEnd := Stop;  // keep the box inside its parent
  Result := Payload <= BoxEnd;  // success when the payload lies in the box
end;

{ Finds the child box of type Want between Start and Stop. }
function FindChild(Strm: TStream; Start, Stop: Int64; const Want: string;
  out Payload, BoxEnd: Int64): Boolean;
var
  P, PL, BE: Int64;  // P: position; PL: payload; BE: box end
  Typ: string;  // Typ: box type
  Guard: Integer;  // Guard: loop counter
begin
  Result := False;  // assume failure
  Payload := 0;  // no payload yet
  BoxEnd := 0;  // no end yet
  P := Start;  // start of the first box
  Guard := 0;  // no boxes yet
  while (Guard < 4096) and BoxHeader(Strm, P, Stop, Typ, PL, BE) do  // go through the boxes
  begin
    if Typ = Want then  // wanted box
    begin
      Payload := PL;  // return the payload
      BoxEnd := BE;  // return the box end
      Result := True;  // success
      Exit;
    end;
    if BE <= P then Break;  // stop on a broken size
    P := BE;  // next box
    Inc(Guard);  // count the box
  end;
end;

{ ---- MP4 / MOV / LRV movies ---- }

{ Reads the creation time and the length of a movie from its mvhd box. }
function ReadMovieHeader(const FileName: string; out Created: TDateTime; out HasDate: Boolean;
  out Duration: Double): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  MP, ME, HP, HE: Int64;  // MP, ME: moov payload and end; HP, HE: mvhd payload and end
  Ver: Integer;  // Ver: version of the mvhd box (0 = 32-bit fields, 1 = 64-bit fields)
  Secs, Scale, Dur: Int64;  // Secs: creation time in seconds since 1904; Scale: time units per second; Dur: length in time units
begin
  Result := False;  // assume failure
  Created := 0;  // no date yet
  HasDate := False;  // no date yet
  Duration := 0;  // no length yet
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    if not FindChild(Strm, 0, Strm.Size, 'moov', MP, ME) then Exit;  // find the movie box
    if not FindChild(Strm, MP, ME, 'mvhd', HP, HE) then Exit;  // find the movie header
    Ver := Integer(RdU32(Strm, True, HP) shr 24);  // first byte of the box is the version
    if Ver = 1 then  // 64-bit fields
    begin
      Secs := RdU32(Strm, True, HP + 4) * 4294967296 + RdU32(Strm, True, HP + 8);  // creation time
      Scale := RdU32(Strm, True, HP + 20);  // time units per second
      Dur := RdU32(Strm, True, HP + 24) * 4294967296 + RdU32(Strm, True, HP + 28);  // length
    end
    else  // 32-bit fields
    begin
      Secs := RdU32(Strm, True, HP + 4);  // creation time
      Scale := RdU32(Strm, True, HP + 12);  // time units per second
      Dur := RdU32(Strm, True, HP + 16);  // length
    end;
    if Scale > 0 then Duration := Dur / Scale;  // length in seconds
    if Duration < 0 then Duration := 0;  // never negative
    if Secs > 0 then  // a creation time is stored
    begin
      Created := EncodeDate(1904, 1, 1) + Secs / 86400;  // seconds since 1904-01-01 as a date
      HasDate := (Created >= EncodeDate(1990, 1, 1)) and (Created < Now + 2);  // reject zero-ish and future values
    end;
    Result := True;  // the header was read
  finally
    Strm.Free;  // close the file
  end;
end;

{ Finds the children of a meta box; QuickTime files omit the 4 version bytes that ISO files have. }
function FindMetaChild(Strm: TStream; MetaPL, MetaBE: Int64; const Want: string;
  out Payload, BoxEnd: Int64): Boolean;
begin
  Result := FindChild(Strm, MetaPL + 4, MetaBE, Want, Payload, BoxEnd);  // ISO layout: version and flags first
  if not Result then
    Result := FindChild(Strm, MetaPL, MetaBE, Want, Payload, BoxEnd);  // QuickTime layout: children start at once
end;

{ Copies the cover picture of a movie to Dest. }
function ExtractMovieCover(const FileName: string; Dest: TStream; out IsPng: Boolean): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  MP, ME, UP, UE, XP, XE, IP, IE, CP, CE, DP, DE: Int64;  // payload and end positions of moov, udta, meta, ilst, covr and data
  Kind, Len: Int64;  // Kind: data type of the cover (13 = JPEG, 14 = PNG); Len: size of the picture
begin
  Result := False;  // assume failure
  IsPng := False;  // JPEG unless found otherwise
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    if not FindChild(Strm, 0, Strm.Size, 'moov', MP, ME) then Exit;  // movie box
    if not FindChild(Strm, MP, ME, 'udta', UP, UE) then Exit;  // user data box
    if not FindChild(Strm, UP, UE, 'meta', XP, XE) then Exit;  // metadata box
    if not FindMetaChild(Strm, XP, XE, 'ilst', IP, IE) then Exit;  // item list
    if not FindChild(Strm, IP, IE, 'covr', CP, CE) then Exit;  // cover item
    if not FindChild(Strm, CP, CE, 'data', DP, DE) then Exit;  // cover data
    Kind := RdU32(Strm, True, DP) and $FFFFFF;  // data type from the flags
    Len := DE - (DP + 8);  // picture bytes follow the type and locale fields
    if (Len < 100) or (Len > 8388608) then Exit;  // implausible size
    if (Kind <> 13) and (Kind <> 14) then Exit;  // only JPEG and PNG covers
    IsPng := Kind = 14;  // report the format
    Strm.Position := DP + 8;  // start of the picture
    Dest.CopyFrom(Strm, Len);  // copy it
    Result := True;  // success
  finally
    Strm.Free;  // close the file
  end;
end;

{ copies a TIFF structure (II*/MM*) from the file into T, with Base = 0 }
function LoadTiffBlock(Strm: TStream; Ofs, Count: Int64; out T: TTiff): Boolean;
begin
  Result := False;  // assume failure
  T.Buf := nil;  // release any old array
  T.Base := 0;  // base at the start
  T.Big := False;  // little-endian by default
  if (Count < 16) or (Count > 1048576) then Exit;  // reject implausible sizes
  SetLength(T.Buf, Integer(Count));  // reserve the bytes
  if not StreamRead(Strm, Ofs, T.Buf[0], Integer(Count)) then Exit;  // read the bytes
  if (T.Buf[0] = $4D) and (T.Buf[1] = $4D) then  // MM marks big-endian
    T.Big := True  // big-endian
  else if not ((T.Buf[0] = $49) and (T.Buf[1] = $49)) then
    Exit;  // anything but II is invalid
  Result := U16(T, 2) = 42;  // 42 is the TIFF version
end;

{ the Canon-specific string tag 0x0096 (body serial) from a maker note block }
function CanonMakerSerial(const T: TTiff): string;
var
  P, N, I, E: Integer;  // P: directory position; N: entry count; I: loop counter; E: entry position
begin
  Result := '';  // empty by default
  P := Integer(U32(T, 4));  // directory position
  if (P <= 0) or (P + 2 > Length(T.Buf)) then Exit;  // directory outside the data
  N := U16(T, P);  // number of entries
  if N > 300 then Exit;  // reject an implausible count
  for I := 0 to N - 1 do  // every entry
  begin
    E := P + 2 + I * 12;  // position of the entry
    if E + 12 > Length(T.Buf) then Break;  // entry outside the data
    if U16(T, E) = $0096 then  // tag 0x0096
    begin
      Result := GetStr(T, E);  // read the text
      Exit;
    end;
  end;
end;

{ Reads the EXIF data of a Canon CR3 file from the Canon uuid box. }
function ReadCr3Exif(Strm: TStream; MoovStart, MoovEnd: Int64; var Info: TExifInfo): Boolean;
const
  CanonUuid: array[0..15] of Byte =  // identifier of the Canon uuid box
    ($85, $C0, $B6, $87, $82, $0F, $11, $E0, $81, $11, $F4, $CE, $46, $2B, $6A, $48);
var
  P, PL, BE, CP, CE: Int64;  // P: position; PL: payload; BE: box end; CP: payload of the child; CE: end of the child
  Typ: string;  // Typ: box type
  U: array[0..15] of Byte;  // U: uuid read from the file
  I, Guard: Integer;  // I: loop counter; Guard: box counter
  Same: Boolean;  // Same: True when the uuid matches
  T: TTiff;  // T: TIFF structure of the child
begin
  Result := False;  // assume failure
  P := MoovStart;  // first box
  Guard := 0;  // no boxes yet
  while (Guard < 256) and BoxHeader(Strm, P, MoovEnd, Typ, PL, BE) do  // go through the boxes
  begin
    Inc(Guard);  // count the box
    if Typ = 'uuid' then  // uuid box
    begin
      for I := 0 to 15 do U[I] := 0;  // clear the uuid
      Same := StreamRead(Strm, PL, U, 16);  // read the uuid
      if Same then
        for I := 0 to 15 do  // compare with the Canon uuid
          if U[I] <> CanonUuid[I] then Same := False;
      if Same then  // Canon box found
      begin
        // CMT1 = TIFF IFD0, CMT2 = EXIF IFD, CMT3 = Canon maker note
        if FindChild(Strm, PL + 16, BE, 'CMT1', CP, CE) and LoadTiffBlock(Strm, CP, CE - CP, T) then  // IFD0 of the picture
          ReadIFD(T, U32(T, 4), 0, Info);  // read the directory
        if FindChild(Strm, PL + 16, BE, 'CMT2', CP, CE) and LoadTiffBlock(Strm, CP, CE - CP, T) then  // EXIF directory
          ReadIFD(T, U32(T, 4), 0, Info);  // read the directory
        if (Info.Serial = '') and FindChild(Strm, PL + 16, BE, 'CMT3', CP, CE) and  // serial number from the maker note
           LoadTiffBlock(Strm, CP, CE - CP, T) then
          Info.Serial := CanonMakerSerial(T);  // take the serial number
        Result := True;  // success
        Exit;
      end;
    end;
    if BE <= P then Break;  // stop on a broken size
    P := BE;  // next box
  end;
end;

{ Reads an unsigned big-endian value of N (4 or 8) bytes from a stream. }
function RdN(Strm: TStream; Ofs: Int64; N: Integer): Int64;
begin
  case N of  // by size
    4: Result := RdU32(Strm, True, Ofs);  // 4 bytes
    8: Result := RdU32(Strm, True, Ofs) * 4294967296 + RdU32(Strm, True, Ofs + 4);  // 8 bytes
  else
    Result := 0;  // other sizes are not used
  end;
end;

{ Reads the EXIF data of a HEIC file through the item tables (iinf and iloc). }
function ReadHeifExif(Strm: TStream; MetaStart, MetaEnd: Int64; var Info: TExifInfo): Boolean;
var
  IinfP, IinfE, IlocP, IlocE, P, PL, BE, Q, ExtOfs, ExtLen, BaseOfs, ExtOne, HdrOfs: Int64;  // IinfP, IinfE: item info box; IlocP, IlocE: item location box; P, PL, BE: box position, payload, end; Q: position in the table; ExtOfs, ExtLen: offset and length of the extent; BaseOfs: base offset; ExtOne: extent offset; HdrOfs: header offset
  Typ: string;  // Typ: box type
  Ver, Cnt, I, J, OffSz, LenSz, BaseSz, IdxSz, K, ExtCnt: Integer;  // Ver: box version; Cnt: item count; I, J: loop counters; OffSz, LenSz, BaseSz, IdxSz: field sizes; K: field offset; ExtCnt: extent count
  ExifId, ItemId: Int64;  // ExifId: item id of the EXIF item; ItemId: item id read
  B: array[0..3] of Byte;  // B: small read buffer
  T: TTiff;  // T: TIFF structure of the EXIF data
  Guard: Integer;  // Guard: box counter
begin
  Result := False;  // assume failure
  if not FindChild(Strm, MetaStart, MetaEnd, 'iinf', IinfP, IinfE) then Exit;  // find the item info box
  if not FindChild(Strm, MetaStart, MetaEnd, 'iloc', IlocP, IlocE) then Exit;  // find the item location box

  // 1. item id of the Exif item
  ExifId := -1;  // no EXIF item yet
  B[0] := 0; B[1] := 0; B[2] := 0; B[3] := 0;  // clear the buffer
  StreamRead(Strm, IinfP, B, 1);  // read the version
  if B[0] = 0 then P := IinfP + 4 + 2 else P := IinfP + 4 + 4;  // skip the header (the entry count size depends on the version)
  Guard := 0;  // no boxes yet
  while (Guard < 4096) and BoxHeader(Strm, P, IinfE, Typ, PL, BE) do  // go through the item entries
  begin
    Inc(Guard);  // count the entry
    if Typ = 'infe' then  // item info entry
    begin
      B[0] := 0;  // clear the buffer
      StreamRead(Strm, PL, B, 1);  // read the version
      if B[0] = 2 then  // version 2: 16-bit item id
      begin
        ItemId := RdU16(Strm, True, PL + 4);  // read the item id
        K := 8;  // offset of the item type
      end
      else if B[0] = 3 then  // version 3: 32-bit item id
      begin
        ItemId := RdU32(Strm, True, PL + 4);  // read the item id
        K := 10;  // offset of the item type
      end
      else
      begin
        ItemId := -1;  // unknown version
        K := 0;  // no offset
      end;
      if (ItemId >= 0) and StreamRead(Strm, PL + K, B, 4) then  // read the item type
        if (B[0] = Ord('E')) and (B[1] = Ord('x')) and (B[2] = Ord('i')) and (B[3] = Ord('f')) then  // type is Exif
        begin
          ExifId := ItemId;  // remember the item id
          Break;  // stop searching
        end;
    end;
    if BE <= P then Break;  // stop on a broken size
    P := BE;  // next entry
  end;
  if ExifId < 0 then Exit;  // no EXIF item found

  // 2. its location (iloc, construction method 0 = offset in the file)
  B[0] := 0;  // clear the buffer
  StreamRead(Strm, IlocP, B, 1);  // read the version
  Ver := B[0];  // box version
  if Ver > 2 then Exit;  // unknown version
  StreamRead(Strm, IlocP + 4, B, 2);  // read the field sizes
  OffSz := B[0] shr 4;  // size of the offset field
  LenSz := B[0] and 15;  // size of the length field
  BaseSz := B[1] shr 4;  // size of the base offset field
  if Ver = 0 then IdxSz := 0 else IdxSz := B[1] and 15;  // size of the index field (version 1 and 2 only)
  if Ver < 2 then  // version 0 and 1 use a 16-bit item count
  begin
    Cnt := RdU16(Strm, True, IlocP + 6);  // item count
    Q := IlocP + 8;  // position of the first item
  end
  else
  begin
    Cnt := Integer(RdU32(Strm, True, IlocP + 6));  // item count
    Q := IlocP + 10;  // position of the first item
  end;
  if Cnt > 20000 then Exit;  // reject an implausible count
  for I := 0 to Cnt - 1 do  // every item
  begin
    if Ver < 2 then  // version 0 and 1 use a 16-bit item id
    begin
      ItemId := RdU16(Strm, True, Q);  // item id
      Inc(Q, 2);  // move past the id
    end
    else
    begin
      ItemId := RdU32(Strm, True, Q);  // item id
      Inc(Q, 4);  // move past the id
    end;
    if Ver >= 1 then  // versions 1 and later have a construction method
    begin
      K := RdU16(Strm, True, Q) and 15;   // construction method
      Inc(Q, 2);  // move past the field
    end
    else
      K := 0;  // version 0 has no construction method
    Inc(Q, 2);                             // data reference index
    BaseOfs := RdN(Strm, Q, BaseSz);  // base offset
    Inc(Q, BaseSz);  // move past the base offset
    ExtCnt := RdU16(Strm, True, Q);  // number of extents
    Inc(Q, 2);  // move past the count
    ExtOne := -1;  // no extent yet
    ExtLen := 0;  // no length yet
    for J := 0 to ExtCnt - 1 do  // every extent
    begin
      if IdxSz > 0 then Inc(Q, IdxSz);  // skip the extent index
      ExtOfs := RdN(Strm, Q, OffSz);  // offset of the extent
      Inc(Q, OffSz);  // move past the offset
      ExtLen := RdN(Strm, Q, LenSz);  // length of the extent
      Inc(Q, LenSz);  // move past the length
      if J = 0 then ExtOne := BaseOfs + ExtOfs;  // remember the first extent
    end;
    if (ItemId = ExifId) and (K = 0) and (ExtOne >= 0) and (ExtLen > 8) then  // this is the EXIF item stored in the file
    begin
      // payload = 4 byte offset to the TIFF header, then the data
      HdrOfs := RdU32(Strm, True, ExtOne);  // offset to the TIFF header
      if (HdrOfs < 0) or (HdrOfs + 4 >= ExtLen) then Exit;  // reject implausible values
      if LoadTiffBlock(Strm, ExtOne + 4 + HdrOfs, ExtLen - 4 - HdrOfs, T) then  // read the TIFF data
      begin
        ReadIFD(T, U32(T, 4), 0, Info);  // read the directory
        Result := True;  // success
      end;
      Exit;
    end;
  end;
end;

{ Canon CR3 and HEIC/HEIF: EXIF data from the container boxes }
function ReadBmffFromFile(const FileName: string; var Info: TExifInfo): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  Size, P, PL, BE: Int64;  // Size: file size; P, PL, BE: box position, payload, end
  Typ: string;  // Typ: box type
  Guard: Integer;  // Guard: box counter
begin
  Result := False;  // assume failure
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Size := Strm.Size;  // file size
    P := 0;  // first box
    Guard := 0;  // no boxes yet
    while (Guard < 64) and BoxHeader(Strm, P, Size, Typ, PL, BE) do  // go through the top level boxes
    begin
      Inc(Guard);  // count the box
      if Typ = 'moov' then  // movie box (Canon CR3)
        ReadCr3Exif(Strm, PL, BE, Info)  // read the Canon boxes
      else if Typ = 'meta' then  // meta box (HEIC)
        ReadHeifExif(Strm, PL + 4, BE, Info);  // read the item tables
      if BE <= P then Break;  // stop on a broken size
      P := BE;  // next box
    end;
  finally
    Strm.Free;  // close the file
  end;
  Result := (Info.Make <> '') or (Info.Model <> '') or Info.HasDate;  // success when a camera or date was found
end;

{ Reads the largest stored picture size (ispe property) of a HEIC file. }
function ReadHeifStoredSize(const FileName: string; out W, H: Integer): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  Size, P, PL, BE, IP, IE, CP, CE, Q, QL, QE, AW, AH, Best: Int64;  // Size: file size; P, PL, BE: top level box; IP, IE: iprp box; CP, CE: ipco box; Q, QL, QE: property box; AW, AH: property size; Best: largest area
  Typ, Typ2: string;  // Typ, Typ2: box types
  Guard, G2: Integer;  // Guard, G2: box counters
begin
  Result := False;  // assume failure
  W := 0;  // no width yet
  H := 0;  // no height yet
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Size := Strm.Size;  // file size
    P := 0;  // first box
    Guard := 0;  // no boxes yet
    while (Guard < 64) and BoxHeader(Strm, P, Size, Typ, PL, BE) do  // go through the top level boxes
    begin
      Inc(Guard);  // count the box
      if Typ = 'meta' then  // meta box
        if FindChild(Strm, PL + 4, BE, 'iprp', IP, IE) and FindChild(Strm, IP, IE, 'ipco', CP, CE) then  // find the property container
        begin
          Q := CP;  // first property
          G2 := 0;  // no properties yet
          Best := 0;  // no size yet
          while (G2 < 4096) and BoxHeader(Strm, Q, CE, Typ2, QL, QE) do  // go through the properties
          begin
            Inc(G2);  // count the property
            if Typ2 = 'ispe' then  // image size property
            begin
              AW := RdU32(Strm, True, QL + 4);  // width
              AH := RdU32(Strm, True, QL + 8);  // height
              if AW * AH > Best then  // larger than the best so far
              begin
                Best := AW * AH;  // new best area
                W := Integer(AW);  // width
                H := Integer(AH);  // height
              end;
            end;
            if QE <= Q then Break;  // stop on a broken size
            Q := QE;  // next property
          end;
          Result := Best > 0;  // success when a size was found
          Exit;
        end;
      if BE <= P then Break;
      P := BE;  // stop on a broken size
    end;  // next box
  finally
    Strm.Free;  // close the file
  end;
end;

{ Reads the EXIF data of a JPEG, TIFF-based raw, CRW, CR3 or HEIC file. }
function ReadExifFromFile(const FileName: string; out Info: TExifInfo): Boolean;
var
  FS: TFileStream;  // FS: the open file
  Len, Pos, Mk, L: Integer;  // Len: bytes read; Pos: position; Mk: marker; L: segment length
  T: TTiff;  // T: TIFF structure
begin
  Result := False;  // assume failure
  T.Buf := nil;  // no data yet
  T.Base := -1;  // no TIFF header yet
  T.Big := False;  // little-endian by default
  Info.Valid := False;  // nothing valid yet
  Info.Make := ''; Info.Model := ''; Info.Artist := ''; Info.Owner := '';  // clear the text fields
  Info.Serial := ''; Info.DateTaken := 0; Info.HasDate := False;  // clear the other fields
  Info.ISO := 0; Info.Orientation := 0;  // clear the numbers
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Len := FS.Size;  // file size
    if Len > 262144 then Len := 262144;  // read at most 256 KB
    SetLength(T.Buf, Len);  // reserve the buffer
    if Len > 0 then FS.ReadBuffer(T.Buf[0], Len);  // read the start of the file
  finally
    FS.Free;  // close the file
  end;
  if Len < 12 then Exit;  // too short

  if IsCiff(T.Buf) then  // Canon CRW
  begin
    // Canon CRW is not a TIFF file: read make, model and time from its CIFF directories
    Info.Valid := ReadCiffFromFile(FileName, Info);  // read the CIFF directories
    Result := Info.Valid;  // return the result
    Exit;
  end;

  if (T.Buf[4] = Ord('f')) and (T.Buf[5] = Ord('t')) and (T.Buf[6] = Ord('y')) and  // ftyp box: CR3 or HEIC
     (T.Buf[7] = Ord('p')) then
  begin
    // Canon CR3 and HEIC/HEIF are ISO base media files
    Info.Valid := ReadBmffFromFile(FileName, Info);  // read the container boxes
    Result := Info.Valid;  // return the result
    Exit;
  end;

  T.Base := -1;  // no TIFF header yet
  if (T.Buf[0] = $FF) and (T.Buf[1] = $D8) then  // JPEG
  begin
    Pos := 2;  // first marker
    while Pos + 4 <= Len do  // go through the markers
    begin
      if T.Buf[Pos] <> $FF then Break;  // every marker starts with FF
      Mk := T.Buf[Pos + 1];  // marker code
      if Mk = $FF then begin Inc(Pos); Continue; end;  // skip fill bytes
      if (Mk = $D9) or (Mk = $DA) then Break;  // end of image or start of scan
      L := (T.Buf[Pos + 2] shl 8) or T.Buf[Pos + 3];  // segment length
      if (Mk = $E1) and (Pos + 10 <= Len) and (T.Buf[Pos + 4] = Ord('E')) and  // APP1 segment that starts with Exif
         (T.Buf[Pos + 5] = Ord('x')) and (T.Buf[Pos + 6] = Ord('i')) and
         (T.Buf[Pos + 7] = Ord('f')) then
      begin
        T.Base := Pos + 10;  // TIFF header follows the identifier
        Break;  // stop searching
      end;
      Pos := Pos + 2 + L;  // next segment
    end;
  end
  else if ((T.Buf[0] = $49) and (T.Buf[1] = $49)) or  // TIFF based file
          ((T.Buf[0] = $4D) and (T.Buf[1] = $4D)) then
    T.Base := 0;  // header at the start

  if (T.Base < 0) or (T.Base + 8 > Len) then Exit;  // no usable TIFF header
  T.Big := T.Buf[T.Base] = $4D;  // MM marks big-endian
  if U16(T, T.Base + 2) <> 42 then Exit;  // 42 is the TIFF version
  ReadIFD(T, U32(T, T.Base + 4), 0, Info);  // read the first directory
  Info.Valid := (Info.Make <> '') or (Info.Model <> '') or Info.HasDate;  // valid when a camera or a date was found
  // a file with only an orientation (no camera or date) still needs to be turned upright
  Result := Info.Valid or (Info.Orientation <> 0);  // also useful when only the orientation is known
end;

{ ---- JPEG helpers (previews and thumbnails) ---- }

{ True for the JPEG frame types that can be decoded. }
function IsUsableSof(Mk: Integer): Boolean;
begin
  // baseline, extended sequential, progressive; not lossless (C3) as used for raw data
  Result := (Mk = $C0) or (Mk = $C1) or (Mk = $C2);  // baseline, extended sequential or progressive
end;

{ Reads the picture size and component count of the JPEG that starts at Start. }
function JpegDims(const B: TBytes; Start, Limit: Integer; out W, H, Comps: Integer): Boolean;
var
  P, Mk, L: Integer;  // P: position; Mk: marker; L: segment length
begin
  Result := False;  // assume failure
  W := 0;  // no width yet
  H := 0;  // no height yet
  Comps := 0;  // no components yet
  P := Start + 2;  // first marker
  while P + 4 <= Limit do  // go through the markers
  begin
    if B[P] <> $FF then Exit;  // every marker starts with FF
    Mk := B[P + 1];  // marker code
    if Mk = $FF then begin Inc(P); Continue; end;  // skip fill bytes
    if (Mk = $01) or ((Mk >= $D0) and (Mk <= $D8)) then begin Inc(P, 2); Continue; end;  // markers without a length
    if (Mk = $D9) or (Mk = $DA) then Exit;  // end of image or start of scan
    L := (B[P + 2] shl 8) or B[P + 3];  // segment length
    if L < 2 then Exit;  // implausible length
    if IsUsableSof(Mk) then  // frame header
    begin
      if P + 10 > Limit then Exit;  // header too short
      H := (B[P + 5] shl 8) or B[P + 6];  // height
      W := (B[P + 7] shl 8) or B[P + 8];  // width
      Comps := B[P + 9];  // number of components
      Result := (W > 0) and (H > 0);  // success when the size is valid
      Exit;
    end;
    P := P + 2 + L;  // next segment
  end;
end;

{ returns the offset just after the EOI marker of the JPEG that starts at Start, or -1 }
function JpegEnd(const B: TBytes; Start, Limit: Integer): Integer;
var
  P, Mk, L: Integer;  // P: position; Mk: marker; L: segment length
  SawSof: Boolean;  // SawSof: True once a frame header was seen
begin
  Result := -1;  // assume failure
  SawSof := False;  // no frame header yet
  P := Start + 2;  // first marker
  while P + 2 <= Limit do  // go through the markers
  begin
    if B[P] <> $FF then Exit;  // every marker starts with FF
    Mk := B[P + 1];  // marker code
    if Mk = $FF then begin Inc(P); Continue; end;  // skip fill bytes
    if (Mk = $01) or ((Mk >= $D0) and (Mk <= $D7)) then begin Inc(P, 2); Continue; end;  // markers without a length
    if Mk = $D9 then  // end of image
    begin
      if SawSof then Result := P + 2;  // only valid when a frame header was seen
      Exit;
    end;
    if P + 4 > Limit then Exit;  // marker too short
    L := (B[P + 2] shl 8) or B[P + 3];  // segment length
    if L < 2 then Exit;  // implausible length
    if IsUsableSof(Mk) then SawSof := True;  // remember the frame header
    if Mk = $DA then  // start of scan
    begin
      if not SawSof then Exit;  // a scan needs a frame header
      P := P + 2 + L;  // skip the scan header
      // entropy coded data: runs until a marker that is not a restart or stuffed FF 00
      while P + 1 < Limit do  // skip the entropy coded data
      begin
        if (B[P] = $FF) and (B[P + 1] <> 0) and (B[P + 1] <> $FF) and  // stop at the next real marker
           not ((B[P + 1] >= $D0) and (B[P + 1] <= $D7)) then Break;
        Inc(P);  // next byte
      end;
      if P + 1 >= Limit then Exit;  // ran out of data
      Continue;
    end;
    P := P + 2 + L;  // next segment
  end;
end;

{ Reads the pixel size of a JPEG file from its header. }
function ReadJpegDims(const FileName: string; out W, H: Integer): Boolean;
var
  Strm: TFileStream;  // Strm: the open file
  Buf: TBytes;  // Buf: start of the file
  Len, Comps: Integer;  // Len: bytes read; Comps: component count
begin
  Result := False;  // assume failure
  W := 0;  // no width yet
  H := 0;  // no height yet
  Buf := nil;  // release any old array
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Len := Strm.Size;  // file size
    if Len > 262144 then Len := 262144;  // read at most 256 KB
    SetLength(Buf, Len);  // reserve the buffer
    if Len > 0 then Strm.ReadBuffer(Buf[0], Len);  // read the start of the file
  finally
    Strm.Free;  // close the file
  end;
  if (Len < 12) or (Buf[0] <> $FF) or (Buf[1] <> $D8) then Exit;  // must start with the JPEG signature
  Result := JpegDims(Buf, 0, Len, W, H, Comps);  // read the size
end;

type
  { A JPEG found inside a raw file. }
  TJpegCand = record
    Pos, Len, W, H, Comps: Integer;  // Pos: start; Len: length; W, H: size; Comps: component count
  end;
  TJpegCands = array of TJpegCand;  // list of candidates

{ reads up to MaxBytes from the start of the file; returns the number of bytes read }
function ReadPrefix(const FileName: string; MaxBytes: Integer; out Buf: TBytes;
  out FileLen: Int64): Integer;
var
  Strm: TFileStream;  // Strm: the open file
begin
  Result := 0;  // nothing read
  Buf := nil;  // release any old array
  FileLen := 0;  // no file size yet
  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    FileLen := Strm.Size;  // file size
    if FileLen > MaxBytes then Result := MaxBytes else Result := Integer(FileLen);  // limit to MaxBytes
    SetLength(Buf, Result);  // reserve the buffer
    if Result > 0 then Strm.ReadBuffer(Buf[0], Result);  // read the bytes
  finally
    Strm.Free;  // close the file
  end;
end;

{ Finds the JPEG images embedded in a block of bytes. }
procedure FindJpegs(const B: TBytes; Len: Integer; var C: TJpegCands);
var
  P, E, CW, CH, CC, N, I, K: Integer;  // P: position; E: end of a JPEG; CW, CH: size; CC: components; N: candidate count; I, K: loop counters
  HaveColor: Boolean;  // HaveColor: True when a color candidate exists
begin
  C := nil;  // no candidates yet
  N := 0;  // none found
  P := 0;  // start at the beginning
  while P + 4 < Len do  // go through the bytes
  begin
    if (B[P] = $FF) and (B[P + 1] = $D8) and (B[P + 2] = $FF) then  // JPEG start marker
    begin
      E := JpegEnd(B, P, Len);  // find the end
      if E > P then  // a complete JPEG was found
      begin
        if JpegDims(B, P, Len, CW, CH, CC) then  // read its size
        begin
          SetLength(C, N + 1);  // add a candidate
          C[N].Pos := P;  // start
          C[N].Len := E - P;  // length
          C[N].W := CW;  // width
          C[N].H := CH;  // height
          C[N].Comps := CC;  // component count
          Inc(N);  // count the candidate
          if N >= 24 then Break;  // stop at 24 candidates
        end;
        P := E;            // skip this JPEG, including any thumbnail nested inside it
        Continue;
      end;
    end;
    Inc(P);  // next byte
  end;
  // Some RAW formats (Canon CRW) store the sensor data as a single-component JPEG,
  // which looks like a huge gray image. When color previews exist, ignore those.
  HaveColor := False;  // no color candidate yet
  for I := 0 to High(C) do  // look at all candidates
    if C[I].Comps = 3 then HaveColor := True;  // three components means a color picture
  if HaveColor then  // color pictures exist
  begin
    K := 0;  // number of candidates kept
    for I := 0 to High(C) do  // look at all candidates
      if C[I].Comps = 3 then  // keep color pictures only
      begin
        C[K] := C[I];  // move the candidate down
        Inc(K);  // count it
      end;
    SetLength(C, K);  // drop the others
  end;
end;

{ Copies the embedded JPEG of the given rank (0 = largest) to Dest and returns its size. }
function ExtractEmbeddedJpeg(const FileName: string; Rank: Integer; Deep: Boolean;
  Dest: TStream; out W, H: Integer): Boolean;
var
  Buf: TBytes;  // Buf: bytes read from the file
  Got, I, J: Integer;  // Got: bytes read; I, J: loop counters
  FLen: Int64;  // FLen: file size
  C: TJpegCands;  // C: embedded JPEGs found
  Tmp: TJpegCand;  // Tmp: swap helper
  BestLen: Integer;  // BestLen: length of the largest JPEG
begin
  Result := False;  // assume failure
  W := 0;  // no width yet
  H := 0;  // no height yet
  Buf := nil;  // release any old array
  C := nil;  // release any old array
  Got := ReadPrefix(FileName, 4 * 1024 * 1024, Buf, FLen);  // read the first 4 MB
  if Got = 0 then Exit;  // nothing read
  FindJpegs(Buf, Got, C);  // find the embedded JPEGs
  BestLen := 0;  // no JPEG yet
  for I := 0 to High(C) do  // look at all candidates
    if C[I].Len > BestLen then BestLen := C[I].Len;  // remember the longest length
  // nothing sizable in the first 4 MB: some cameras store the preview later in the file
  if Deep and (BestLen < 20000) and (FLen > Got) then  // no large JPEG yet: search the rest of the file
  begin
    Got := ReadPrefix(FileName, 96 * 1024 * 1024, Buf, FLen);  // read up to 96 MB
    FindJpegs(Buf, Got, C);  // find the embedded JPEGs again
  end;
  // largest first
  for I := 1 to High(C) do  // insertion sort, largest first
  begin
    Tmp := C[I];  // entry to place
    J := I - 1;  // compare with the previous entries
    while (J >= 0) and (C[J].Len < Tmp.Len) do  // move smaller entries up
    begin
      C[J + 1] := C[J];  // shift the entry
      Dec(J);  // previous entry
    end;
    C[J + 1] := Tmp;  // place the entry
  end;
  if (Rank < 0) or (Rank > High(C)) then Exit;  // rank out of range
  if C[Rank].Len < 4096 then Exit;  // ignore tiny JPEGs
  Dest.WriteBuffer(Buf[C[Rank].Pos], C[Rank].Len);  // write the JPEG to the destination
  W := C[Rank].W;  // width
  H := C[Rank].H;  // height
  Result := True;  // success
end;

{ ---- writing ---- }

type
  { One 12-byte directory entry. }
  TEntry = record
    Tag: Integer;  // tag number
    Raw: TBytes;          // the 12-byte IFD entry
  end;

{ Writes a 16-bit value into B at Ofs in the given byte order. }
procedure PutU16(var B: TBytes; Ofs, V: Integer; Big: Boolean);
begin
  if Big then
  begin
    B[Ofs] := (V shr 8) and $FF;  // high byte
    B[Ofs + 1] := V and $FF;  // low byte
  end
  else
  begin
    B[Ofs] := V and $FF;  // low byte
    B[Ofs + 1] := (V shr 8) and $FF;  // high byte
  end;
end;

{ Writes a 32-bit value into B at Ofs in the given byte order. }
procedure PutU32(var B: TBytes; Ofs: Integer; V: Int64; Big: Boolean);
var
  I: Integer;  // I: byte index
begin
  for I := 0 to 3 do  // each byte
    if Big then
      B[Ofs + 3 - I] := (V shr (8 * I)) and $FF  // big-endian position
    else
      B[Ofs + I] := (V shr (8 * I)) and $FF;  // little-endian position
end;

{ appends N zero bytes and returns the old length }
function Grow(var B: TBytes; N: Integer): Integer;
begin
  Result := Length(B);  // old length
  SetLength(B, Result + N);  // make room
  FillChar(B[Result], N, 0);  // clear the new bytes
end;

{ Adds missing Artist and Copyright tags to a JPEG file in place; existing values are kept. }
function WriteExifOwnerFields(const FileName, Artist, Copyright: string): Boolean;
var
  Src, Tiff, Outp: TBytes;  // Src: the file; Tiff: new TIFF block; Outp: new file
  Entries: array of TEntry;  // Entries: directory entries
  Len, Pos, Mk, L, SegStart, SegEnd, Base, Cnt, I, J, K, Ofs, InsertAt, Pre, Post: Integer;  // Len: file size; Pos: position; Mk: marker; L: length; SegStart, SegEnd: EXIF segment; Base: TIFF header; Cnt: entry count; I, J, K: loop counters; Ofs: directory offset; InsertAt: where a new segment goes; Pre, Post: parts of the file kept
  T: TTiff;  // T: TIFF structure of the old data
  Big, Found: Boolean;  // Big: big-endian data; Found: EXIF segment found
  Strm: TFileStream;  // Strm: file stream
  Next: Int64;  // Next: offset of the next directory
  Tmp: TEntry;  // Tmp: swap helper
  TmpName: string;  // TmpName: temporary file name
  ArtistExists, CopyExists, WantArtist, WantCopy: Boolean;  // ArtistExists, CopyExists: tags already filled; WantArtist, WantCopy: tags to add

  procedure AddAscii(ATag: Integer; const S: string);
  var
    N, Data, C: Integer;  // N: text length; Data: position of the text; C: character index
    E: TEntry;  // E: new entry
  begin
    if S = '' then Exit;  // nothing to add
    N := Length(S) + 1;  // length with the terminating zero
    E.Tag := ATag;  // tag number
    E.Raw := nil;  // release any old array
    SetLength(E.Raw, 12);  // reserve the entry bytes
    FillChar(E.Raw[0], 12, 0);  // clear them
    PutU16(E.Raw, 0, ATag, Big);  // tag
    PutU16(E.Raw, 2, 2, Big);              // type 2 = ASCII
    PutU32(E.Raw, 4, N, Big);  // number of characters
    if N <= 4 then  // short texts fit in the entry
    begin
      for C := 1 to Length(S) do
        E.Raw[7 + C] := Ord(S[C]);          // stored inline in the value field
    end
    else
    begin
      if Odd(Length(Tiff)) then Grow(Tiff, 1);  // keep the data word aligned
      Data := Grow(Tiff, N);  // reserve room for the text
      for C := 1 to Length(S) do
        Tiff[Data + C - 1] := Ord(S[C]);  // copy the character
      PutU32(E.Raw, 8, Data, Big);  // offset of the text
    end;
    SetLength(Entries, Length(Entries) + 1);  // add a directory entry
    Entries[High(Entries)] := E;  // store the entry
  end;

begin
  Result := False;  // assume failure
  Src := nil;  // release any old array
  Tiff := nil;  // release any old array
  Outp := nil;  // release any old array
  Entries := nil;  // release any old array
  T.Buf := nil;  // release any old array
  T.Base := 0;  // base at the start
  T.Big := False;  // little-endian by default
  Next := 0;  // no next directory
  Big := False;  // little-endian by default
  ArtistExists := False;  // no artist yet
  CopyExists := False;  // no copyright yet
  if (Artist = '') and (Copyright = '') then  // nothing to write
  begin
    Result := True;  // nothing to do counts as success
    Exit;
  end;

  try
    Strm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);  // open the file
  except
    Exit;  // cannot open
  end;
  try
    Len := Strm.Size;  // file size
    SetLength(Src, Len);  // reserve the buffer
    if Len > 0 then Strm.ReadBuffer(Src[0], Len);  // read the file
  finally
    Strm.Free;  // close the file
  end;
  if (Len < 4) or (Src[0] <> $FF) or (Src[1] <> $D8) then Exit;  // must be a JPEG

  // locate the Exif APP1 segment; remember where to insert one if there is none
  Found := False;  // EXIF segment not found yet
  SegStart := 0;  // start of the segment
  SegEnd := 0;  // end of the segment
  InsertAt := 2;  // a new segment goes after the SOI marker
  Pos := 2;  // first marker
  while Pos + 4 <= Len do  // go through the markers
  begin
    if Src[Pos] <> $FF then Break;  // every marker starts with FF
    Mk := Src[Pos + 1];  // marker code
    if Mk = $FF then begin Inc(Pos); Continue; end;  // skip fill bytes
    if (Mk = $D9) or (Mk = $DA) then Break;  // end of image or start of scan
    L := (Src[Pos + 2] shl 8) or Src[Pos + 3];  // segment length
    if L < 2 then Break;  // implausible length
    if (Mk = $E1) and (Pos + 10 <= Len) and (Src[Pos + 4] = Ord('E')) and  // APP1 segment that starts with Exif
       (Src[Pos + 5] = Ord('x')) and (Src[Pos + 6] = Ord('i')) and (Src[Pos + 7] = Ord('f')) then
    begin
      Found := True;  // EXIF segment found
      SegStart := Pos;  // start of the segment
      SegEnd := Pos + 2 + L;  // end of the segment
      Break;
    end;
    if (Mk = $E0) and (Pos = 2) then InsertAt := Pos + 2 + L;   // keep JFIF first
    Pos := Pos + 2 + L;  // next segment
  end;

  if Found then  // an EXIF segment exists
  begin
    if SegEnd > Len then Exit;  // segment outside the file
    Base := SegStart + 10;  // TIFF header position
    if Base + 8 > SegEnd then Exit;  // segment too short
    T.Buf := Src;  // use the file bytes
    T.Base := Base;  // header position
    T.Big := Src[Base] = $4D;  // MM marks big-endian
    if U16(T, Base + 2) <> 42 then Exit;  // 42 is the TIFF version
    Big := T.Big;  // byte order
    Ofs := Base + Integer(U32(T, Base + 4));  // position of the first directory
    if (Ofs < Base) or (Ofs + 2 > SegEnd) then Exit;  // directory outside the segment
    Cnt := U16(T, Ofs);  // number of entries
    if Ofs + 2 + Cnt * 12 + 4 > SegEnd then Exit;  // directory outside the segment
    Next := U32(T, Ofs + 2 + Cnt * 12);  // offset of the next directory
    SetLength(Tiff, SegEnd - Base);  // reserve the TIFF block
    Move(Src[Base], Tiff[0], SegEnd - Base);  // copy the old TIFF data
    SetLength(Entries, Cnt);  // reserve the entries
    for I := 0 to Cnt - 1 do  // every entry
    begin
      Entries[I].Tag := U16(T, Ofs + 2 + I * 12);  // tag number
      Entries[I].Raw := nil;  // release any old array
      SetLength(Entries[I].Raw, 12);  // reserve the entry bytes
      Move(Src[Ofs + 2 + I * 12], Entries[I].Raw[0], 12);  // copy the entry
      if Entries[I].Tag = $013B then ArtistExists := GetStr(T, Ofs + 2 + I * 12) <> '';  // artist already filled
      if Entries[I].Tag = $8298 then CopyExists := GetStr(T, Ofs + 2 + I * 12) <> '';  // copyright already filled
    end;
  end
  else
  begin
    if InsertAt > Len then Exit;  // insert position outside the file
    SetLength(Tiff, 8);  // reserve a new TIFF header
    FillChar(Tiff[0], 8, 0);  // clear it
    Tiff[0] := $49;  // II marks little-endian
    Tiff[1] := $49;  // II marks little-endian
    PutU16(Tiff, 2, 42, False);  // 42 is the TIFF version
    Big := False;  // little-endian
    Next := 0;  // no next directory
  end;

  // only fill fields that are missing or empty; never overwrite existing values
  WantArtist := (Artist <> '') and (not ArtistExists);  // artist is to be added
  WantCopy := (Copyright <> '') and (not CopyExists);  // copyright is to be added
  if not (WantArtist or WantCopy) then  // nothing to add
  begin
    Result := True;  // nothing to do counts as success
    Exit;
  end;

  // drop the empty tags we are about to replace
  K := 0;  // number of entries kept
  for I := 0 to High(Entries) do  // go through the entries
    if not (((Entries[I].Tag = $013B) and WantArtist) or
            ((Entries[I].Tag = $8298) and WantCopy)) then
    begin
      Entries[K] := Entries[I];  // keep the entry
      Inc(K);  // count it
    end;
  SetLength(Entries, K);  // drop the others
  if WantArtist then AddAscii($013B, Artist);  // add the artist
  if WantCopy then AddAscii($8298, Copyright);  // add the copyright

  // IFD entries must be sorted by tag
  for I := 1 to High(Entries) do  // insertion sort by tag
  begin
    Tmp := Entries[I];  // entry to place
    J := I - 1;  // compare with the previous entries
    while (J >= 0) and (Entries[J].Tag > Tmp.Tag) do  // move larger tags up
    begin
      Entries[J + 1] := Entries[J];  // shift the entry
      Dec(J);  // previous entry
    end;
    Entries[J + 1] := Tmp;  // place the entry
  end;

  // write a new IFD0 at the end of the TIFF block; existing value offsets stay valid
  if Odd(Length(Tiff)) then Grow(Tiff, 1);  // keep the data word aligned
  Ofs := Grow(Tiff, 2 + Length(Entries) * 12 + 4);  // room for the new directory
  PutU16(Tiff, Ofs, Length(Entries), Big);  // number of entries
  for I := 0 to High(Entries) do  // every entry
    Move(Entries[I].Raw[0], Tiff[Ofs + 2 + I * 12], 12);  // copy the entry
  PutU32(Tiff, Ofs + 2 + Length(Entries) * 12, Next, Big);  // offset of the next directory
  PutU32(Tiff, 4, Ofs, Big);  // point the header to the new directory

  L := 2 + 6 + Length(Tiff);  // segment length
  if L > 65535 then Exit;          // would not fit in one APP1 segment

  if Found then
  begin
    Pre := SegStart;  // replace the old segment
    Post := SegEnd;  // end of the old segment
  end
  else
  begin
    Pre := InsertAt;  // insert at this position
    Post := InsertAt;  // nothing is removed
  end;
  SetLength(Outp, Pre + 10 + Length(Tiff) + (Len - Post));  // reserve the new file
  Move(Src[0], Outp[0], Pre);  // copy the part before the segment
  Outp[Pre] := $FF;  // marker prefix
  Outp[Pre + 1] := $E1;  // APP1 marker
  Outp[Pre + 2] := (L shr 8) and $FF;  // length high byte
  Outp[Pre + 3] := L and $FF;  // length low byte
  Outp[Pre + 4] := Ord('E');  // Exif identifier
  Outp[Pre + 5] := Ord('x');  // Exif identifier
  Outp[Pre + 6] := Ord('i');  // Exif identifier
  Outp[Pre + 7] := Ord('f');  // Exif identifier
  Outp[Pre + 8] := 0;  // zero byte
  Outp[Pre + 9] := 0;  // zero byte
  Move(Tiff[0], Outp[Pre + 10], Length(Tiff));  // copy the TIFF block
  if Len - Post > 0 then
    Move(Src[Post], Outp[Pre + 10 + Length(Tiff)], Len - Post);  // copy the rest of the file

  TmpName := FileName + '.tmp';  // temporary file name
  try
    Strm := TFileStream.Create(TmpName, fmCreate);  // create the temporary file
    try
      Strm.WriteBuffer(Outp[0], Length(Outp));  // write the new file
    finally
      Strm.Free;  // close the file
    end;
    Result := DeleteFileUTF8(FileName) and RenameFileUTF8(TmpName, FileName);  // replace the original
  except
    Result := False;  // failure
  end;
  if not Result then DeleteFileUTF8(TmpName);  // remove the temporary file
end;

end.
