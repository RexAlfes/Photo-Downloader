{ Program entry point: starts the single-instance check, the splash screen and the main window. }
program PhotoDownloader;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  {$IFDEF UNIX}
  Graphics, Types,
  {$ENDIF}
  {$IFDEF LCLGTK2}
  gtk2,  // GTK 2 style settings (ListComboBoxes)
  {$ENDIF}
  uSettings, uSingle, uSplash, uScale, uVersion, uExif, uItems, uDrives, uPhotoView, uDialogs, uViewer, uMain;

{$R *.res}

{$IFDEF UNIX}
{ Linux does not take the program icon from the executable: load it from the program resource so
  that the windows and the taskbar show it. }
procedure LoadWindowIcon;
var
  Ic: TIcon;  // Ic: the icon read from the resource
  Sz: TSize;  // Sz: wanted size of the image inside the icon
begin
  Ic := TIcon.Create;  // create the icon
  try
    try
      Ic.LoadFromResourceName(HInstance, 'MAINICON');  // read all sizes from the program resource
      Sz.cx := 128;  // wanted width
      Sz.cy := 128;  // wanted height
      Ic.Current := Ic.GetBestIndexForSize(Sz);  // use the 128-pixel image
      Application.Icon.Assign(Ic);  // every window and the taskbar use it
    except
      // no icon available: the windows keep the default icon
    end;
  finally
    Ic.Free;  // free the icon
  end;
end;
{$ENDIF}

{$IFDEF LCLGTK2}
{ GTK 2 shows the list of a drop-down box as a menu placed so that the chosen entry lies over the box:
  in a long list (for example 67 counties, with an entry near the end chosen) the menu then fills the
  screen and starts with empty space above the first entry. As a list (appears-as-list) it opens below
  the box with a scroll bar, as on Windows. Set for every drop-down box of the program, with the
  highest priority so a desktop theme does not undo it. }
procedure ListComboBoxes;
begin
  gtk_rc_parse_string(
    'style "pd-combo-list" { GtkComboBox::appears-as-list = 1 }'#10 +  // lists instead of menus
    'class "GtkComboBox" style : highest "pd-combo-list"');  // for every drop-down box
end;
{$ENDIF}

begin
  Application.Title := 'Photo Downloader';  // window and taskbar title
  Application.Scaled := True;  // scale the forms with the system DPI setting
  // single instance (the default): hand over to the copy that is already running
  if SingleInstanceWanted and ActivateRunningInstance then Halt(0);
  Application.Initialize;  // create the application object
  {$IFDEF UNIX}
  LoadWindowIcon;  // window and taskbar icon on Linux
  {$ENDIF}
  {$IFDEF LCLGTK2}
  ListComboBoxes;  // drop-down lists open below their box (long lists do not fill the screen)
  {$ENDIF}
  ShowSplash;                 // at once, before the main window is built
  Application.CreateForm(TMainForm, MainForm);  // build the main form
  Application.Run;  // run the message loop until the program closes
end.
