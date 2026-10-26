unit uViewer;

{$mode objfpc}{$H+}

{ Image viewer opened by double-clicking a thumbnail.
  Esc closes it; arrow keys, Page Up/Down, Space or the mouse wheel move between images.
  Pictures are decoded at screen size and smoothly scaled to the window (uScale). }

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, Menus, LCLType, FPImage,
  uSettings, uItems, uExif, uScale, uDialogs, uHeic;

procedure ShowImageViewer(Items: TList; StartIndex: Integer);

implementation

const
  RawExtList = ';.nef;.nrw;.cr2;.cr3;.crw;.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;';
  TiffExtList = ';.tif;.tiff;.dng;';

type
  TViewerForm = class(TForm)
  private
    FItems: TList;
    FIndex: Integer;
    FImage: TImage;
    FPopup: TPopupMenu;
    FSrc: TFPMemoryImage;           // decoded picture, at least screen size when the file allows
    FResizeTimer: TTimer;
    procedure LoadCurrent;
    procedure ShowFit;
    procedure Step(Delta: Integer);
    procedure ViewerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ImageDblClick(Sender: TObject);
    procedure PropertiesClick(Sender: TObject);
    procedure ResizeTimerTick(Sender: TObject);
    procedure ViewerResize(Sender: TObject);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor CreateViewer(AOwner: TComponent; AItems: TList; AIndex: Integer);
    destructor Destroy; override;
  end;

constructor TViewerForm.CreateViewer(AOwner: TComponent; AItems: TList; AIndex: Integer);
var
  R: TRect;
  VW, VH: Integer;
  MI: TMenuItem;
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
  OnResize := @ViewerResize;
  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Stretch := False;             // the picture is already scaled to fit
  FImage.Proportional := False;
  FImage.Center := True;
  FImage.OnDblClick := @ImageDblClick;
  // right click: Properties
  FPopup := TPopupMenu.Create(Self);
  MI := TMenuItem.Create(Self);
  MI.Caption := 'Properties';
  MI.OnClick := @PropertiesClick;
  FPopup.Items.Add(MI);
  FImage.PopupMenu := FPopup;
  PopupMenu := FPopup;
  FResizeTimer := TTimer.Create(Self);
  FResizeTimer.Enabled := False;
  FResizeTimer.Interval := 120;
  FResizeTimer.OnTimer := @ResizeTimerTick;
  LoadCurrent;
end;

destructor TViewerForm.Destroy;
begin
  FreeAndNil(FSrc);
  inherited Destroy;
end;

procedure TViewerForm.ViewerResize(Sender: TObject);
begin
  // re-scale once the window stops changing size
  if (FSrc <> nil) and (FResizeTimer <> nil) then
  begin
    FResizeTimer.Enabled := False;
    FResizeTimer.Enabled := True;
  end;
end;

procedure TViewerForm.ResizeTimerTick(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  ShowFit;
end;

procedure TViewerForm.ShowFit;
var
  NW, NH: Integer;
  Sc: Double;
  Ms: TMemoryStream;
  Bmp: TBitmap;
begin
  if FSrc = nil then
  begin
    FImage.Picture.Clear;
    Exit;
  end;
  Sc := Min(Max(1, ClientWidth) / FSrc.Width, Max(1, ClientHeight) / FSrc.Height);
  NW := Max(1, Round(FSrc.Width * Sc));
  NH := Max(1, Round(FSrc.Height * Sc));
  Ms := TMemoryStream.Create;
  Bmp := TBitmap.Create;
  try
    if SmoothScaleToBmp(FSrc, NW, NH, Ms) then
    begin
      Ms.Position := 0;
      Bmp.LoadFromStream(Ms);
      FImage.Picture.Assign(Bmp);
    end;
  finally
    Bmp.Free;
    Ms.Free;
  end;
end;

procedure TViewerForm.LoadCurrent;
var
  It: TImageItem;
  Ext: string;
  Mem: TMemoryStream;
  FS: TFileStream;
  W, H, Rank, Target: Integer;
  IsTiff: Boolean;
begin
  if (FIndex < 0) or (FIndex >= FItems.Count) then Exit;
  It := TImageItem(FItems[FIndex]);
  Caption := Format('%s - %s (%d of %d)', [AppTitle, It.FileName, FIndex + 1, FItems.Count]);
  W := 0;
  H := 0;
  // decode at about screen size so the picture can be shown sharply even when maximised
  Target := Min(3000, Max(Screen.Width, Screen.Height));
  Screen.Cursor := crHourGlass;
  try
    FreeAndNil(FSrc);
    Ext := LowerCase(ExtractFileExt(It.FileName));
    IsTiff := Pos(';' + Ext + ';', TiffExtList) > 0;
    try
      if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') then
      begin
        if not ReadJpegDims(It.FullPath, W, H) then
        begin
          W := 0;
          H := 0;
        end;
        FS := TFileStream.Create(It.FullPath, fmOpenRead or fmShareDenyNone);
        try
          FSrc := LoadMemImage(FS, pkJpeg, W, H, Target);
        finally
          FS.Free;
        end;
      end
      else if (Ext = '.png') or (Ext = '.bmp') or (Ext = '.gif') then
      begin
        FS := TFileStream.Create(It.FullPath, fmOpenRead or fmShareDenyNone);
        try
          if Ext = '.png' then
            FSrc := LoadMemImage(FS, pkPng, 0, 0, Target)
          else if Ext = '.gif' then
            FSrc := LoadMemImage(FS, pkGif, 0, 0, Target)       // first frame
          else
            FSrc := LoadMemImage(FS, pkBmp, 0, 0, Target);
        finally
          FS.Free;
        end;
      end
      else if (Pos(';' + Ext + ';', RawExtList) > 0) or IsTiff then
      begin
        // RAW / TIFF / DNG: the largest embedded JPEG preview (the whole file is searched,
        // not just its start), or the plain image data when that is bigger
        Mem := TMemoryStream.Create;
        try
          for Rank := 0 to 2 do
          begin
            Mem.Clear;
            if not ExtractEmbeddedJpeg(It.FullPath, Rank, True, Mem, W, H) then Break;
            if IsTiff and TiffRgbIsLarger(It.FullPath, W, H) then Break;
            Mem.Position := 0;
            FSrc := LoadMemImage(Mem, pkJpeg, W, H, Target);
            if FSrc <> nil then Break;
          end;
        finally
          Mem.Free;
        end;
        if (FSrc = nil) and IsTiff then
          FSrc := LoadTiffMemImage(It.FullPath, Target);
      end
      else if HeicEnabled and (Pos(';' + Ext + ';', HeicExts) > 0) then
        FSrc := LoadHeicMemImage(It.FullPath, Target);
      // turn the picture upright (HEIC decoders already apply the file's own rotation)
      if (FSrc <> nil) and (It.Orientation > 1) and (Pos(';' + Ext + ';', HeicExts) = 0) then
        OrientMemImage(FSrc, It.Orientation);
    except
      FreeAndNil(FSrc);
    end;
    ShowFit;
  finally
    Screen.Cursor := crDefault;
  end;
  if FSrc = nil then Caption := Caption + ' - no preview available';
end;

procedure TViewerForm.PropertiesClick(Sender: TObject);
begin
  if (FIndex >= 0) and (FIndex < FItems.Count) then
    ShowImageProperties(TImageItem(FItems[FIndex]));
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
