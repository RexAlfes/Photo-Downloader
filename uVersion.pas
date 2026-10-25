unit uVersion;

{$mode objfpc}{$H+}

{ Reads the version resource that the Lazarus IDE compiles into the executable
  (Project > Project Options > Version Info). }

interface

function AppVersionString: string;     // e.g. '0.1.0 build 5'

implementation

uses
  SysUtils, fileinfo
  {$IFDEF WINDOWS}, winpeimagereader{$ENDIF}
  {$IFDEF LINUX}, elfreader{$ENDIF}
  {$IFDEF DARWIN}, machoreader{$ENDIF};

function AppVersionString: string;
var
  VI: TVersionInfo;
begin
  Result := 'unknown';
  VI := TVersionInfo.Create;
  try
    try
      VI.Load(HINSTANCE);
      Result := Format('%d.%d.%d build %d',
        [VI.FixedInfo.FileVersion[0], VI.FixedInfo.FileVersion[1],
         VI.FixedInfo.FileVersion[2], VI.FixedInfo.FileVersion[3]]);
    except
      Result := 'unknown';
    end;
  finally
    VI.Free;
  end;
end;

end.
