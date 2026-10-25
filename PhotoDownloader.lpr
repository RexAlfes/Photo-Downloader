program PhotoDownloader;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uSettings, uVersion, uExif, uItems, uDrives, uPhotoView, uDialogs, uViewer, uMain;

{$R *.res}

begin
  Application.Title := 'Photo Downloader';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
