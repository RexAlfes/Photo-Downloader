unit uViewer;

{$mode objfpc}{$H+}

{ Image viewer opened by double-clicking a thumbnail.
  Esc closes it; arrow keys, Page Up/Down, Space or the mouse wheel move between images.
  Pictures are decoded at screen size and smoothly scaled to the window (uScale). }

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls, Menus, LCLType, LCLIntf, FPImage,
  uSettings, uItems, uExif, uScale, uDialogs, uHeic, uWebP, uLrPrev;

procedure ShowImageViewer(Items: TList; StartIndex: Integer);

implementation

const
  RawExtList = ';.nef;.nrw;.cr2;.cr3;.crw;.arw;.srf;.sr2;.dng;.orf;.raf;.rw2;.pef;.srw;.raw;';  // extensions of RAW files (viewed through their embedded JPEG)
  TiffExtList = ';.tif;.tiff;.dng;';  // extensions of TIFF-based files

type
  { The viewer window: shows one picture scaled to fit and lets the user step through the list. }
  TViewerForm = class(TForm)
  private
    FItems: TList;  // FItems: all pictures that can be browsed
    FIndex: Integer;  // FIndex: position of the current picture
    FImage: TImage;  // FImage: control that draws the picture
    FMsg: TLabel;                   // shown when the file cannot be displayed
    FPopup: TPopupMenu;  // FPopup: right-click menu
    FSrc: TFPMemoryImage;           // decoded picture, at least screen size when the file allows
    FResizeTimer: TTimer;  // FResizeTimer: waits until the window stops changing size
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

{ Creates the viewer window over the main window and shows picture AIndex of AItems. }
constructor TViewerForm.CreateViewer(AOwner: TComponent; AItems: TList; AIndex: Integer);
var
  R: TRect;  // R: area of the main window (or the screen)
  VW, VH: Integer;  // VW and VH: viewer width and height
  MI: TMenuItem;  // MI: menu item being created
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  FItems := AItems;  // remember the list
  FIndex := AIndex;  // remember the start position
  Color := clBlack;  // black background
  Position := poDesigned;  // position set by SetBounds below
  WindowState := wsNormal;  // not maximized
  // about two thirds of the main window, centered over it
  if Application.MainForm <> nil then  // use the main window if there is one
    R := Rect(Application.MainForm.Left, Application.MainForm.Top,  // rectangle of the main window
      Application.MainForm.Left + Application.MainForm.Width,
      Application.MainForm.Top + Application.MainForm.Height)
  else  // no main window
    R := Rect(0, 0, Screen.Width, Screen.Height);  // use the whole screen
  VW := (R.Right - R.Left) * 2 div 3;  // two thirds of the width
  VH := (R.Bottom - R.Top) * 2 div 3;  // two thirds of the height
  SetBounds(R.Left + ((R.Right - R.Left) - VW) div 2, R.Top + ((R.Bottom - R.Top) - VH) div 2, VW, VH);  // center the viewer on that area
  KeyPreview := True;  // the form sees keys before the controls
  OnKeyDown := @ViewerKeyDown;  // key handler
  OnResize := @ViewerResize;  // resize handler
  FImage := TImage.Create(Self);  // picture control
  FImage.Parent := Self;  // place on the form
  FImage.Align := alClient;  // fill the window
  FImage.Stretch := False;             // the picture is already scaled to fit
  FImage.Proportional := False;
  FImage.Center := True;  // show the picture centered
  FImage.OnDblClick := @ImageDblClick;  // double-click closes the viewer
  // right click: Properties
  FPopup := TPopupMenu.Create(Self);  // right click menu
  MI := TMenuItem.Create(Self);  // menu item
  MI.Caption := 'Properties';  // its text
  MI.OnClick := @PropertiesClick;  // its action
  FPopup.Items.Add(MI);  // add to the menu
  FImage.PopupMenu := FPopup;  // attach the menu to the picture
  FMsg := TLabel.Create(Self);  // message label for pictures that cannot be shown
  FMsg.Parent := Self;  // place on the form
  FMsg.Align := alClient;  // fill the window
  FMsg.Alignment := taCenter;  // center horizontally
  FMsg.Layout := tlCenter;  // center vertically
  FMsg.WordWrap := True;  // wrap long text
  FMsg.AutoSize := False;  // fixed size
  FMsg.Font.Color := clSilver;  // light gray text
  FMsg.Font.Size := 12;  // readable size
  FMsg.BorderSpacing.Around := 24;  // margin around the text
  FMsg.Caption := 'Sorry, the viewer can''t open this file because the format is ' +
    'currently unsupported, or the file is corrupted.';
  FMsg.Visible := False;  // hidden until needed
  FMsg.OnDblClick := @ImageDblClick;  // double-click closes the viewer
  FMsg.PopupMenu := FPopup;  // attach the menu
  PopupMenu := FPopup;  // attach the menu to the form
  FResizeTimer := TTimer.Create(Self);  // timer for delayed re-scaling
  FResizeTimer.Enabled := False;  // off until the window is resized
  FResizeTimer.Interval := 120;  // 120 ms after the last resize
  FResizeTimer.OnTimer := @ResizeTimerTick;  // timer action
  LoadCurrent;  // show the first picture
