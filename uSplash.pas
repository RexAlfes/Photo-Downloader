unit uSplash;

{$mode objfpc}{$H+}

{ Start-up splash window. ShowSplash is called first thing in the project file, so something
  appears at once on slow computers; CloseSplash is called when the main window is up. }

interface

procedure ShowSplash;
procedure CloseSplash;

implementation

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls, uSettings, uVersion;

const
  MinShowMs = 5000;                 // the splash stays at least this long, unless it is clicked

type
  TSplashHandler = class  // small helper class so a method can be used as a click handler
    procedure Click(Sender: TObject);
    procedure TimerDone(Sender: TObject);  // Linux: the minimum time has passed
  end;

var
  Splash: TForm = nil;  // the splash window (nil when not shown)
  Handler: TSplashHandler = nil;  // object that owns the click handler
  Clicked: Boolean = False;  // True once the user clicked the splash
  StartTick: QWord = 0;  // time (ms) when the splash was shown
  CloseTimer: TTimer = nil;  // Linux: closes the splash when the minimum time has passed (nil when not waiting)

{ Linux: closes the splash without waiting in a loop. Release and ReleaseComponent free the
  window and the timer later, so this is safe inside their own click and timer events. }
procedure ReleaseSplash;
begin
  try
    if CloseTimer <> nil then
    begin
      CloseTimer.Enabled := False;  // no second call
      Application.ReleaseComponent(CloseTimer);  // free the timer once its event has ended
      CloseTimer := nil;  // forget it
    end;
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

{ Click handler: remember that the user wants the splash closed. }
procedure TSplashHandler.Click(Sender: TObject);
begin
  Clicked := True;  // let CloseSplash stop waiting
  {$IFDEF UNIX}
  if CloseTimer <> nil then ReleaseSplash;  // Linux: already waiting for the timer, so close now
  {$ENDIF}
end;

{ Timer handler (Linux): the minimum time has passed, close the splash. }
procedure TSplashHandler.TimerDone(Sender: TObject);
begin
  ReleaseSplash;  // close it
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

{ Called when the main window is up. The splash is kept for MinShowMs from its start (the
  main window shows behind it meanwhile) unless it is clicked. }
procedure CloseSplash;
{$IFDEF UNIX}
var
  Remaining: Int64;  // ms left until MinShowMs is reached
{$ENDIF}
begin
  if Splash = nil then Exit;  // no splash: nothing to do
  {$IFDEF UNIX}
  // Linux: a timer instead of a waiting loop. A loop inside the start-up timer lets menu clicks
  // run inside it, which froze GTK 3; the timer returns at once and the program runs normally.
  Remaining := MinShowMs - Int64(GetTickCount64 - StartTick);  // time still to show
  if (not Clicked) and (Remaining > 0) and (CloseTimer = nil) then
  begin
    try
      CloseTimer := TTimer.Create(nil);  // own timer, freed in ReleaseSplash
      CloseTimer.Interval := Remaining;  // fire when the minimum time is reached
      CloseTimer.OnTimer := @Handler.TimerDone;  // then close the splash
      CloseTimer.Enabled := True;  // start it
      Exit;  // the timer (or a click) closes the splash
    except
      FreeAndNil(CloseTimer);  // no timer: close at once below
    end;
  end;
  ReleaseSplash;  // clicked, time is up, or no timer: close now
  {$ELSE}
  try
    // Windows: keep the splash for at least MinShowMs
    while (not Clicked) and (GetTickCount64 - StartTick < MinShowMs) do  // wait until clicked or the minimum time has passed
    begin
      Application.ProcessMessages;  // keep the screen responsive while waiting
      if Application.Terminated then Break;  // program is closing: stop waiting
      Sleep(20);  // short pause to avoid using the processor
    end;
    Splash.Hide;  // hide the window
    Splash.Free;  // free it
  except
    // ignore
  end;
  Splash := nil;  // forget the window
  FreeAndNil(Handler);  // free the click handler
  {$ENDIF}
end;

finalization
  FreeAndNil(Handler);  // Linux keeps the click handler until the end (the timer may still use it)

end.
