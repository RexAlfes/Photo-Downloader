program PhotoDownloader;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uSettings, uSingle, uScale, uVersion, uExif, uItems, uDrives, uPhotoView, uDialogs, uViewer, uMain;

{$R *.res}

begin
  Application.Title := 'Photo Downloader';
  Application.Scaled := True;
  // single instance (the default): hand over to the copy that is already running
  if SingleInstanceWanted and ActivateRunningInstance then Halt(0);
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
