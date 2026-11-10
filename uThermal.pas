unit uThermal;

{$mode objfpc}{$H+}

(* Photo Downloader - thermal (infrared) file detection for the {Type} token.

  Drones with a thermal camera (for example Skydio) save thermal photos and videos next to the color
  ones, often with the same file type. The {Type} token puts them in their own folders:
    JPG, MP4 ...        color files (the extension in capitals)
    JPG-IR, MP4-IR      thermal files
    JPG-IR-R            radiometric thermal photos (they hold temperatures)
  A file counts as thermal when its XMP data names a camera source that is not a visible-light camera
  (drone-skydio:CameraSource, for example INFRARED), or when its picture or video is 640 x 512 pixels,
  the size of common thermal cameras. A thermal photo whose XMP data says PhotoKind RJPEG is radiometric.
  Only .jpg, .jpeg, .dng, .mp4 and .mov files are read; answers are cached by path and size. *)

interface

{ The folder ending for a thermal file: '' (color or not checked), '-IR' (thermal) or '-IR-R'
  (radiometric thermal photo). Path is the file to read, Size its size (cache key), Ext its extension
  with the dot. }
function ThermalSuffix(const Path: string; Size: Int64; const Ext: string): string;

implementation

uses
  Classes, SysUtils, StrUtils, LazUTF8, LazFileUtils;

const
  tkColor = 0;  // color (or not checked)
  tkThermal = 1;  // thermal camera
  tkRadiometric = 2;  // thermal photo with temperatures (RJPEG)

var
  Cache: TStringList = nil;  // path|size=kind of the files read so far

{ Reads Count bytes of a file from position Start (negative: counted from the end); '' on failure. }
function ReadPart(const Path: string; Start: Int64; Count: Integer): RawByteString;
var
  F: TFileStream;  // F: the file
  N: Int64;  // N: bytes to read
begin
  Result := '';  // nothing read yet
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);  // open read-only, others may keep it open
    try
      if Start < 0 then Start := F.Size + Start;  // counted from the end
      if Start < 0 then Start := 0;  // a small file: from its start
      N := F.Size - Start;  // bytes up to the end
      if N > Count then N := Count;  // not more than asked
      if N <= 0 then Exit;  // nothing there
      F.Position := Start;  // go to the start
      SetLength(Result, N);  // room for the bytes
      F.ReadBuffer(Result[1], N);  // read them
    finally
      F.Free;  // close the file
    end;
  except
    Result := '';  // unreadable: treated as color
  end;
end;

{ The value of a Skydio XMP property in D, as an element (<drone-skydio:Tag>value<) or an attribute
  (drone-skydio:Tag="value"), in capitals; '' when it is not there. }
function SkydioValue(const D, Tag: string): string;
var
  I, J: Integer;  // I: start of the value; J: its end
begin
  Result := '';  // not found yet
  I := Pos('<drone-skydio:' + Tag + '>', D);  // element form
  if I > 0 then
  begin
    I := I + Length('<drone-skydio:' + Tag + '>');  // first character of the value
    J := PosEx('<', D, I);  // end of the value
  end
  else
  begin
    I := Pos('drone-skydio:' + Tag + '="', D);  // attribute form
    if I = 0 then Exit;  // not there
    I := I + Length('drone-skydio:' + Tag + '="');  // first character of the value
    J := PosEx('"', D, I);  // end of the value
  end;
  if (J > I) and (J - I < 64) then Result := UpperCase(Trim(Copy(D, I, J - I)));  // for example INFRARED
end;

{ The size of the main picture of a JPEG (its first frame header outside the APP segments, so not the
  EXIF thumbnail). False when D (the start of the file) holds none. }
function JpegSize(const D: RawByteString; out W, H: Integer): Boolean;
var
  P, L: Integer;  // P: position of the marker; L: length of its segment
  M: Byte;  // M: marker type
