{ Light and dark colors for the parts of the program it draws itself (the picture grid and list, the
  main window panels and the date list), View > Theme (Follow system / Light / Dark), and the dark
  window title bar on Windows 10 and 11.

  Menus, buttons and dialogs are drawn by the system and keep its look: on Windows they stay light
  (Windows has no supported dark mode for classic programs); on Linux they follow the GTK theme.
  The light palette is the program's look before themes existed. Every dark text and background pair
  has a contrast of at least 4.5:1. }
unit uTheme;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms;

type
  TThemeMode = (tmSystem, tmLight, tmDark);  // follow the system, always light, always dark

  { The colors in use. }
  TThemeColors = record
    Back: TColor;           // grid and date list background
    Text: TColor;           // text on cards and in the date list
    Normal, Selected: TColor;              // card of a new picture; selected
    Problem, SelProblem: TColor;           // card of a problem picture (name clash ...); selected
    Downloaded, SelDownloaded: TColor;     // card of a downloaded picture; selected
    Duplicate, SelDuplicate: TColor;       // card of a duplicate; selected
    Frame: TColor;          // outline of thumbnails and placeholders
    Placeholder: TColor;    // box shown while there is no thumbnail
    Header, HeaderText, HeaderLine: TColor;  // list view column headings
    Focus: TColor;          // frame of the focused card
    Panel, PanelText: TColor;  // main window panels and their labels (clDefault: the system's)
  end;

var
  Th: TThemeColors;  // the colors in use (set by SetTheme)
  ThemeDark: Boolean = False;  // the dark colors are in use

{ Picks the palette for Mode; returns True when it is dark. }
function SetTheme(Mode: TThemeMode): Boolean;
{ True when the system asks programs to be dark (Windows: the "apps" setting; Linux: a dark GTK theme). }
function SystemPrefersDark: Boolean;
{ True when the system draws its own windows dark already (a dark GTK theme on Linux; never on Windows). }
function SystemDrawsDark: Boolean;
{ Makes the title bar of Form dark or light (Windows 10 2004 and later; does nothing elsewhere). }
procedure ApplyTitleBar(Form: TCustomForm; Dark: Boolean);

implementation

uses
  {$IFDEF WINDOWS}Windows, Registry,{$ENDIF} LCLIntf;

{ The colors before themes existed. }
procedure SetLight;
begin
  Th.Back := clWindow;
  Th.Text := clBlack;
  Th.Normal := $00EBEBEF;         // RGB(239,235,235)
  Th.Selected := $00FAD7BE;       // RGB(190,215,250)
  Th.Problem := $006060FF;        // RGB(255,96,96)
  Th.SelProblem := $009664EB;     // RGB(235,100,150)
  Th.Downloaded := $00C8C8C8;     // RGB(200,200,200)
  Th.SelDownloaded := $00CDB4A0;  // RGB(160,180,205)
  Th.Duplicate := $00AAECFF;      // RGB(255,236,170): amber
  Th.SelDuplicate := $008CCDEB;   // RGB(235,205,140)
  Th.Frame := clGray;
  Th.Placeholder := $00D2D2D2;    // RGB(210,210,210)
  Th.Header := clBtnFace;
  Th.HeaderText := clBtnText;
  Th.HeaderLine := clBtnShadow;
  Th.Focus := clHighlight;
  Th.Panel := clDefault;          // the system's colors
  Th.PanelText := clDefault;
end;

{ Dark colors: light text RGB(232,232,232) on backgrounds dark enough for 4.5:1 or more. }
procedure SetDark;
begin
  Th.Back := RGBToColor(30, 30, 30);
  Th.Text := RGBToColor(232, 232, 232);
  Th.Normal := RGBToColor(50, 50, 54);
  Th.Selected := RGBToColor(38, 79, 120);        // blue
  Th.Problem := RGBToColor(130, 40, 40);         // red
  Th.SelProblem := RGBToColor(140, 45, 100);     // purple red
  Th.Downloaded := RGBToColor(82, 82, 82);       // gray, lighter than a new card
  Th.SelDownloaded := RGBToColor(60, 82, 108);   // gray blue
  Th.Duplicate := RGBToColor(104, 84, 18);       // amber
  Th.SelDuplicate := RGBToColor(118, 98, 44);    // light amber
  Th.Frame := RGBToColor(120, 120, 120);
  Th.Placeholder := RGBToColor(70, 70, 70);
  Th.Header := RGBToColor(45, 45, 45);
  Th.HeaderText := RGBToColor(225, 225, 225);
  Th.HeaderLine := RGBToColor(95, 95, 95);
  Th.Focus := RGBToColor(110, 170, 240);
  if SystemDrawsDark then  // a dark GTK theme paints the panels itself
  begin
    Th.Panel := clDefault;
    Th.PanelText := clDefault;
  end
  else
  begin
    Th.Panel := RGBToColor(40, 40, 40);
    Th.PanelText := RGBToColor(232, 232, 232);
  end;
end;

function SystemDrawsDark: Boolean;
{$IFNDEF WINDOWS}
var
  C: LongInt;  // C: the system's window color as RGB
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := False;  // Windows draws classic programs light
  {$ELSE}
  C := ColorToRGB(clWindow);
  Result := (Red(C) * 299 + Green(C) * 587 + Blue(C) * 114) div 1000 < 128;  // a dark window color
  {$ENDIF}
end;

function SystemPrefersDark: Boolean;
{$IFDEF WINDOWS}
var
  R: TRegistry;  // R: the user's registry
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := False;
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
       R.ValueExists('AppsUseLightTheme') then
      Result := R.ReadInteger('AppsUseLightTheme') = 0;  // Settings > Personalization > Colors > app mode Dark
  finally
    R.Free;
  end;
  {$ELSE}
  Result := SystemDrawsDark;
  {$ENDIF}
end;

function SetTheme(Mode: TThemeMode): Boolean;
begin
  case Mode of
    tmLight: Result := False;
    tmDark: Result := True;
  else
    Result := SystemPrefersDark;
  end;
  if Result then SetDark else SetLight;
  ThemeDark := Result;  // for windows opened later (the viewer)
end;

procedure ApplyTitleBar(Form: TCustomForm; Dark: Boolean);
{$IFDEF WINDOWS}
type
  TDwmSetWindowAttribute = function(Wnd: HWND; Attr: DWORD; Data: Pointer; Size: DWORD): HRESULT; stdcall;
const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;  // Windows 10 2004 and later
  DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;  // Windows 10 1809 to 1909
var
  Lib: HMODULE;  // Lib: dwmapi.dll
  SetAttr: TDwmSetWindowAttribute;  // SetAttr: DwmSetWindowAttribute
  V: BOOL;  // V: dark or light
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if (Form = nil) or not Form.HandleAllocated then Exit;
  Lib := LoadLibrary('dwmapi.dll');
  if Lib = 0 then Exit;
  try
    Pointer(SetAttr) := GetProcAddress(Lib, 'DwmSetWindowAttribute');
    if not Assigned(SetAttr) then Exit;
    V := Dark;
    if Failed(SetAttr(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @V, SizeOf(V))) then
      SetAttr(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @V, SizeOf(V));
    SetWindowPos(Form.Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);  // redraw the frame now
  finally
    FreeLibrary(Lib);
  end;
  {$ENDIF}
end;

initialization
  SetLight;  // until the settings are read
end.
