unit uLrPrev;

{$mode objfpc}{$H+}

{ Adobe Lightroom preview files (.lrprev).

  A .lrprev file is a series of blocks that each start with the 4 bytes 'AgHg'. The first block
  ('header') holds Lua-style text with the picture size and an id, the following blocks
  ('level_1', 'level_2', ...) each hold a complete JPEG, smallest first. The number of levels
  and their sizes vary from file to file. There is no EXIF and no original file name in the file.

  Only the largest level is used. The picture is already upright. }

interface

uses
  Classes, SysUtils, StrUtils;

const
  LrPrevExts = ';.lrprev;';  // file extensions handled by this unit

type
  TLrPrevInfo = record
    Uuid: string;       // id of the preview (the original photo is found through it in the Lightroom catalog)
    Quality: string;    // preview quality text, for example 'thumbnail'
    CropW, CropH: Integer;  // pixel size of the original picture (as cropped)
    LevelW, LevelH: Integer;  // pixel size of the largest preview level
    Levels: Integer;    // number of preview levels in the file
  end;

{ Reads the file and copies the JPEG of the largest preview level into Jpeg (position 0).
  False, with Err filled in, when the file is not a usable .lrprev file. }
function LrPrevExtract(const FileName: string; Jpeg: TMemoryStream; out Info: TLrPrevInfo;
  out Err: string): Boolean;

implementation

const
  MaxFileSize = 64 * 1024 * 1024;  // larger files are not read
  Magic = 'AgHg';  // start of every block

{ Value of 'Key = value' in the header text, '' when it is not there. Quotes are removed. }
function HeaderValue(const Txt, Key: string): string;
var
  P, Q: Integer;  // P: position in the text; Q: end of the value