begin
  Result := False;  // not found yet
  W := 0;
  H := 0;
  if (Length(D) < 4) or (Ord(D[1]) <> $FF) or (Ord(D[2]) <> $D8) then Exit;  // not a JPEG
  P := 3;  // first marker after SOI
  while P + 8 <= Length(D) do
  begin
    if Ord(D[P]) <> $FF then Exit;  // lost the marker chain
    M := Ord(D[P + 1]);  // marker type
    if M = $FF then begin Inc(P); Continue; end;  // fill byte
    L := Ord(D[P + 2]) shl 8 or Ord(D[P + 3]);  // segment length (with the length bytes)
    if (M in [$C0..$CF]) and not (M in [$C4, $C8, $CC]) then  // a frame header (not DHT, JPG, DAC)
    begin
      H := Ord(D[P + 5]) shl 8 or Ord(D[P + 6]);  // lines
      W := Ord(D[P + 7]) shl 8 or Ord(D[P + 8]);  // samples per line
      Exit(True);
    end;
    if (M = $DA) or (M = $D9) then Exit;  // image data or end: no frame header before it
    P := P + 2 + L;  // next marker
  end;
end;

{ Big-endian 32-bit number at position P (1-based) of S. }
function BE32(const S: RawByteString; P: Int64): Int64;
begin
  Result := Int64(Ord(S[P])) shl 24 or Ord(S[P + 1]) shl 16 or Ord(S[P + 2]) shl 8 or Ord(S[P + 3]);
end;

{ The picture size of the first video track of an MP4 / MOV file (moov > trak > tkhd). False when the
  file has none or cannot be read. }
function MovieSize(const Path: string; out W, H: Integer): Boolean;
var
  F: TFileStream;  // F: the file
  Pos0, BoxSize, FileSize: Int64;  // Pos0: start of a top-level box; BoxSize: its size; FileSize: file size
  Hdr, Moov: RawByteString;  // Hdr: a box header; Moov: the whole moov box
  T, E, K, KEnd: Int64;  // T: position of a trak; E: end of the trak; K: a box inside it; KEnd: end of that box
  Ver, Off: Integer;  // Ver: tkhd version; Off: offset of the width in the tkhd box
begin
  Result := False;  // not found yet
  W := 0;
  H := 0;
  Moov := '';
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);  // open read-only
    try
      FileSize := F.Size;  // file size
      Pos0 := 0;  // first box
      SetLength(Hdr, 16);  // room for a header
      while Pos0 + 8 <= FileSize do  // walk the top-level boxes (moov may come after the media data)
      begin
        F.Position := Pos0;
        F.ReadBuffer(Hdr[1], 16);  // size, type and a possible 64-bit size
        BoxSize := BE32(Hdr, 1);  // 32-bit size
        if BoxSize = 1 then BoxSize := BE32(Hdr, 9) shl 32 or BE32(Hdr, 13)  // 64-bit size
        else if BoxSize = 0 then BoxSize := FileSize - Pos0;  // up to the end of the file
        if BoxSize < 8 then Exit;  // broken file
        if Copy(Hdr, 5, 4) = 'moov' then
        begin
          if BoxSize > 64 * 1024 * 1024 then Exit;  // unreasonably large: give up
          SetLength(Moov, BoxSize);  // room for the box
          F.Position := Pos0;
          F.ReadBuffer(Moov[1], BoxSize);  // read it
          Break;
        end;
        Pos0 := Pos0 + BoxSize;  // next box
      end;
    finally
      F.Free;  // close the file
    end;
  except
    Exit;  // unreadable
  end;
  if Moov = '' then Exit;  // no moov box
  T := 9;  // first box inside moov
  while T + 8 <= Length(Moov) do
  begin
    E := T + BE32(Moov, T);  // end of this box
    if (E <= T) or (E > Length(Moov) + 1) then Exit;  // broken box
    if Copy(Moov, T + 4, 4) = 'trak' then  // a track: look for its tkhd
    begin
      K := T + 8;  // first box inside the track
      while K + 8 <= E do
      begin
        KEnd := K + BE32(Moov, K);  // end of this box
        if (KEnd <= K) or (KEnd > E) then Break;  // broken box
        if Copy(Moov, K + 4, 4) = 'tkhd' then
        begin
          Ver := Ord(Moov[K + 8]);  // version 0 (32-bit times) or 1 (64-bit times)
          if Ver = 1 then Off := 8 + 88 else Off := 8 + 76;  // width after times, layer, volume and matrix
          if K + Off + 8 <= KEnd then
          begin
            W := BE32(Moov, K + Off) shr 16;  // 16.16 fixed point
            H := BE32(Moov, K + Off + 4) shr 16;
            if (W > 0) and (H > 0) then Exit(True);  // a video track
          end;
          Break;  // one tkhd per track
        end;
        K := KEnd;  // next box
      end;
    end;
    T := E;  // next box
  end;