end;

{ Frees the decoded picture. }
destructor TViewerForm.Destroy;
begin
  FreeAndNil(FSrc);  // release the picture
  inherited Destroy;  // run the normal clean-up
end;

{ Window resized: restart the timer so the picture is re-scaled after the resizing stops. }
procedure TViewerForm.ViewerResize(Sender: TObject);
begin
  // re-scale once the window stops changing size
  if (FSrc <> nil) and (FResizeTimer <> nil) then  // a picture is shown and the timer exists
  begin
    FResizeTimer.Enabled := False;  // stop any running countdown
    FResizeTimer.Enabled := True;  // start counting again
  end;
end;

{ Timer fired: the window has stopped changing, so re-scale the picture. }
procedure TViewerForm.ResizeTimerTick(Sender: TObject);
begin
  FResizeTimer.Enabled := False;  // stop the timer
  ShowFit;  // draw the picture at the new size
end;

{ Scales the decoded picture to fit the window and shows it. }
procedure TViewerForm.ShowFit;
var
  NW, NH: Integer;  // NW and NH: scaled size
  Sc: Double;  // Sc: scale factor
  Ms: TMemoryStream;  // Ms: scaled picture as a BMP stream
  Bmp: TBitmap;  // Bmp: scaled bitmap
begin
  if FSrc = nil then  // no picture
  begin
    FImage.Picture.Clear;  // clear the display
    Exit;  // stop
  end;
  Sc := Min(Max(1, ClientWidth) / FSrc.Width, Max(1, ClientHeight) / FSrc.Height);  // scale that makes the picture fit both ways
  NW := Max(1, Round(FSrc.Width * Sc));  // new width
  NH := Max(1, Round(FSrc.Height * Sc));  // new height
  Ms := TMemoryStream.Create;  // stream for the scaled picture
  Bmp := TBitmap.Create;  // bitmap for the display
  try
    if SmoothScaleToBmp(FSrc, NW, NH, Ms) then  // scale smoothly into the stream
    begin
      Ms.Position := 0;  // rewind the stream
      Bmp.LoadFromStream(Ms);  // read the bitmap from it
      FImage.Picture.Assign(Bmp);  // show it
    end;
  finally
    Bmp.Free;  // free the bitmap
    Ms.Free;  // free the stream
  end;
end;

