unit uIccEmbed;

{$mode objfpc}{$H+}

{ Embeds an ICC color profile into a JPEG file without decoding or recompressing the picture.

  A JPEG carries its color profile in APP2 segments that start with "ICC_PROFILE"#0, a sequence number
  and the number of segments; one segment holds at most 65519 bytes of the profile, so a large profile
  is split into several segments. The new segments are put after the leading APP0 (JFIF) and APP1
  (EXIF, XMP) segments; everything else, from the other header segments to the compressed picture
  data, is copied byte for byte. The file is written to a temporary file first and then replaces the
  original, so a failure never leaves a half-written picture behind.

  Used by the built-in plug-in "JPEG auto profile" (one profile per camera model). }

interface

uses
  Classes, SysUtils;

{ True when the file looks like an ICC profile (at least 132 bytes, signature "acsp" at offset 36). }
function IsIccProfile(const FileName: string): Boolean;
{ True when the JPEG already holds an ICC profile (an APP2 ICC_PROFILE segment). }
function JpegHasIccProfile(const JpegFile: string): Boolean;
{ Puts the profile from IccFile into JpegFile. Replace: an existing profile is replaced; otherwise a
  JPEG that already has one is left alone. Returns 1 = embedded, 0 = skipped (the JPEG already has a
  profile), -1 = failed (Err tells why). }
function EmbedIccProfile(const JpegFile, IccFile: string; Replace: Boolean; out Err: string): Integer;

implementation

uses
  LazFileUtils;

const
  IccTag = 'ICC_PROFILE'#0;  // start of an ICC APP2 segment
  MaxChunk = 65535 - 2 - 14;  // profile bytes per segment: segment length minus its length field and header

{ Reads a whole file into a byte string ('' when it cannot be read). }
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

{ True when the segment at position P (its FF marker) is an APP2 ICC_PROFILE segment. }
function IsIccSegment(const D: RawByteString; P: Integer): Boolean;
begin
  Result := (Ord(D[P + 1]) = $E2) and (P + 4 + Length(IccTag) - 1 <= Length(D)) and
    (Copy(D, P + 4, Length(IccTag)) = IccTag);  // APP2 with the ICC tag
end;

function IsIccProfile(const FileName: string): Boolean;
var
  D: RawByteString;  // D: the file
begin
  Result := False;  // assume not
  try
    D := ReadAll(FileName);  // read it
  except
    Exit;  // not readable
  end;
  Result := (Length(D) >= 132) and (Copy(D, 37, 4) = 'acsp');  // signature at offset 36
end;

{ Walks the header segments of a JPEG: returns the position of the start-of-scan segment (0 for a
  broken file) and, through IccFound, whether an ICC segment exists. }
function ScanHeader(const D: RawByteString; out IccFound: Boolean): Integer;
var
  P, M: Integer;  // P: position of the current FF marker; M: marker code
