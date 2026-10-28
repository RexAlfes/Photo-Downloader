unit uVersion;

{$mode objfpc}{$H+}

{ Reads the version resource that the Lazarus IDE compiles into the executable
  (Project > Project Options > Version Info). }

interface

function AppVersionString: string;     // e.g. '0.1.0.58' (major.minor.revision.build)

implementation

uses
  SysUtils, fileinfo
  {$IFDEF WINDOWS}, winpeimagereader{$ENDIF}
  {$IFDEF LINUX}, elfreader{$ENDIF}
  {$IFDEF DARWIN}, machoreader{$ENDIF};

{ Returns "major.minor.revision.build" (for example 0.1.0.58) from the version resource, or 'unknown' if it cannot be read.
  From 0.1.0.58 on the revision goes up with every bundle; the build number restarts at 1 and is counted up by the IDE (Project Options > Version Info). }
function AppVersionString: string;
var
  VI: TVersionInfo;  // reader for the executable's version resource
begin
  Result := 'unknown';  // default result if anything fails
  VI := TVersionInfo.Create;  // create the version reader
  try
    try
      VI.Load(HINSTANCE);  // load the resource of the running program
      Result := Format('%d.%d.%d.%d',  // format the four version numbers as text
        [VI.FixedInfo.FileVersion[0], VI.FixedInfo.FileVersion[1],
         VI.FixedInfo.FileVersion[2], VI.FixedInfo.FileVersion[3]]);
    except
      Result := 'unknown';  // keep 'unknown' on any error
    end;
  finally
    VI.Free;  // always release the reader
  end;
end;

end.
