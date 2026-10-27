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
  MutexName = 'PhotoDownloader.SingleInstance';  // name of the system-wide mutex that marks a running copy
  WindowMark = 'PhotoDownloader.MainWindow';  // property name stored on the main window so it can be found
  EnumTag = 1;                  // passed through EnumWindows and checked in EnumProc

var
  GMutex: THandle = 0;  // mutex handle (kept open for the life of the program)
  GFound: HWND = 0;  // window handle of the running copy, filled in by EnumProc

{ Callback for EnumWindows: stops at the window that carries our mark. }
function EnumProc(Wnd: HWND; LParam: LPARAM): WINBOOL; stdcall;
begin
  if (LParam = EnumTag) and (GetPropA(Wnd, WindowMark) <> 0) then  // is this window marked as the main window of the program?
  begin
    GFound := Wnd;  // remember the window
    Result := False;          // stop enumerating
  end
  else
    Result := True;  // keep enumerating
end;

{ Windows version: creates the mutex; if it already exists, brings the other copy's window to the front. }
function ActivateRunningInstance: Boolean;
begin
  Result := False;  // assume we are the first copy
  GMutex := CreateMutexA(nil, False, MutexName);  // create or open the named mutex
  if GMutex = 0 then Exit;  // no mutex available: just run
  if GetLastError <> ERROR_ALREADY_EXISTS then Exit;     // we are the first copy
  GFound := 0;  // forget any earlier search result
  EnumWindows(@EnumProc, EnumTag);  // look for the marked window of the other copy
  if GFound <> 0 then  // found the other copy's window
  begin
    if IsIconic(GFound) then ShowWindow(GFound, SW_RESTORE);  // restore it if minimized
    SetForegroundWindow(GFound);  // bring it to the front
    Result := True;  // tell the caller to quit
  end;
end;

{ Windows version: marks the main window so later copies can find it. }
procedure RegisterMainWindow(Wnd: PtrUInt);
begin
  if Wnd <> 0 then SetPropA(HWND(Wnd), WindowMark, 1);  // store the mark as a window property
end;
{$ELSE}
function ActivateRunningInstance: Boolean;
begin
  Result := False;            // single instance is only implemented for Windows
end;

procedure RegisterMainWindow(Wnd: PtrUInt);  // Other systems: nothing to register.
begin
  if Wnd = 0 then Exit;  // nothing to do without a window
end;
{$ENDIF}

end.
