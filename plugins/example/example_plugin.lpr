library example_plugin;

{$mode objfpc}{$H+}

(* Example plug-in library for Photo Downloader (plug-in interface 1).

   It shows everything a library needs:
   - pd_api_version and pd_info (required),
   - pd_token: two tokens, {Example.Name} (the original file name in capitals, without extension)
     and {Example.Site} (a site name entered in the prompt window),
   - pd_check (optional): checks the prompt value and shows a preview,
   - one text field in the prompt window and a reminder note.

   Build on Windows:  fpc -B example_plugin.lpr          -> example_plugin.dll
   Build on Linux:    fpc -B -Cg example_plugin.lpr      -> libexample_plugin.so
   Copy the file into the plugins folder (see docs/Plugin_Developer_Manual.md), start Photo Downloader,
   and switch the plug-in on in Preferences > Plug-ins. *)

uses
  SysUtils, Classes;

{ Copies S into the program's buffer (at most BufLen - 1 bytes and a closing #0); returns the full length. }
function PutText(const S: string; Buf: PAnsiChar; BufLen: Integer): Integer;
var
  N: Integer;  // N: bytes copied
begin
  Result := Length(S);  // the length the program needs
  if (Buf = nil) or (BufLen <= 0) then Exit;  // the program only asked for the length
  N := Length(S);  // bytes to copy
  if N > BufLen - 1 then N := BufLen - 1;  // keep room for the closing #0
  if N > 0 then Move(S[1], Buf^, N);  // copy the text
  Buf[N] := #0;  // close it
end;

{ The plug-in interface version this library was written for. }
function pd_api_version: Integer; cdecl;
begin
  Result := 1;  // interface 1
end;

{ Information lines: name, version, description, tokens, prompt window. }
function pd_info(Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;
begin
  Result := PutText(
    'Name=Example Plug-in' + LineEnding +
    'Version=1.0.0' + LineEnding +
    'Description=Shows how a plug-in library works: two tokens and one field.' + LineEnding +
    'Tokens=Example.Name;Example.Site' + LineEnding +
    'Title=Example plug-in' + LineEnding +
    'Note=This text is a reminder shown under the fields.' + LineEnding +
    'Field=Site|text|Site name|||upper' + LineEnding,
    Buf, BufLen);  // hand it over
end;

{ Value of one token. Context: the prompt values and details of the file (key=value lines). }
function pd_token(Token, Context: PAnsiChar; Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;
var
  L: TStringList;  // L: the context lines
  T: string;  // T: token name in lower case
begin
  Result := -1;  // no value yet
  L := TStringList.Create;  // create the list
  try
    L.Text := string(Context);  // split the context into lines
    T := LowerCase(string(Token));  // token name
    if T = 'example.name' then  // original file name in capitals, without extension
      Result := PutText(UpperCase(ChangeFileExt(L.Values['FileName'], '')), Buf, BufLen)
    else if (T = 'example.site') and (Trim(L.Values['Site']) <> '') then  // the site name from the window
      Result := PutText(UpperCase(Trim(L.Values['Site'])), Buf, BufLen);
  finally
    L.Free;  // free the list
  end;
end;

{ Checks the prompt values: the site name must not be empty. }
function pd_check(Values: PAnsiChar; Buf: PAnsiChar; BufLen: Integer): Integer; cdecl;
var
  L: TStringList;  // L: the value lines
  Site: string;  // Site: the entered site name
begin
  L := TStringList.Create;  // create the list
  try
    L.Text := string(Values);  // split into lines
    Site := UpperCase(Trim(L.Values['Site']));  // the site name
    if Site = '' then
      Result := PutText('Preview=Site: (none)' + LineEnding + 'Error=Enter a site name.' + LineEnding, Buf, BufLen)
    else
      Result := PutText('Preview=Site: ' + Site + LineEnding + 'Value.Site=' + Site + LineEnding, Buf, BufLen);
  finally
    L.Free;  // free the list
  end;
end;

exports
  pd_api_version, pd_info, pd_token, pd_check;

end.
