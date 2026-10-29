unit uSplash;

{$mode objfpc}{$H+}

{ Start-up splash window. ShowSplash is called first thing in the project file, so something
  appears at once on slow computers. Nothing waits in a loop: the main window's start-up timer
  keeps firing while SplashWaiting is True (at most MinShowMs, less when the splash is clicked)
  and then calls CloseSplash. A waiting loop let menu clicks run inside it and froze GTK 3. }

interface

procedure ShowSplash;
{ True while the splash should stay: shown, not clicked, and MinShowMs not reached yet. }
function SplashWaiting: Boolean;
procedure CloseSplash;

implementation

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls, uSettings, uVersion;

const
  MinShowMs = 5000;                 // the splash stays at least this long, unless it is clicked

type
  TSplashHandler = class  // small helper class so a method can be used as a click handler
    procedure Click(Sender: TObject);
  end;

var
  Splash: TForm = nil;  // the splash window (nil when not shown)
  Handler: TSplashHandler = nil;  // object that owns the click handler
  Clicked: Boolean = False;  // True once the user clicked the splash
  StartTick: QWord = 0;  // time (ms) when the splash was shown

{ Hides the splash and frees it. Release frees the window later, so this is safe inside its own
  click event. }
procedure ReleaseSplash;
begin
  try
    if Splash <> nil then
    begin
      Splash.Hide;  // hide the window now
      Splash.Release;  // free it once its events have ended
    end;
  except
    // ignore: the splash is only decoration
  end;
  Splash := nil;  // forget the window
end;

{ Click handler: the user wants the splash closed now. }
procedure TSplashHandler.Click(Sender: TObject);
begin
  Clicked := True;  // SplashWaiting is False from now on
  ReleaseSplash;  // close it at once
end;

{ Builds and shows the splash window with title, version and a moving progress bar. }
procedure ShowSplash;
var
  L: TLabel;  // L: label being created
  Bar: TProgressBar;  // Bar: moving progress bar
  I: Integer;  // I: index for the control loop
begin
  if Splash <> nil then Exit;  // already showing: nothing to do
  try
    Handler := TSplashHandler.Create;  // create the click handler object
    Clicked := False;  // reset the click flag
    StartTick := GetTickCount64;  // remember when the splash appeared
    Splash := TForm.CreateNew(Application);  // borderless form owned by the application
    Splash.BorderStyle := bsNone;  // no title bar or border
    Splash.FormStyle := fsStayOnTop;  // stay above other windows
    Splash.ShowInTaskBar := stNever;  // no taskbar button
    Splash.Position := poScreenCenter;  // center on the screen
    Splash.Color := $2A1E1E;  // dark background color
    Splash.ClientWidth := 420;  // window width in pixels
    Splash.ClientHeight := 170;  // window height in pixels

    L := TLabel.Create(Splash);  // first label: program name
    L.Parent := Splash;  // place it on the splash
    L.AutoSize := False;  // fixed size, no auto fit
    L.SetBounds(0, 28, 420, 40);  // position and size
    L.Alignment := taCenter;  // centered text
    L.Caption := AppTitle;  // program name text
    L.Font.Color := clWhite;  // white text
    L.Font.Size := 22;  // large font
    L.Font.Style := [fsBold];  // bold

    L := TLabel.Create(Splash);  // second label: version
    L.Parent := Splash;  // place it on the splash
    L.AutoSize := False;  // fixed size
    L.SetBounds(0, 76, 420, 22);  // position and size
    L.Alignment := taCenter;  // centered text
    L.Caption := AppVersionString;  // version text from the version resource
    L.Font.Color := clSilver;  // light gray text
    L.Font.Size := 10;  // small font

    L := TLabel.Create(Splash);  // third label: hint text
    L.Parent := Splash;  // place it on the splash
    L.AutoSize := False;  // fixed size
    L.SetBounds(0, 112, 420, 20);  // position and size
    L.Alignment := taCenter;  // centered text
    L.Caption := 'Starting... (click to continue)';  // hint text
    L.Font.Color := clSilver;  // light gray text
    L.Font.Size := 9;  // smaller font

    Bar := TProgressBar.Create(Splash);  // moving bar shows that start-up is in progress
    Bar.Parent := Splash;  // place it on the splash
    Bar.SetBounds(60, 138, 300, 10);  // position and size
    Bar.Style := pbstMarquee;  // endless "marquee" animation
    Splash.OnClick := @Handler.Click;          // a click anywhere closes it
    for I := 0 to Splash.ControlCount - 1 do  // every child control also reacts to a click
      Splash.Controls[I].OnClick := @Handler.Click;  // use the same click handler

    Splash.Show;  // show the window
    Splash.Update;  // paint it now
    Application.ProcessMessages;  // let Windows draw it before the long start-up work
  except
    FreeAndNil(Splash);          // the splash is only decoration: never stop the program
  end;
end;

{ True while the splash should stay on screen. The caller checks it from a timer, so the program
  keeps running normally meanwhile (no waiting loop). }
function SplashWaiting: Boolean;
begin
  Result := (Splash <> nil) and (not Clicked) and (GetTickCount64 - StartTick < MinShowMs);  // shown, not clicked, time not up
end;

{ Closes the splash now. Called by the start-up timer once SplashWaiting is False. }
procedure CloseSplash;
begin
  ReleaseSplash;  // hide and free the window (nothing happens when it is already gone)
  FreeAndNil(Handler);  // free the click handler; no splash events can come any more
end;

finalization
  FreeAndNil(Handler);  // in case CloseSplash was never called

end.