begin
  Result := 0;  // not found yet
  IccFound := False;  // no profile seen yet
  if (Length(D) < 4) or (D[1] <> #$FF) or (D[2] <> #$D8) then Exit;  // not a JPEG
  P := 3;  // first segment
  while P + 3 <= Length(D) do
  begin
    if D[P] <> #$FF then Exit;  // lost the segment chain
    M := Ord(D[P + 1]);  // marker
    if M = $FF then begin Inc(P); Continue; end;  // fill byte
    if M = $DA then Exit(P);  // start of scan: the picture data follows
    if IsIccSegment(D, P) then IccFound := True;  // a profile is there
    P := P + 2 + BE16(D, P + 2);  // next segment
  end;
end;

function JpegHasIccProfile(const JpegFile: string): Boolean;
begin
  try
    ScanHeader(ReadAll(JpegFile), Result);  // look at the header segments
  except
    Result := False;  // not readable
  end;
end;

function EmbedIccProfile(const JpegFile, IccFile: string; Replace: Boolean; out Err: string): Integer;
var
  D, Icc, Outp, Seg, Tmp: RawByteString;  // D: the JPEG; Icc: the profile; Outp: the new file; Seg: one segment
  P, M, SosPos, Count, I, N, InsertAt: Integer;  // positions, marker, segment count, sizes
  HasIcc: Boolean;  // HasIcc: the JPEG already has a profile
  F: TFileStream;  // F: the new file
begin
  Result := -1;  // assume failure
  Err := '';  // no error yet
  try
    D := ReadAll(JpegFile);  // the picture
    Icc := ReadAll(IccFile);  // the profile
  except
    on E: Exception do begin Err := 'cannot read: ' + E.Message; Exit; end;
  end;
  if (Length(Icc) < 132) or (Copy(Icc, 37, 4) <> 'acsp') then begin Err := 'not an ICC profile: ' + IccFile; Exit; end;
  SosPos := ScanHeader(D, HasIcc);  // where the picture data starts
  if SosPos = 0 then begin Err := 'not a JPEG file, or its header is damaged'; Exit; end;
  if HasIcc and not Replace then Exit(0);  // keep the camera's own profile
  // the new ICC segments
  Count := (Length(Icc) + MaxChunk - 1) div MaxChunk;  // segments needed
  if Count > 255 then begin Err := 'the profile is too large'; Exit; end;
  Seg := '';  // nothing yet
  for I := 0 to Count - 1 do
  begin
    N := Length(Icc) - I * MaxChunk;  // bytes left
    if N > MaxChunk then N := MaxChunk;  // at most one segment's worth
    Seg := Seg + #$FF#$E2 + Chr((N + 16) shr 8) + Chr((N + 16) and $FF) +  // marker and length
      IccTag + Chr(I + 1) + Chr(Count) + Copy(Icc, I * MaxChunk + 1, N);  // tag, sequence, count, data
  end;
  // copy the header: leading APP0/APP1 segments, then the profile, then the rest (old profile left out)
  Outp := #$FF#$D8;  // start of image
  InsertAt := 0;  // profile not placed yet
  P := 3;  // first segment
  while P < SosPos do
  begin
    M := Ord(D[P + 1]);  // marker
    if M = $FF then begin Inc(P); Continue; end;  // fill byte: dropped
    N := 2 + BE16(D, P + 2);  // segment size with its marker
    if (InsertAt = 0) and (M <> $E0) and (M <> $E1) then  // first segment after APP0/APP1
    begin
      Outp := Outp + Seg;  // the profile goes here
      InsertAt := Length(Outp);  // placed
    end;
    if not IsIccSegment(D, P) then Outp := Outp + Copy(D, P, N);  // keep every segment except an old profile
    P := P + N;  // next segment
  end;
  if InsertAt = 0 then Outp := Outp + Seg;  // only APP0/APP1 before the picture data
  Outp := Outp + Copy(D, SosPos, MaxInt);  // the picture data, unchanged
  // write a new file, then put it in place of the old one
  Tmp := JpegFile + '.icc.tmp';  // temporary name
  try
    F := TFileStream.Create(Tmp, fmCreate);  // the new file
    try
      F.WriteBuffer(Outp[1], Length(Outp));  // write it
    finally
      F.Free;  // close it
    end;
    // old file aside first, so it can be put back if the new one cannot take its place
    if FileExistsUTF8(JpegFile + '.icc.old') then DeleteFileUTF8(JpegFile + '.icc.old');  // a left-over
    if not RenameFileUTF8(JpegFile, JpegFile + '.icc.old') then raise Exception.Create('cannot replace the file');
    if not RenameFileUTF8(Tmp, JpegFile) then  // put the new one in place
    begin
      RenameFileUTF8(JpegFile + '.icc.old', JpegFile);  // put the old one back
      raise Exception.Create('cannot rename ' + Tmp);
    end;
    DeleteFileUTF8(JpegFile + '.icc.old');  // the old file is no longer needed
  except
    on E: Exception do
    begin
      if FileExistsUTF8(Tmp) then DeleteFileUTF8(Tmp);  // no left-over
      Err := E.Message;  // why
      Exit;
    end;
  end;
  Result := 1;  // embedded
end;

end.
