unit uViewer;

{$mode objfpc}{$H+}

{ Full-window image viewer opened by double-clicking a thumbnail.
  Esc closes it; arrow keys, Page Up/Down, Space or the mouse wheel move between images. }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType, uSettings, uItems, uExif;

procedure ShowImageViewer(Items: TList; StartIndex: Integer);

implementation

type
  TViewerForm = class(TForm)
  private
    FItems: TList;
    FIndex: Integer;
    FImage: TImage;
    procedure LoadCurrent;
    procedure Step(Delta: Integer);
    procedure ViewerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ImageDblClick(Sender: TObject);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor CreateViewer(AOwner: TComponent; AItems: TList; AIndex: Integer);
  end;

constructor TViewerForm.CreateViewer(AOwner: TComponent; AItems: TList; AIndex: Integer);
var
  R: TRect;
  VW, VH: Integer;
begin
  inherited CreateNew(AOwner);
  FItems := AItems;
  FIndex := AIndex;
  Color := clBlack;
  Position := poDesigned;
  WindowState := wsNormal;
  // about two thirds of the main window, centred over it
  if Application.MainForm <> nil then
    R := Rect(Application.MainForm.Left, Application.MainForm.Top,
      Application.MainForm.Left + Application.MainForm.Width,
      Application.MainForm.Top + Application.MainForm.Height)
  else
    R := Rect(0, 0, Screen.Width, Screen.Height);
  VW := (R.Right - R.Left) * 2 div 3;
  VH := (R.Bottom - R.Top) * 2 div 3;
  SetBounds(R.Left + ((R.Right - R.Left) - VW) div 2, R.Top + ((R.Bottom - R.Top) - VH) div 2, VW, VH);
  KeyPreview := True;
  OnKeyDown := @ViewerKeyDown;
  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Stretch := True;
  FImage.Proportional := True;
  FImage.Center := True;
  FImage.OnDblClick := @ImageDblClick;
  LoadCurrent;
end;

procedure TViewerForm.LoadCurrent;
var
  It: TImageItem;
  Ext: string;
  Jpg: TJPEGImage;
  Mem: TMemoryStream;
  W, H, Rank: Integer;
  Ok: Boolean;
begin
  if (FIndex < 0) or (FIndex >= FItems.Count) then Exit;
  It := TImageItem(FItems[FIndex]);
  Caption := Format('%s - %s (%d of %d)', [AppTitle, It.FileName, FIndex + 1, FItems.Count]);
  Ok := False;
  W := 0;
  H := 0;
  Screen.Cursor := crHourGlass;
  try
    FImage.Picture.Clear;
    Ext := LowerCase(ExtractFileExt(It.FileName));
    try
      if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') or (Ext = '.png') or (Ext = '.bmp') then
      begin
        FImage.Picture.LoadFromFile(It.FullPath);
        Ok := True;
      end
      else if Pos(';' + Ext + ';', ';.nef;.nrw;.cr2;.cr3;.crw;.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;') > 0 then
      begin
        // RAW: show the largest embedded JPEG preview
        Mem := TMemoryStream.Create;
        try
          for Rank := 0 to 2 do
          begin
            Mem.Clear;
            if not ExtractEmbeddedJpeg(It.FullPath, Rank, Mem, W, H) then Break;
            Mem.Position := 0;
            Jpg := TJPEGImage.Create;
            try
              try
                Jpg.LoadFromStream(Mem);
                FImage.Picture.Assign(Jpg);
                Ok := True;
              except
                Ok := False;
              end;
            finally
              Jpg.Free;
            end;
            if Ok then Break;
          end;
        finally
          Mem.Free;
        end;
      end;
    except
      Ok := False;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if not Ok then Caption := Caption + ' - no preview available';
end;

procedure TViewerForm.Step(Delta: Integer);
var
  N: Integer;
begin
  N := FIndex + Delta;
  if N < 0 then N := 0;
  if N > FItems.Count - 1 then N := FItems.Count - 1;
  if N = FIndex then Exit;
  FIndex := N;
  LoadCurrent;
end;

procedure TViewerForm.ViewerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift <> [] then Exit;
  case Key of
    VK_ESCAPE: Close;
    VK_LEFT, VK_UP, VK_PRIOR: Step(-1);
    VK_RIGHT, VK_DOWN, VK_NEXT, VK_SPACE: Step(1);
    VK_HOME: Step(-FItems.Count);
    VK_END: Step(FItems.Count);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TViewerForm.ImageDblClick(Sender: TObject);
begin
  Close;
end;

function TViewerForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if WheelDelta > 0 then Step(-1) else Step(1);
  Result := True;
end;

procedure ShowImageViewer(Items: TList; StartIndex: Integer);
var
  F: TViewerForm;
begin
  if (Items = nil) or (StartIndex < 0) or (StartIndex >= Items.Count) then Exit;
  F := TViewerForm.CreateViewer(Application, Items, StartIndex);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
