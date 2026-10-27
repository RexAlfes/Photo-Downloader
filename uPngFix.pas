unit uPngFix;

{$mode objfpc}{$H+}
{$POINTERMATH ON}

{ Some programs and instruments (oscilloscope screenshots, for example) write PNG files whose
  chunk checksums (CRC) are wrong. Windows ignores that; the standard FPC reader refuses
  the file. RepairPngCrc rewrites every chunk checksum in a copy of the file held in memory,
  so the normal reader can then decode it. }

interface

uses
  Classes;

{ M holds the whole file. True if it looks like a PNG and at least one checksum was changed. }
function RepairPngCrc(M: TMemoryStream): Boolean;
{ Reads a whole file into M (position 0). }
procedure LoadFileToMemory(const FileName: string; M: TMemoryStream);

implementation

uses
  SysUtils;

var
  CrcTable: array[0..255] of Cardinal;  // CRC-32 lookup table, one entry per byte value
  CrcReady: Boolean = False;  // True once the table has been filled

{ Fills the CRC-32 lookup table (polynomial $EDB88320). }
procedure MakeCrcTable;
var
  N, K: Integer;  // N: byte value, K: bit counter
  C: Cardinal;  // C: running CRC value
begin
  for N := 0 to 255 do  // every possible byte value
  begin
    C := Cardinal(N);  // start with the byte itself
    for K := 0 to 7 do  // process its 8 bits
      if (C and 1) <> 0 then C := $EDB88320 xor (C shr 1) else C := C shr 1;  // shift right, XOR in the polynomial when the low bit is set
    CrcTable[N] := C;  // store the finished entry
  end;
  CrcReady := True;  // table is ready
end;

{ Reads four bytes as a big-endian unsigned number. }
function BE32(P: PByte): Cardinal;
begin
  Result := (Cardinal(P[0]) shl 24) or (Cardinal(P[1]) shl 16) or (Cardinal(P[2]) shl 8) or P[3];  // first byte is the most significant
end;

{ Writes a number as four big-endian bytes. }
procedure PutBE32(P: PByte; V: Cardinal);
begin
  P[0] := (V shr 24) and $FF;  // highest byte
  P[1] := (V shr 16) and $FF;  // second byte
  P[2] := (V shr 8) and $FF;  // third byte
  P[3] := V and $FF;  // lowest byte
end;

{ Recomputes every chunk checksum of a PNG held in memory; True if any checksum was changed. }
function RepairPngCrc(M: TMemoryStream): Boolean;
const
  Sig: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);  // the 8-byte PNG file signature
var
  B: PByte;  // B: pointer to the file bytes
  Total, Pos, Len, I: Int64;  // Total: file size, Pos: start of the current chunk, Len: its data length, I: loop index
  C, Old: Cardinal;  // C: new checksum, Old: checksum stored in the file
begin
  Result := False;  // nothing changed yet
  B := PByte(M.Memory);  // point at the stream's memory
  Total := M.Size;  // file size in bytes
  if Total < 20 then Exit;  // too small to be a PNG
  for I := 0 to 7 do  // compare the signature bytes
    if B[I] <> Sig[I] then Exit;  // not a PNG: leave it alone
  if not CrcReady then MakeCrcTable;  // build the table on first use
  Pos := 8;  // the first chunk follows the signature
  while Pos + 12 <= Total do  // while a whole chunk header and checksum fit
  begin
    Len := BE32(B + Pos);  // chunk data length (big-endian)
    if Pos + 12 + Len > Total then Break;           // damaged or cut off: leave the rest alone
    C := $FFFFFFFF;  // CRC-32 starts with all bits set
    for I := Pos + 4 to Pos + 7 + Len do            // chunk type and data
      C := CrcTable[(C xor B[I]) and $FF] xor (C shr 8);  // add each byte of chunk type and data
    C := C xor $FFFFFFFF;  // final inversion gives the CRC-32
    Old := BE32(B + Pos + 8 + Len);  // checksum currently stored after the data
    if Old <> C then  // different from the correct value?
    begin
      PutBE32(B + Pos + 8 + Len, C);  // overwrite with the correct checksum
      Result := True;  // report that the file was repaired
    end;
    Inc(Pos, 12 + Len);  // move to the next chunk (length, type, data, checksum)
  end;
end;

{ Reads a whole file into a memory stream and rewinds it. }
procedure LoadFileToMemory(const FileName: string; M: TMemoryStream);
var
  F: TFileStream;  // F: the open file
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open for reading, allowing other programs to use the file
  try
    M.Clear;  // empty the target stream
    M.CopyFrom(F, 0);  // copy the entire file
    M.Position := 0;  // rewind for the reader
  finally
    F.Free;  // close the file
  end;
end;

end.