begin
  Result := '';
  P := Pos(Key, Txt);
  if P = 0 then Exit;
  P := P + Length(Key);
  while (P <= Length(Txt)) and (Txt[P] in [' ', '=', #9, #13, #10, '"']) do Inc(P);  // skip ' = ' and an opening quote
  Q := P;
  while (Q <= Length(Txt)) and not (Txt[Q] in [',', '"', ' ', '}', #13, #10, #9]) do Inc(Q);
  Result := Copy(Txt, P, Q - P);
end;

{ Number from the header (whole numbers or with decimals); 0 when missing }
function HeaderInt(const Txt, Key: string): Integer;
var
  S: string;  // value text
  D: Double;  // value as a number
begin
  S := HeaderValue(Txt, Key);
  D := 0;
  if (S <> '') and TryStrToFloat(S, D, DefaultFormatSettings) then Result := Round(D) else Result := 0;
end;

{ Finds the text Sub in the byte buffer Buf (length Len) from position From (0-based); -1 when absent. }
function FindBytes(const Buf: TBytes; Len, From: Integer; const Sub: string): Integer;
var
  I, J, N: Integer;  // I: position; J: position in Sub; N: length of Sub
  Ok: Boolean;  // True while all bytes match
begin
  Result := -1;
  N := Length(Sub);
  I := From;
  while I <= Len - N do
  begin
    if Buf[I] = Ord(Sub[1]) then
    begin
      Ok := True;
      for J := 2 to N do
        if Buf[I + J - 1] <> Ord(Sub[J]) then
        begin
          Ok := False;
          Break;
        end;
      if Ok then Exit(I);
    end;
    Inc(I);
  end;
end;

function LrPrevExtract(const FileName: string; Jpeg: TMemoryStream; out Info: TLrPrevInfo;
  out Err: string): Boolean;
var
  FS: TFileStream;  // the file
  Buf: TBytes;  // whole file
  Len, I, K, HdrEnd, N, Best, BestArea, Area, Idx, StartPos, BlockEnd, EndPos: Integer;
  Txt: string;  // header text
  Starts, Ends, Blocks: array of Integer;  // start of every JPEG, end of its block, start of every block
  LvlW, LvlH: array of Integer;  // sizes of the levels in the header, in order
  P, Q: Integer;  // search positions in the header text
begin
  Result := False;
  Err := '';
  Info.Uuid := '';
  Info.Quality := '';
  Info.CropW := 0;
  Info.CropH := 0;
  Info.LevelW := 0;
  Info.LevelH := 0;
  Info.Levels := 0;
  Jpeg.Clear;
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Len := FS.Size;
    if (Len < 64) or (Len > MaxFileSize) then
    begin
      Err := 'not a usable .lrprev file (size ' + IntToStr(Len) + ' bytes)';
      Exit;
    end;
    SetLength(Buf, Len);
    FS.ReadBuffer(Buf[0], Len);
  finally
    FS.Free;
  end;
  if FindBytes(Buf, Len, 0, Magic) <> 0 then
  begin
    Err := 'not a .lrprev file (does not start with AgHg)';
    Exit;
  end;
  // blocks: every block starts with AgHg; block 0 is the header text, the others hold one JPEG each
  SetLength(Starts, 0);
  SetLength(Blocks, 0);
  I := 0;
  while I >= 0 do
  begin
    SetLength(Blocks, Length(Blocks) + 1);
    Blocks[High(Blocks)] := I;
    I := FindBytes(Buf, Len, I + 4, Magic);
  end;
  if Length(Blocks) < 2 then
  begin
    Err := 'no preview picture found';
    Exit;
  end;
  // header text of block 0, from 'pyramid'
  HdrEnd := Blocks[1];
  I := FindBytes(Buf, HdrEnd, 0, 'pyramid');
  if I < 0 then
  begin
    Err := 'no header text found';
    Exit;
  end;
  N := HdrEnd - I;
  if N > 4000 then N := 4000;  // the header is short
  SetString(Txt, PChar(@Buf[I]), N);
  Info.Uuid := HeaderValue(Txt, 'uuid');
  Info.Quality := HeaderValue(Txt, 'quality');
  Info.CropW := HeaderInt(Txt, 'croppedWidth');
  Info.CropH := HeaderInt(Txt, 'croppedHeight');
  // sizes of the levels, in the order they are listed: { height = 43, width = 64, }
  SetLength(LvlW, 0);
  SetLength(LvlH, 0);
  P := Pos('levels', Txt);
  if P > 0 then
  begin
    Q := P;
    repeat
      Q := PosEx('height', Txt, Q);
      if Q = 0 then Break;
      SetLength(LvlH, Length(LvlH) + 1);
      SetLength(LvlW, Length(LvlW) + 1);
      LvlH[High(LvlH)] := HeaderInt(Copy(Txt, Q, 40), 'height');
      LvlW[High(LvlW)] := HeaderInt(Copy(Txt, Q, 60), 'width');
      Q := Q + 6;
    until False;
  end;
  // start of the JPEG (FF D8 FF) inside each level block
  for K := 1 to High(Blocks) do
  begin
    if K < High(Blocks) then BlockEnd := Blocks[K + 1] else BlockEnd := Len;
    I := FindBytes(Buf, BlockEnd, Blocks[K] + 4, #$FF#$D8#$FF);
    if I >= 0 then
    begin
      SetLength(Starts, Length(Starts) + 1);
      SetLength(Ends, Length(Ends) + 1);
      Starts[High(Starts)] := I;
      Ends[High(Ends)] := BlockEnd;
    end;
  end;
  Info.Levels := Length(Starts);
  // the largest level listed in the header (by area); the last JPEG when the lists do not agree
  Idx := High(Starts);
  if Length(LvlW) = Length(Starts) then
  begin
    Best := 0;
    BestArea := -1;
    for I := 0 to High(LvlW) do
    begin
      Area := LvlW[I] * LvlH[I];
      if Area > BestArea then
      begin
        BestArea := Area;
        Best := I;
      end;
    end;
    Idx := Best;
  end;
  if Idx < 0 then
  begin
    Err := 'no preview picture found';
    Exit;
  end;
  if (Idx <= High(LvlW)) and (Length(LvlW) = Length(Starts)) then
  begin
    Info.LevelW := LvlW[Idx];
    Info.LevelH := LvlH[Idx];
  end;
  StartPos := Starts[Idx];
  // the picture ends at its last FF D9 before the next block (or the end of the file)
  EndPos := -1;
  I := Ends[Idx] - 2;
  while I > StartPos do
  begin
    if (Buf[I] = $FF) and (Buf[I + 1] = $D9) then
    begin
      EndPos := I + 2;
      Break;
    end;
    Dec(I);
  end;
  if EndPos < 0 then
  begin
    Err := 'the preview picture is incomplete';
    Exit;
  end;
  Jpeg.WriteBuffer(Buf[StartPos], EndPos - StartPos);
  Jpeg.Position := 0;
  Result := True;
end;

end.
