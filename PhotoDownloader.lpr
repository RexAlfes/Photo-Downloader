{ Program entry point: starts the single-instance check, the splash screen and the main window. }
program PhotoDownloader;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uSettings, uSingle, uSplash, uScale, uVersion, uExif, uItems, uDrives, uPhotoView, uDialogs, uViewer, uMain;

{$R *.res}

begin
  Application.Title := 'Photo Downloader';  // window and taskbar title
  Application.Scaled := True;  // scale the forms with the system DPI setting
  // single instance (the default): hand over to the copy that is already running
  if SingleInstanceWanted and ActivateRunningInstance then Halt(0);
  Application.Initialize;  // create the application object
  ShowSplash;                 // at once, before the main window is built
  Application.CreateForm(TMainForm, MainForm);  // build the main form
  Application.Run;  // run the message loop until the program closes
end.