end;

{ Reads the file and decides: tkColor, tkThermal or tkRadiometric. }
function ThermalKind(const Path, Ext: string): Integer;
var
  D: RawByteString;  // D: the parts of the file that hold XMP data and the frame header
  Src: string;  // Src: the camera source named in the XMP data
  W, H: Integer;  // W, H: picture or video size
begin
  Result := tkColor;  // assume a color file
  if (Ext = '.mp4') or (Ext = '.mov') then  // a video: the size of its first video track
  begin
    if MovieSize(Path, W, H) and (W = 640) and (H = 512) then Result := tkThermal;
    Exit;
  end;
  if Ext = '.dng' then
    // a raw file may keep its XMP data near the start (after the TIFF directories) or at the end
    D := ReadPart(Path, 0, 1024 * 1024) + ReadPart(Path, -256 * 1024, 256 * 1024)
  else
    D := ReadPart(Path, 0, 256 * 1024);  // JPEG: EXIF, XMP and the frame header are near the start
  Src := SkydioValue(D, 'CameraSource');  // for example MAIN_VISIBLE or INFRARED
  if (Src <> '') and (Pos('VISIBLE', Src) = 0) then Result := tkThermal  // not the color camera
  else if (Ext <> '.dng') and JpegSize(D, W, H) and (W = 640) and (H = 512) then Result := tkThermal;  // thermal picture size
  if (Result = tkThermal) and (SkydioValue(D, 'PhotoKind') = 'RJPEG') then Result := tkRadiometric;  // with temperatures
end;

function ThermalSuffix(const Path: string; Size: Int64; const Ext: string): string;
var
  E, Key: string;  // E: extension in lower case; Key: cache key
  I, Kind: Integer;  // I: cache index; Kind: the answer
begin
  Result := '';  // color
  E := LowerCase(Ext);  // extension
  if (E <> '.jpg') and (E <> '.jpeg') and (E <> '.dng') and (E <> '.mp4') and (E <> '.mov') then Exit;  // not checked
  if (Path = '') or not FileExistsUTF8(Path) then Exit;  // an example name: no file to read
  if Cache = nil then
  begin
    Cache := TStringList.Create;  // the cache
    Cache.Sorted := True;  // fast lookup
  end;
  Key := StringReplace(Path, '=', #1, [rfReplaceAll]) + '|' + IntToStr(Size);  // the same file ('=' would split the name)
  I := Cache.IndexOfName(Key);  // seen before?
  if I >= 0 then Kind := StrToIntDef(Cache.ValueFromIndex[I], tkColor)  // known answer
  else
  begin
    Kind := ThermalKind(Path, E);  // read the file
    if Cache.Count > 100000 then Cache.Clear;  // keep the cache small
    Cache.Add(Key + '=' + IntToStr(Kind));  // remember the answer
  end;
  case Kind of
    tkThermal: Result := '-IR';  // thermal
    tkRadiometric: Result := '-IR-R';  // radiometric thermal photo
  end;
end;

finalization
  Cache.Free;  // free the cache
end.
