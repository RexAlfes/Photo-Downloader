unit uSingle;

{$mode objfpc}{$H+}

{ Single instance support (Windows). The first copy of the program owns a named mutex
  and marks its main window; a later copy finds the mutex, brings that window to the
  front and exits. No threads or pipes are used, so nothing can keep the process alive.
  If the mutex exists but no window is found (a stuck copy), the new copy just starts. }

interface

{ True if another copy is already running and was brought to the front. }
function ActivateRunningInstance: Boolean;
{ Marks this copy's main window so that later copies can find it. }
procedure RegisterMainWindow(Wnd: PtrUInt);

implementation

{$IFDEF WINDOWS}
uses
  Windows;

const
  MutexName = 'PhotoDownloader.SingleInstance';
  WindowMark = 'PhotoDownloader.MainWindow';

var
  GMutex: THandle = 0;
  GFound: HWND = 0;

function EnumProc(Wnd: HWND; LParam: LPARAM): WINBOOL; stdcall;
begin
  if GetPropA(Wnd, WindowMark) <> 0 then
  begin
    GFound := Wnd;
    Result := False;          // stop enumerating
  end
  else
    Result := True;
end;

function ActivateRunningInstance: Boolean;
begin
  Result := False;
  GMutex := CreateMutexA(nil, False, MutexName);
  if GMutex = 0 then Exit;
  if GetLastError <> ERROR_ALREADY_EXISTS then Exit;     // we are the first copy
  GFound := 0;
  EnumWindows(@EnumProc, 0);
  if GFound <> 0 then
  begin
    if IsIconic(GFound) then ShowWindow(GFound, SW_RESTORE);
    SetForegroundWindow(GFound);
    Result := True;
  end;
end;

procedure RegisterMainWindow(Wnd: PtrUInt);
begin
  if Wnd <> 0 then SetPropA(HWND(Wnd), WindowMark, 1);
end;
{$ELSE}
function ActivateRunningInstance: Boolean;
begin
  Result := False;            // single instance is only implemented for Windows
end;

procedure RegisterMainWindow(Wnd: PtrUInt);
begin
  if Wnd = 0 then Exit;
end;
{$ENDIF}

end.