{ Loads the current picture; the file's real format is detected from its content, not its extension. }
procedure TViewerForm.LoadCurrent;
var
  It: TImageItem;  // It: item to show
  Ext: string;  // Ext: lowercase file extension
  Mem: TMemoryStream;  // Mem: embedded JPEG preview
  FS: TFileStream;  // FS: the file as a stream
  W, H, Rank, Target: Integer;  // W and H: picture size, Rank: which embedded preview to try, Target: size to decode at
  IsTiff: Boolean;  // IsTiff: True for TIFF-based files
  Sniff: Integer;  // Sniff: format found from the first bytes (1 TIFF, 2 JPEG, 3 PNG, 4 BMP, 5 GIF, 6 WebP, 7 HEIC)
  WebPErr: string;  // WebPErr: reason a WebP could not be decoded
  LrInfo: TLrPrevInfo;  // LrInfo: header values of a Lightroom preview file
  LrErr: string;  // LrErr: reason a Lightroom preview file could not be read
begin
  WebPErr := '';  // no error yet
  if (FIndex < 0) or (FIndex >= FItems.Count) then Exit;  // index out of range: nothing to show
  It := TImageItem(FItems[FIndex]);  // the picture to show
  Caption := Format('%s - %s (%d of %d)', [AppTitle, It.FileName, FIndex + 1, FItems.Count]);  // window title: program, file name, position
  W := 0;  // size unknown yet
  H := 0;  // size unknown yet
  FMsg.Visible := False;  // hide the error message
  // decode at about screen size so the picture can be shown sharply even when maximized
  Target := Min(3000, Max(Screen.Width, Screen.Height));  // decode at about screen size
  Screen.Cursor := crHourGlass;  // show the hourglass
  try
    FreeAndNil(FSrc);  // free the previous picture
    Ext := LowerCase(ExtractFileExt(It.FileName));  // file extension in lowercase
    IsTiff := Pos(';' + Ext + ';', TiffExtList) > 0;  // is it a TIFF-based extension?
    try
      if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') then  // named like a JPEG
      begin
        Sniff := SniffFileKind(It.FullPath);  // what the file really is
        if Sniff = 1 then  // actually a TIFF
          FSrc := LoadTiffMemImage(It.FullPath, Target)      // a TIFF with a .jpg name
        else
        begin
          if not ReadJpegDims(It.FullPath, W, H) then  // read the JPEG size from the file
          begin
            W := 0;  // size not available
            H := 0;  // size not available
          end;
          FS := TFileStream.Create(It.FullPath, fmOpenRead or fmShareDenyNone);  // open the file
          try
            case Sniff of  // choose the reader by content
              3: FSrc := LoadMemImage(FS, pkPng, 0, 0, Target);   // not a JPEG at all
              4: FSrc := LoadMemImage(FS, pkBmp, 0, 0, Target);  // BMP
              5: FSrc := LoadMemImage(FS, pkGif, 0, 0, Target);  // GIF
              6: FSrc := LoadWebPMemImage(It.FullPath, Target, WebPErr);   // a WebP with a .jpg name
              7: if HeicEnabled then FSrc := LoadHeicMemImage(It.FullPath, Target);  // HEIC or AVIF
            else
              FSrc := LoadMemImage(FS, pkJpeg, W, H, Target);  // a real JPEG
            end;
          finally
            FS.Free;  // close the file
          end;
        end;
      end
      else if (Ext = '.png') or (Ext = '.bmp') or (Ext = '.gif') then  // named like a PNG, BMP or GIF
      begin
        FS := TFileStream.Create(It.FullPath, fmOpenRead or fmShareDenyNone);  // open the file
        try
          Sniff := SniffFileKind(It.FullPath);  // what the file really is
          if (Sniff = 2) then  // actually a JPEG
            FSrc := LoadMemImage(FS, pkJpeg, 0, 0, Target)       // a JPEG with a .png/.bmp/.gif name
          else if (Sniff = 3) or ((Sniff = 0) and (Ext = '.png')) then  // PNG, or unknown content with a .png name
            FSrc := LoadMemImage(FS, pkPng, 0, 0, Target)
          else if (Sniff = 5) or ((Sniff = 0) and (Ext = '.gif')) then  // GIF, or unknown content with a .gif name
            FSrc := LoadMemImage(FS, pkGif, 0, 0, Target)       // first frame
          else if Sniff = 6 then  // actually a WebP
            FSrc := LoadWebPMemImage(It.FullPath, Target, WebPErr)     // a WebP with another name
          else if Sniff = 7 then  // actually HEIC or AVIF
          begin
            if HeicEnabled then FSrc := LoadHeicMemImage(It.FullPath, Target);  // decode it if the decoder is built in
          end
          else
            FSrc := LoadMemImage(FS, pkBmp, 0, 0, Target);  // everything else is read as BMP
        finally
          FS.Free;  // close the file
        end;
      end
      else if (Pos(';' + Ext + ';', RawExtList) > 0) or IsTiff then  // RAW, TIFF or DNG file
      begin
        // RAW / TIFF / DNG: the largest embedded JPEG preview (the whole file is searched,
        // not just its start), or the plain image data when that is bigger
        Mem := TMemoryStream.Create;  // stream for the embedded JPEG
        try
          for Rank := 0 to 2 do  // try up to three embedded previews, largest first
          begin
            Mem.Clear;  // clear the stream
            if not ExtractEmbeddedJpeg(It.FullPath, Rank, True, Mem, W, H) then Break;  // no more previews
            if IsTiff and TiffRgbIsLarger(It.FullPath, W, H) then Break;  // the TIFF's own image data is larger: use that instead
            Mem.Position := 0;  // rewind
            FSrc := LoadMemImage(Mem, pkJpeg, W, H, Target);  // decode the preview
            if FSrc <> nil then Break;  // got a picture
          end;
        finally
          Mem.Free;  // free the stream
        end;
        if (FSrc = nil) and IsTiff then  // nothing usable and it is a TIFF
          FSrc := LoadTiffMemImage(It.FullPath, Target);  // decode the TIFF image data
      end
      else if Ext = '.webp' then  // named .webp
      begin
        Sniff := SniffFileKind(It.FullPath);  // what the file really is
        if Sniff in [2, 3, 4, 5] then  // not WebP at all
        begin
          // the content decides, not the name
          FS := TFileStream.Create(It.FullPath, fmOpenRead or fmShareDenyNone);  // open the file
          try
            case Sniff of  // read by content
              2: FSrc := LoadMemImage(FS, pkJpeg, 0, 0, Target);  // JPEG
              3: FSrc := LoadMemImage(FS, pkPng, 0, 0, Target);  // PNG
              4: FSrc := LoadMemImage(FS, pkBmp, 0, 0, Target);  // BMP
            else
              FSrc := LoadMemImage(FS, pkGif, 0, 0, Target);  // GIF
            end;
          finally
            FS.Free;  // close the file
          end;
        end
        else
          FSrc := LoadWebPMemImage(It.FullPath, Target, WebPErr);  // decode the WebP picture
      end
      else if Pos(';' + Ext + ';', LrPrevExts) > 0 then  // Lightroom preview file
      begin
        Mem := TMemoryStream.Create;  // stream for the JPEG of the largest level
        try
          if LrPrevExtract(It.FullPath, Mem, LrInfo, LrErr) then
            FSrc := LoadMemImage(Mem, pkJpeg, LrInfo.LevelW, LrInfo.LevelH, Target)  // decode it
          else
            WebPErr := LrErr;  // shown in the log below
        finally
          Mem.Free;  // free the stream
        end;
      end
      else if HeicEnabled and (Pos(';' + Ext + ';', HeicExts) > 0) then  // HEIC, HEIF or AVIF
        FSrc := LoadHeicMemImage(It.FullPath, Target);  // decode it
      // turn the picture upright (HEIC decoders already apply the file's own rotation)
      if (FSrc <> nil) and (It.Orientation > 1) and (Pos(';' + Ext + ';', HeicExts) = 0) then  // rotate to upright unless the decoder already did
        OrientMemImage(FSrc, It.Orientation);  // apply the EXIF orientation
    except
      FreeAndNil(FSrc);  // any error leaves no picture
    end;
    ShowFit;  // show whatever was loaded
  finally
    Screen.Cursor := crDefault;  // restore the normal cursor
  end;
  if FSrc = nil then  // no picture could be loaded
  begin
    if LooksLikeText(It.FullPath) then  // the file is plain text
      LogThumb(It.FullPath + ': viewer could not open it: not an image (text file)' + HeaderNote(It.FullPath))  // write that to the log
    else
      LogThumb(It.FullPath + ': viewer could not open it' +  // write the reason to the log
        IfThen(WebPErr <> '', ': ' + WebPErr, IfThen(LoadMemImageError <> '', ': ' + LoadMemImageError, '')) + HeaderNote(It.FullPath));
    Caption := Caption + ' - cannot be displayed';  // add the problem to the window title
    FMsg.Visible := True;  // show the "cannot open" message
  end;
end;

{ Menu action: shows the properties of the current picture. }
procedure TViewerForm.PropertiesClick(Sender: TObject);
begin
  if (FIndex >= 0) and (FIndex < FItems.Count) then  // index is valid
    ShowImageProperties(TImageItem(FItems[FIndex]));  // open the properties window
end;

{ Moves Delta pictures forward or back and shows the new one. }
procedure TViewerForm.Step(Delta: Integer);
var
  N: Integer;  // N: new position
begin
  N := FIndex + Delta;  // new position
  if N < 0 then N := 0;  // not before the first picture
  if N > FItems.Count - 1 then N := FItems.Count - 1;  // not after the last picture
  if N = FIndex then Exit;  // nothing changes: nothing to load
  FIndex := N;  // remember the position
  LoadCurrent;  // show the picture
end;

{ Keyboard: Esc closes; arrows, Page Up/Down and Space step through the pictures. }
procedure TViewerForm.ViewerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift <> [] then Exit;  // ignore keys pressed with Shift, Ctrl or Alt
  case Key of  // choose by key
    VK_ESCAPE: Close;  // Esc closes
    VK_LEFT, VK_UP, VK_PRIOR: Step(-1);  // previous picture
    VK_RIGHT, VK_DOWN, VK_NEXT, VK_SPACE: Step(1);  // next picture
    VK_HOME: Step(-FItems.Count);  // first picture
    VK_END: Step(FItems.Count);  // last picture
  else
    Exit;  // any other key is left alone
  end;
  Key := 0;  // mark the key as handled
end;

{ Double-click on the picture closes the viewer. }
procedure TViewerForm.ImageDblClick(Sender: TObject);
begin
  Close;  // close the window
end;

{ Mouse wheel: up goes to the previous picture, down to the next. }
function TViewerForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);  // let the base class try first
  if Result then Exit;  // already handled
  if WheelDelta > 0 then Step(-1) else Step(1);  // choose the direction
  Result := True;  // report it as handled
end;

{ Opens the viewer window as a modal dialog at picture StartIndex. }
procedure ShowImageViewer(Items: TList; StartIndex: Integer);
var
  F: TViewerForm;  // F: the viewer form
begin
  if (Items = nil) or (StartIndex < 0) or (StartIndex >= Items.Count) then Exit;  // nothing to show: do nothing
  if TImageItem(Items[StartIndex]).IsVideo or TImageItem(Items[StartIndex]).IsAudio then  // video and audio are played by the system's default player
  begin
    OpenDocument(TImageItem(Items[StartIndex]).FullPath);  // open it in the default player outside the program
    Exit;
  end;
  F := TViewerForm.CreateViewer(Application, Items, StartIndex);  // create the viewer
  try
    F.ShowModal;  // show it and wait until it closes
  finally
    F.Free;  // free the form
  end;
end;

end.
