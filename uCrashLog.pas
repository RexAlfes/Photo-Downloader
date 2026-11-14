{ Crash log: every error that reaches the program's error message (for example an Access Violation) is
  first written, with the chain of calls that led to it, to crash.log in the cache folder and, on
  Linux, to the terminal. Debug builds (build mode Default, -gl) show unit names and line numbers in the
  chain; release builds show addresses only. The usual message box is shown afterwards. }
unit uCrashLog;

{$mode objfpc}{$H+}

interface

{ Full path of the crash log. }
function CrashLogName: string;

implementation

uses
  Classes, SysUtils, Forms, uSettings, uVersion;

type
  { Receives Application.OnException. }
  TCrashLogger = class
    procedure AppException(Sender: TObject; E: Exception);
  end;

var
  Logger: TCrashLogger = nil;  // the handler object

function CrashLogName: string;
begin
  Result := CacheDir + 'crash.log';
end;

{ The chain of calls of the exception being handled, one line each. }
function ExceptionTrace: string;
var
  I: Integer;  // I: frame number
  Frames: PCodePointer;  // Frames: return addresses of the calls
begin
  Result := BackTraceStrFunc(ExceptAddr) + LineEnding;  // where it happened
  Frames := ExceptFrames;
  for I := 0 to ExceptFrameCount - 1 do
    Result := Result + BackTraceStrFunc(Frames[I]) + LineEnding;  // who called it
end;

{ Writes the error and its call chain, then shows the usual message. }
procedure TCrashLogger.AppException(Sender: TObject; E: Exception);
var
  S: string;  // S: the report
  F: TFileStream;  // F: the log file
begin
  try
    S := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + AppTitle + ' ' + AppVersionString + LineEnding +
      E.ClassName + ': ' + E.Message + LineEnding + ExceptionTrace + LineEnding;
    {$IFDEF UNIX}
    Write(StdErr, S);  // the terminal (Windows programs without a console have none)
    {$ENDIF}
    if FileExists(CrashLogName) then
      F := TFileStream.Create(CrashLogName, fmOpenReadWrite or fmShareDenyWrite)
    else
      F := TFileStream.Create(CrashLogName, fmCreate);
    try
      F.Seek(0, soEnd);  // add at the end
      F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
  except
    // the log must never cause a second error
  end;
  Application.ShowException(E);  // the usual message box
end;

initialization
  Logger := TCrashLogger.Create;
  Application.OnException := @Logger.AppException;  // Forms is initialized first, so Application exists
finalization
  if Application <> nil then Application.OnException := nil;  // no handler pointing at a freed object
  Logger.Free;
end.
