{ Light and dark colors for the parts of the program it draws itself (the picture grid and list, the
  main window panels and the date list), View > Theme (Follow system / Light / Dark), and the dark
  window title bar on Windows 10 and 11.

  Menus, buttons and dialogs are drawn by the system. On Linux they follow the GTK theme. On Windows,
  which has no supported dark mode for classic programs, StartTheme switches them dark at program start
  with the MetaDarkStyle package (third_party/metadarkstyle, LGPL with linking exception); that can only
  be chosen before the first window exists, so a change of theme reaches them at the next start.
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
  StartDark: Boolean = False;  // menus, buttons and dialogs are dark in this run (chosen at program start)

{ Program start, before Application.Initialize: reads View > Theme from the settings file and, when it
  means dark, makes menus, buttons and dialogs dark for this run (Windows; see the unit header). }
procedure StartTheme(const SettingsFile: string);
{ Program start, right after Application.Initialize. Linux (GTK 2): when View > Theme differs from the
  desktop's light or dark, uses the dark or light version of the desktop's GTK theme for this program
  (Mint-Y and Mint-Y-Dark, for example), so menus, buttons and dialogs follow. Windows: nothing. }
procedure StartThemeAfterInit;
{ Text colors for dialog windows: red for errors, gray for quiet notes, blue for links; lighter shades
  when the dialogs are dark (StartDark), each at least 4.5:1 on its background. }
function DlgErrorText: TColor;
function DlgQuietText: TColor;
function DlgLinkText: TColor;
{ Picks the palette for Mode; returns True when it is dark. }
function SetTheme(Mode: TThemeMode): Boolean;
{ True when Mode means dark now (without changing the colors in use). }
function ModeIsDark(Mode: TThemeMode): Boolean;
{ True when the system asks programs to be dark (Windows: the "apps" setting; Linux: a dark GTK theme). }
function SystemPrefersDark: Boolean;
{ True when the system draws its own windows dark already (a dark GTK theme on Linux; never on Windows). }
function SystemDrawsDark: Boolean;
{ Makes the title bar of Form dark or light: Windows 10 2004 and later through DWM; Linux (GTK 2) through the
  _GTK_THEME_VARIANT hint, which GNOME-style window managers (Cinnamon, GNOME, MATE with Marco) follow when
  the window theme has a dark version. }
procedure ApplyTitleBar(Form: TCustomForm; Dark: Boolean);

implementation

uses
  {$IFDEF WINDOWS}Windows, Registry, uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes,{$ENDIF}
  {$IFDEF LCLGTK2}glib2, gdk2, gtk2, Gtk2Def, Gtk2Proc,{$ENDIF}  // GTK 2: title bar hint, GTK theme, LCL's style cache
  LCLIntf, IniFiles;

{$IFNDEF WINDOWS}
var
  StartMode: Integer = 0;  // View > Theme read at program start (0 system, 1 light, 2 dark)
  GtkOverride: Boolean = False;  // Linux: another version of the desktop's GTK theme is in use
  GtkSysDark: Boolean = False;  // Linux: the desktop's own GTK theme is dark (seen before any change)
{$ENDIF}

{ The colors before themes existed. }
procedure SetLight;
begin
  Th.Back := clWindow;
  if StartDark then Th.Back := clWhite;  // the system colors are dark for this run: real light colors
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
  if StartDark then  // the system colors are dark for this run: real light colors until the next start
  begin
    Th.Header := RGBToColor(240, 240, 240);
    Th.HeaderText := clBlack;
    Th.HeaderLine := RGBToColor(160, 160, 160);
    Th.Focus := RGBToColor(0, 120, 215);
  end;
  Th.Panel := clDefault;          // the system's colors
  Th.PanelText := clDefault;
  if StartDark then  // the system colors are dark for this run
  begin
    Th.Panel := RGBToColor(240, 240, 240);
    Th.PanelText := clBlack;
  end;
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
  // a dark desktop theme paints the panels itself; a theme this program switched to at start does not reach
  // the system colors the program read while starting, so the panels get the dark colors directly then
  if SystemDrawsDark {$IFNDEF WINDOWS}and not GtkOverride{$ENDIF} then
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
  Result := StartDark;  // dark only when MetaDarkStyle made it so at start
  {$ELSE}
  if GtkOverride then Exit(StartDark);  // the theme version chosen at start
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
  if GtkOverride then Result := GtkSysDark  // the desktop's own theme, not the version this program uses
  else Result := SystemDrawsDark;
  {$ENDIF}
end;

function ModeIsDark(Mode: TThemeMode): Boolean;
begin
  case Mode of
    tmLight: Result := False;
    tmDark: Result := True;
  else
    Result := SystemPrefersDark;
  end;
end;

function SetTheme(Mode: TThemeMode): Boolean;
begin
  Result := ModeIsDark(Mode);
  if Result then SetDark else SetLight;
  ThemeDark := Result;  // for windows opened later (the viewer)
end;

procedure StartTheme(const SettingsFile: string);
var
  Ini: TIniFile;  // Ini: the settings file
  Mode: Integer;  // Mode: View > Theme (0 system, 1 light, 2 dark)
begin
  Mode := 0;  // follow the system when the file has nothing
  try
    Ini := TIniFile.Create(SettingsFile);
    try
      Mode := Ini.ReadInteger('View', 'Theme', 0);
    finally
      Ini.Free;
    end;
  except
    Mode := 0;  // unreadable: follow the system
  end;
  {$IFNDEF WINDOWS}
  StartMode := Mode;  // for StartThemeAfterInit
  {$ENDIF}
  {$IFDEF WINDOWS}
  StartDark := (Mode = 2) or ((Mode <> 1) and SystemPrefersDark);
  if StartDark then
  begin
    PreferredAppMode := pamForceDark;  // dark menus, buttons and dialogs for this run
    ApplyMetaDarkStyle(DefaultDark);  // before the first window exists
  end;  // light: nothing is changed, the program looks as without the package
  {$ENDIF}
end;

{$IFDEF LCLGTK2}
{ The name of the GTK theme in use (for example Mint-Y). }
function GtkThemeName: string;
var
  P: Pgchar;  // P: the name, allocated by GTK
begin
  Result := '';
  P := nil;
  g_object_get(gtk_settings_get_default, 'gtk-theme-name', [@P, nil]);
  if P <> nil then
  begin
    Result := StrPas(P);
    g_free(P);
  end;
end;

{ True when a GTK theme with GTK 2 files is installed under this name. }
function GtkThemeExists(const Name: string): Boolean;
var
  Home: string;  // Home: the user's folder
begin
  Home := IncludeTrailingPathDelimiter(GetUserDir);
  Result := (Name <> '') and (FileExists('/usr/share/themes/' + Name + '/gtk-2.0/gtkrc') or
    FileExists(Home + '.themes/' + Name + '/gtk-2.0/gtkrc') or
    FileExists(Home + '.local/share/themes/' + Name + '/gtk-2.0/gtkrc'));
end;

{ The dark (Dark = True) or light version of the GTK theme Name, or '' when none is installed. }
function GtkThemeVariant(const Name: string; Dark: Boolean): string;
var
  C: array[0..6] of string;  // C: names to try, best first
  Base: string;  // Base: Name without a dark ending
  I: Integer;  // I: loop counter
begin
  Result := '';
  if Dark then
  begin
    C[0] := Name + '-Dark';
    C[1] := Name + '-dark';
    C[2] := StringReplace(Name, 'Light', 'Dark', []);
    C[3] := StringReplace(Name, 'light', 'dark', []);
    C[4] := 'Mint-Y-Dark';  // Linux Mint
    C[5] := 'Adwaita-dark';  // GNOME
    C[6] := 'Mint-L-Dark';
  end
  else
  begin
    Base := Name;
    if SameText(Copy(Base, Length(Base) - 4, 5), '-Dark') then Delete(Base, Length(Base) - 4, 5);
    C[0] := Base;
    C[1] := StringReplace(Name, 'Dark', 'Light', []);
    C[2] := StringReplace(Name, 'dark', 'light', []);
    C[3] := StringReplace(Name, 'Dark', '', []);
    C[4] := 'Mint-Y';  // Linux Mint
    C[5] := 'Adwaita';  // GNOME
    C[6] := 'Mint-L';
  end;
  for I := 0 to High(C) do
    if (C[I] <> Name) and GtkThemeExists(C[I]) then Exit(C[I]);
end;
{$ENDIF}

procedure StartThemeAfterInit;
{$IFDEF LCLGTK2}
var
  Want: Boolean;  // Want: dark wanted
  V: string;  // V: the theme version to use
{$ENDIF}
begin
  {$IFDEF LCLGTK2}
  GtkSysDark := SystemDrawsDark or (Pos('dark', LowerCase(GtkThemeName)) > 0);  // the desktop's own theme
  StartDark := GtkSysDark;
  Want := (StartMode = 2) or ((StartMode = 0) and GtkSysDark);
  if Want = GtkSysDark then Exit;  // the desktop already matches
  V := GtkThemeVariant(GtkThemeName, Want);
  if V = '' then Exit;  // no such version installed: the desktop's theme stays
  gtk_settings_set_string_property(gtk_settings_get_default, 'gtk-theme-name', PChar(V), 'PhotoDownloader');  // this program only
  // LCL keeps the GTK styles of the old theme (read in Application.Initialize); GTK frees them when it loads the
  // new one, so drawing text with a system color then crashed (Access Violation in GetSysGCValues). Let GTK load
  // the new theme, drop LCL's cached styles and read them again, which also rebuilds the system colors.
  while gtk_events_pending <> 0 do gtk_main_iteration_do(False);
  ReleaseAllStyles;
  GetStyle(lgsButton);  // the same styles LCL reads at start-up (TGtk2WidgetSet.InitSystemColors)
  GetStyle(lgsWindow);
  GetStyle(lgsMenuBar);
  GetStyle(lgsMenuitem);
  GetStyle(lgsVerticalScrollbar);
  GetStyle(lgsTooltip);
  GtkOverride := True;
  StartDark := Want;
  {$ELSE}
  {$IFNDEF WINDOWS}
  StartDark := SystemDrawsDark;  // other Linux widgetsets: the desktop decides
  {$ENDIF}
  {$ENDIF}
end;

function DlgErrorText: TColor;
begin
  if StartDark then Result := RGBToColor(255, 128, 128) else Result := RGBToColor(160, 0, 0);
end;

function DlgQuietText: TColor;
begin
  if StartDark then Result := RGBToColor(176, 176, 176) else Result := RGBToColor(96, 96, 96);
end;

function DlgLinkText: TColor;
begin
  if StartDark then Result := RGBToColor(110, 170, 255) else Result := clBlue;
end;

{$IFDEF LCLGTK2}
{ Sets the window manager's hint for a dark or light title bar on a GTK window. }
procedure SetTitleVariant(Win: PGdkWindow; Dark: Boolean);
const
  Variant: array[Boolean] of string = ('light', 'dark');  // value of the hint
begin
  if Win = nil then Exit;
  gdk_property_change(Win, gdk_atom_intern('_GTK_THEME_VARIANT', False),
    gdk_atom_intern('UTF8_STRING', False), 8, GDK_PROP_MODE_REPLACE,
    Pguchar(PChar(Variant[Dark])), Length(Variant[Dark]));
end;

{ GTK "realize" signal: the window has just been created and is not on the screen yet, the moment the
  window manager (Muffin in Cinnamon) still reads the hint; later changes it ignores. }
procedure TitleBarRealized(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  SetTitleVariant(Widget^.window, ThemeDark);  // the theme in use
end;
{$ENDIF}

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
{$IFDEF LCLGTK2}
var
  W: PGtkWidget;  // W: the form's GTK window
{$ENDIF}
begin
  {$IFDEF LCLGTK2}
  if (Form = nil) or not Form.HandleAllocated then Exit;
  W := PGtkWidget(Form.Handle);
  // the window manager reads the hint when the window first appears: set it from GTK's "realize" signal,
  // right before that (never realize the window early here: that made GTK replace it and could crash)
  if g_object_get_data(PGObject(W), 'pd-title-bar') = nil then
  begin
    g_signal_connect_after(W, 'realize', TGCallback(@TitleBarRealized), nil);
    g_object_set_data(PGObject(W), 'pd-title-bar', Pointer(1));  // connected once per window
  end;
  SetTitleVariant(W^.window, Dark);  // a window already on the screen (followed by window managers that watch it)
  {$ENDIF}
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
