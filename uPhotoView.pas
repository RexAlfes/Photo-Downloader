unit uPhotoView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, StdCtrls, ExtCtrls, Forms, LCLType, uItems;

const
  SmallCellWidth = 200;  // width of a card in the small view

type
  TViewMode = (vmList, vmSmall, vmLarge);  // list, small thumbnails, large thumbnails
  TOpenItemEvent = procedure(Sender: TObject; Index: Integer) of object;  // called when an item is opened (double-click)
  THeaderClickEvent = procedure(Sender: TObject; Col: Integer) of object;  // called when a list column heading is clicked

  { TPhotoView - scrolling grid of image cards (or a one-line-per-image list) }
  TPhotoView = class(TCustomControl)
  private
    FItems: TList;                  // visible items, not owned
    FMode: TViewMode;  // current view mode
    FScroll: TScrollBar;  // vertical scroll bar
    FCellW, FCellH, FCols, FLineH, FThumbBox, FTotalH, FLargeW: Integer;  // FCellW, FCellH: card size; FCols: cards per row; FLineH: text line height; FThumbBox: thumbnail box size; FTotalH: total height; FLargeW: cached large card width
    FFocusIdx, FAnchor: Integer;  // focused item and the anchor of a shift-selection
    FLaidOut: Boolean;  // True once the sizes have been computed
    FLoadBudget: Integer;           // thumbnails that may still be decoded in this paint
    FNeedMore: Boolean;             // some thumbnails were postponed to the next paint
    FLoadTimer: TTimer;
    FOnSelChange: TNotifyEvent;  // selection changed event
    FOnOpenItem: TOpenItemEvent;  // item opened event
    FLastX, FLastY: Integer;  // last mouse position
    FLastButton: TMouseButton;  // last mouse button
    FHdrH, FSortCol: Integer;       // list view header height; sorted column (-1 none)
    FSortDesc: Boolean;  // True when the sort is descending
    FOnHeaderClick: THeaderClickEvent;  // heading click event
    procedure ScrollChange(Sender: TObject);  // scroll bar moved
    procedure LoadTimerTick(Sender: TObject);  // timer that continues loading thumbnails
    procedure DoLayout;  // computes card sizes and scroll bar limits
    function OffsetY: Integer;  // current scroll offset in pixels
    function TopPad: Integer;  // space above the cards (the list header)
    function ViewH: Integer;  // height of the visible card area
    function HeaderCol(X: Integer): Integer;  // which list column is at X
    procedure DrawHeader;  // draws the list column headings
    function MaxOffset: Integer;  // largest scroll offset
    function HitTest(X, Y: Integer): Integer;  // index of the item at a mouse position, or -1
    procedure DrawItem(Item: TImageItem; const R: TRect);  // draws one card
    procedure DrawThumb(Item: TImageItem; X, Y: Integer);  // draws one thumbnail or its placeholder
    function FitLeft(const S: string; MaxW: Integer): string;  // shortens text from the left with '...'
    procedure SetMode(AValue: TViewMode);  // changes the view mode
    procedure SelectIndex(Idx: Integer; Shift: TShiftState);  // selects an item (with Shift/Ctrl rules)
    procedure EnsureVisible(Idx: Integer);  // scrolls so an item is visible
  protected
    procedure Paint; override;  // paints the whole grid
    procedure Resize; override;  // re-computes the layout
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;  // mouse button pressed
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;  // keyboard navigation
    procedure DblClick; override;  // double-click
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;  // mouse wheel scrolling
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;  // creates the control
    destructor Destroy; override;  // frees the item list
    procedure SetItems(const L: TList);  // replaces the shown items
    procedure SelectionChanged;  // redraws after the selection changed
    procedure ScrollToItem(Item: TImageItem);  // scrolls to an item
    { width of one large-thumbnail card (wide enough for the first text line) }
    function LargeCellWidth: Integer;  // width of one large-thumbnail card
    { width of one card in the current view (0 for the list view) }
    function CellWidthNow: Integer;  // width of one card in the current view
    function ScrollBarWidth: Integer;  // width of the scroll bar
    property Mode: TViewMode read FMode write SetMode;  // the view mode
    property OnSelectionChange: TNotifyEvent read FOnSelChange write FOnSelChange;  // event: selection changed
    property OnOpenItem: TOpenItemEvent read FOnOpenItem write FOnOpenItem;  // event: item opened
    property OnHeaderClick: THeaderClickEvent read FOnHeaderClick write FOnHeaderClick;  // event: heading clicked
    property SortCol: Integer read FSortCol write FSortCol;  // sorted column (-1 none)
    property SortDesc: Boolean read FSortDesc write FSortDesc;  // sort direction
  end;

implementation

const
  ColNormal = $00EBEBEF;      // BGR of RGB(239,235,235)
  ColProblem = $006060FF;     // RGB(255,96,96)
  ColSelected = $00FAD7BE;    // RGB(190,215,250)
  ColSelProblem = $009664EB;  // RGB(235,100,150)
  ColDownloaded = $00C8C8C8;  // RGB(200,200,200): already downloaded
  ColSelDownloaded = $00CDB4A0;  // RGB(160,180,205)
  ColDuplicate = $00AAECFF;     // RGB(255,236,170): duplicate file (amber)
  ColSelDuplicate = $008CCDEB;  // RGB(235,205,140): selected duplicate file

{ Creates the grid: item list, scroll bar and the timer for postponed thumbnails. }
constructor TPhotoView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);  // run the base constructor
  FItems := TList.Create;  // list of the shown items (not owned)
  FMode := vmSmall;  // small thumbnails by default
  FFocusIdx := -1;  // nothing focused
  FAnchor := -1;  // no selection anchor
  FLineH := 15;  // default text line height
  FSortCol := -1;  // no sort column
  TabStop := True;  // the control can take the keyboard focus
  Color := clWindow;  // white background
  ControlStyle := ControlStyle + [csOpaque];   // paint covers everything; avoids flicker
  FScroll := TScrollBar.Create(Self);  // scroll bar
  FScroll.Parent := Self;  // place it inside the grid
  FScroll.Kind := sbVertical;  // vertical
  FScroll.Align := alRight;  // on the right edge
  FScroll.TabStop := False;  // not in the tab order
  FScroll.OnChange := @ScrollChange;  // scroll handler
  FLoadTimer := TTimer.Create(Self);  // timer for postponed thumbnails
  FLoadTimer.Enabled := False;  // off until needed
  FLoadTimer.Interval := 15;  // 15 ms between loads
  FLoadTimer.OnTimer := @LoadTimerTick;  // timer action
end;

{ Frees the item list. }
destructor TPhotoView.Destroy;
begin
  FItems.Free;  // free the list (the items themselves are owned elsewhere)
  inherited Destroy;  // run the base destructor
end;

{ Changes the view mode, scrolls to the top and redraws. }
procedure TPhotoView.SetMode(AValue: TViewMode);
begin
  if FMode = AValue then Exit;  // nothing to do if unchanged
  FMode := AValue;  // remember the mode
  FScroll.Position := 0;  // back to the top
  DoLayout;  // recompute card sizes
  Invalidate;  // redraw
end;

{ Replaces the shown items with a copy of L and resets focus and anchor. }
procedure TPhotoView.SetItems(const L: TList);
var
  I: Integer;  // I: item index
begin
  FItems.Clear;  // clear the old list
  for I := 0 to L.Count - 1 do  // each new item
    FItems.Add(L[I]);  // copy the reference
  FFocusIdx := -1;  // no focused item
  FAnchor := -1;  // no anchor
  DoLayout;  // recompute card sizes
  Invalidate;  // redraw
end;

{ Scrolls so that Item is visible and redraws. }
procedure TPhotoView.ScrollToItem(Item: TImageItem);
begin
  EnsureVisible(FItems.IndexOf(Item));  // make its row visible
  Invalidate;  // redraw
end;

{ Redraws and tells the owner that the selection changed. }
procedure TPhotoView.SelectionChanged;
begin
  Invalidate;  // redraw
  if Assigned(FOnSelChange) then FOnSelChange(Self);  // notify the owner
end;

{ Returns the width of a large card; computed once from the longest usual first text line. }
function TPhotoView.LargeCellWidth: Integer;
var
  Bmp: TBitmap;  // Bmp: temporary bitmap used to measure text
begin
  if FLargeW > 0 then  // already computed
  begin
    Result := FLargeW;  // use the saved value
    Exit;  // done
  end;
  // 3 px margin + 160 px thumbnail + 4 px gap + the longest usual first line, e.g.
  // "1234) DSC_00000000_ABCD.NEF (99.99 MB)"
  Bmp := TBitmap.Create;  // temporary bitmap
  try
    Bmp.Canvas.Font.Assign(Font);  // use the grid's font
    Result := 3 + 160 + 4 + Bmp.Canvas.TextWidth('0000) WWWW_00000000_WWWW.WWW (999.99 MB)') + 8;  // margin + thumbnail + gap + longest line + margin
  finally
    Bmp.Free;  // free the bitmap
  end;
  if Result < 340 then Result := 340;  // at least 340 pixels
  FLargeW := Result;  // remember the value
end;

{ Returns the card width of the current view (0 for the list). }
function TPhotoView.CellWidthNow: Integer;
begin
  case FMode of  // by view mode
    vmSmall: Result := SmallCellWidth;  // small cards have a fixed width
    vmLarge: Result := LargeCellWidth;  // large cards fit their first line
  else
    Result := 0;  // list rows have no card width
  end;
end;

{ Returns the width of the scroll bar. }
function TPhotoView.ScrollBarWidth: Integer;
begin
  Result := FScroll.Width;  // scroll bar width
end;

{ Computes card sizes, rows, total height and scroll bar limits for the current width and mode. }
procedure TPhotoView.DoLayout;
var
  W, Rows: Integer;  // W: usable width, Rows: number of rows
begin
  if HandleAllocated then  // a window exists
  begin
    Canvas.Font := Font;  // use the control's font
    FLineH := Canvas.TextHeight('Ag') + 1;  // text line height plus one
    FHdrH := FLineH + 6;  // list header height
    FLaidOut := True;  // layout is valid
  end;
  W := ClientWidth - FScroll.Width;  // width without the scroll bar
  if W < 60 then W := 60;  // not narrower than 60
  case FMode of
    vmList:
      begin
        FCellW := W;  // list: one full-width row per picture
        FCellH := FLineH + 4;  // row height
      end;
    vmSmall:
      begin
        FThumbBox := 64;  // small view: 64-pixel thumbnails
        FCellW := SmallCellWidth;  // fixed card width
        FCellH := FLineH * 5 + 10;  // five text lines plus margin
      end;
  else
    begin
      FThumbBox := 160;  // large view: 160-pixel thumbnails
      FCellW := LargeCellWidth;  // card width fits the first line
      FCellH := FThumbBox + FLineH + 12;  // thumbnail plus one line plus margin
    end;
  end;
  if FMode = vmList then FCols := 1 else FCols := Max(1, W div FCellW);  // cards per row (always at least one)
  Rows := (FItems.Count + FCols - 1) div FCols;  // number of rows, rounded up
  FTotalH := Rows * FCellH;  // total height of all rows

  FScroll.OnChange := nil;  // do not fire the scroll event while changing it
  try
    if FTotalH > ViewH then  // more rows than fit
    begin
      FScroll.Min := 0;  // scroll range start
      FScroll.Max := FTotalH;  // scroll range end
      FScroll.PageSize := Max(1, ViewH);  // visible part
      FScroll.LargeChange := Max(1, ViewH);  // page step
      FScroll.SmallChange := Max(1, FCellH div 2);  // arrow step
      FScroll.Enabled := True;  // turn the scroll bar on
      if FScroll.Position > MaxOffset then FScroll.Position := MaxOffset;  // keep the position in range
    end
    else
    begin
      FScroll.Position := 0;  // everything fits: back to the top
      FScroll.Enabled := False;  // turn the scroll bar off
    end;
  finally
    FScroll.OnChange := @ScrollChange;  // restore the scroll event
  end;
end;

{ Returns the largest scroll offset. }
function TPhotoView.MaxOffset: Integer;
begin
  Result := Max(0, FTotalH - ViewH);  // total height minus the visible height
end;

{ Returns the space above the cards (list header height in list view). }
function TPhotoView.TopPad: Integer;
begin
  if FMode = vmList then Result := FHdrH else Result := 0;  // header only in list view
end;

{ Returns the height of the card area. }
function TPhotoView.ViewH: Integer;
begin
  Result := ClientHeight - TopPad;  // client height minus the header
end;

{ Returns the current scroll offset in pixels. }
function TPhotoView.OffsetY: Integer;
begin
  if FScroll.Enabled then  // scrolling is on
    Result := EnsureRange(FScroll.Position, 0, MaxOffset)  // offset kept in range
  else
    Result := 0;  // no scrolling: top
end;

{ Scroll bar moved: redraw immediately. }
procedure TPhotoView.ScrollChange(Sender: TObject);
begin
  Repaint;      // draw the newly exposed rows straight away
end;

{ Timer tick: continues loading postponed thumbnails. }
procedure TPhotoView.LoadTimerTick(Sender: TObject);
begin
  FLoadTimer.Enabled := False;  // stop the timer
  Invalidate;   // continue loading the thumbnails postponed by the last paint
end;

{ Resize event: recomputes the layout. }
procedure TPhotoView.Resize;
begin
  inherited Resize;  // run the base handler
  if FScroll <> nil then  // scroll bar exists
  begin
    DoLayout;  // recompute card sizes
    Invalidate;  // redraw
  end;
end;

{ Returns the item index at pixel position (X, Y), or -1 if there is none. }
function TPhotoView.HitTest(X, Y: Integer): Integer;
var
  Row, Col: Integer;  // Row and Col: card position in the grid
begin
  Result := -1;  // assume nothing hit
  Y := Y - TopPad;  // move below the header
  if (X < 0) or (Y < 0) or (FCellH <= 0) or (FCellW <= 0) then Exit;  // outside the cards
  Col := X div FCellW;  // column number
  Row := (Y + OffsetY) div FCellH;  // row number including the scroll offset
  if Col >= FCols then Exit;  // beyond the last column
  Result := Row * FCols + Col;  // item index from row and column
  if Result >= FItems.Count then Result := -1;  // beyond the last item
end;

{ Scrolls so that the row of item Idx is fully visible. }
procedure TPhotoView.EnsureVisible(Idx: Integer);
var
  RowTop, RowBottom: Integer;  // RowTop and RowBottom: pixel range of the item's row
begin
  RowTop := 0;  // start values
  RowBottom := 0;  // start values
  if (Idx < 0) or (not FScroll.Enabled) then Exit;  // nothing to scroll
  RowTop := (Idx div FCols) * FCellH;  // top edge of the row
  RowBottom := RowTop + FCellH;  // bottom edge of the row
  if RowTop < OffsetY then  // row above the visible area
    FScroll.Position := RowTop  // scroll up to it
  else if RowBottom > OffsetY + ViewH then  // row below the visible area
    FScroll.Position := Min(MaxOffset, RowBottom - ViewH);  // scroll down until it is visible
end;

{ Shortens S from the left with '...' until it fits MaxW pixels. }
function TPhotoView.FitLeft(const S: string; MaxW: Integer): string;
var
  T: string;  // T: shortened text
  N: Integer;  // N: characters removed from the start plus one
begin
  if Canvas.TextWidth(S) <= MaxW then  // fits already
  begin
    Result := S;  // use as is
    Exit;  // done
  end;
  N := 1;  // start at the first character
  repeat
    T := '...' + Copy(S, N, MaxInt);  // '...' plus the end of the text
    Inc(N);  // next try removes one more character
  until (Canvas.TextWidth(T) <= MaxW) or (N > Length(S));  // stop when it fits or no text is left
  Result := T;  // use the result
end;

{ Draws the mark of a video: a play triangle and the length of the clip. With Tile a whole dark tile
  is painted (no frame is available); otherwise a black strip is drawn along the bottom of the
  frame in the rectangle X, Y, W, H. }
procedure DrawVideoMark(C: TCanvas; Item: TImageItem; X, Y, W, H: Integer; Tile: Boolean);
var
  S, CX, CY, TH: Integer;  // S: size of the triangle; CX, CY: its center; TH: height of the strip
  Txt: string;  // Txt: length of the clip as text
begin
  Txt := Item.DurationText;  // h:mm:ss, or empty when unknown
  if Tile then
  begin
    C.Brush.Style := bsSolid;  // solid fill
    C.Brush.Color := $00383838;  // dark gray tile
    C.Pen.Color := clGray;  // gray outline
    C.Rectangle(X, Y, X + W, Y + H);  // paint the tile
    S := Max(6, Min(W, H) div 3);  // triangle size
    CX := X + W div 2 - S div 6;  // nudge left so the triangle looks centered
    CY := Y + H div 2;  // vertical center
    C.Brush.Color := clWhite;  // white triangle
    C.Pen.Color := clWhite;  // white outline
    C.Polygon([Point(CX - S div 3, CY - S div 2), Point(CX - S div 3, CY + S div 2), Point(CX + S * 2 div 3, CY)]);  // play symbol
    C.Brush.Style := bsClear;  // no fill for the text
    C.Font.Color := clWhite;  // white text
    C.TextOut(X + 4, Y + 4, UpperCase(Copy(ExtractFileExt(Item.FileName), 2, 6)));  // file extension, top left
    if Txt <> '' then C.TextOut(X + W - C.TextWidth(Txt) - 4, Y + H - C.TextHeight(Txt) - 4, Txt);  // length, bottom right
  end
  else
  begin
    TH := C.TextHeight('0') + 2;  // height of the strip
    if H >= TH * 2 then  // only when the frame is large enough
    begin
      C.Brush.Style := bsSolid;  // solid fill
      C.Brush.Color := clBlack;  // black strip
      C.Pen.Color := clBlack;  // black outline
      C.FillRect(X, Y + H - TH, X + W, Y + H);  // paint the strip
      S := Max(4, TH - 6);  // triangle size
      CY := Y + H - TH div 2;  // vertical center of the strip
      C.Brush.Color := clWhite;  // white triangle
      C.Pen.Color := clWhite;  // white outline
      C.Polygon([Point(X + 4, CY - S div 2), Point(X + 4, CY + S div 2), Point(X + 4 + S, CY)]);  // play symbol
      C.Brush.Style := bsClear;  // no fill for the text
      C.Font.Color := clWhite;  // white text
      if Txt <> '' then C.TextOut(X + W - C.TextWidth(Txt) - 4, Y + H - TH + 1, Txt);  // length, right aligned
    end;
  end;
  C.Brush.Style := bsSolid;  // restore the fill
  C.Font.Color := clBlack;  // restore the text color
  C.Pen.Color := clGray;  // restore the outline color
end;

{ Draws the default tile of an audio file: a dark tile with a music note, the extension and the size. }
procedure DrawAudioTile(C: TCanvas; Item: TImageItem; X, Y, W, H: Integer);
var
  S, CX, CY: Integer;  // S: size of the note; CX, CY: center of the tile
  Txt: string;  // Txt: file size as text
begin
  C.Brush.Style := bsSolid;  // solid fill
  C.Brush.Color := $00503C28;  // dark blue tile
  C.Pen.Color := clGray;  // gray outline
  C.Rectangle(X, Y, X + W, Y + H);  // paint the tile
  S := Max(10, Min(W, H) div 2);  // size of the note
  CX := X + W div 2;  // horizontal center
  CY := Y + H div 2;  // vertical center
  C.Brush.Color := clWhite;  // white note
  C.Pen.Color := clWhite;  // white lines
  C.Ellipse(CX - S div 3, CY + S div 6, CX + S div 12, CY + S div 2);  // note head
  C.Pen.Width := Max(2, S div 12);  // stem thickness
  C.MoveTo(CX + S div 12 - 1, CY + S div 3);  // bottom of the stem
  C.LineTo(CX + S div 12 - 1, CY - S div 2);  // top of the stem
  C.LineTo(CX + S div 3, CY - S div 4);  // flag
  C.Pen.Width := 1;  // restore the pen width
  C.Brush.Style := bsClear;  // no fill for the text
  C.Font.Color := clWhite;  // white text
  C.TextOut(X + 4, Y + 4, UpperCase(Copy(ExtractFileExt(Item.FileName), 2, 6)));  // file extension, top left
  Txt := Item.SizeText;  // file size
  C.TextOut(X + W - C.TextWidth(Txt) - 4, Y + H - C.TextHeight(Txt) - 4, Txt);  // size, bottom right
  C.Brush.Style := bsSolid;  // restore the fill
  C.Font.Color := clBlack;  // restore the text color
  C.Pen.Color := clGray;  // restore the outline color
end;

{ Draws a picture's thumbnail (loading it if allowed) or a gray placeholder with its extension. }
procedure TPhotoView.DrawThumb(Item: TImageItem; X, Y: Integer);
var
  W, H: Integer;  // W and H: size to draw
begin
  if (Item.Thumb = nil) and (not Item.ThumbTried) then  // not loaded and not tried yet
  begin
    // decode only a few thumbnails per paint so scrolling stays responsive;
    // the rest are picked up by the timer
    if FLoadBudget > 0 then  // still allowed to load in this paint
    begin
      Dec(FLoadBudget);  // use one load
      EnsureThumb(Item, 160);  // load the thumbnail
    end
    else
      FNeedMore := True;  // postpone to the next paint
  end;
  if Item.Thumb <> nil then  // a thumbnail exists
  begin
    W := Item.Thumb.Width;  // its width
    H := Item.Thumb.Height;  // its height
    if (W > FThumbBox) or (H > FThumbBox) then  // larger than the box
    begin
      if W >= H then  // landscape
      begin
        H := Max(1, H * FThumbBox div W);  // scaled height
        W := FThumbBox;  // box width
      end
      else
      begin
        W := Max(1, W * FThumbBox div H);  // scaled width
        H := FThumbBox;  // box height
      end;
    end;
    if (W > 0) and (H > 0) then  // something to draw
    begin
      Canvas.StretchDraw(Rect(X, Y, X + W, Y + H), Item.Thumb);  // draw the thumbnail
      // thin frame so an almost white photo is still recognizable as a thumbnail
      Canvas.Brush.Style := bsClear;  // no fill for the frame
      Canvas.Pen.Color := clGray;  // gray frame
      Canvas.Rectangle(X - 1, Y - 1, X + W + 1, Y + H + 1);  // draw the frame
      Canvas.Brush.Style := bsSolid;  // restore the fill
      if Item.IsVideo then DrawVideoMark(Canvas, Item, X, Y, W, H, False);  // play mark and length on the frame
    end;
  end
  else if Item.IsAudio then
    DrawAudioTile(Canvas, Item, X, Y, FThumbBox * 3 div 4, FThumbBox * 2 div 3)  // default audio tile
  else if Item.IsVideo then
    DrawVideoMark(Canvas, Item, X, Y, FThumbBox * 3 div 4, FThumbBox * 2 div 3, True)  // no frame: video tile instead of the gray box
  else
  begin
    // placeholder for raw files / unreadable images
    Canvas.Brush.Color := $00D2D2D2;       // gray: no preview available (or not loaded yet)
    Canvas.Pen.Color := clGray;  // gray outline
    Canvas.Rectangle(X, Y, X + FThumbBox * 3 div 4, Y + FThumbBox * 2 div 3);  // draw the placeholder rectangle
    if Item.ThumbTried then  // rendering was tried and failed: cross out the box
    begin
      Canvas.Pen.Color := clRed;  // red cross
      Canvas.Pen.Width := 2;  // thick enough to see
      Canvas.MoveTo(X + 1, Y + 1);  // top left corner
      Canvas.LineTo(X + FThumbBox * 3 div 4 - 1, Y + FThumbBox * 2 div 3 - 1);  // to the bottom right corner
      Canvas.MoveTo(X + FThumbBox * 3 div 4 - 1, Y + 1);  // top right corner
      Canvas.LineTo(X + 1, Y + FThumbBox * 2 div 3 - 1);  // to the bottom left corner
      Canvas.Pen.Width := 1;  // restore the pen width
      Canvas.Pen.Color := clGray;  // restore the pen color
    end;
    Canvas.Brush.Style := bsClear;  // no fill for the text
    Canvas.Font.Color := clBlack;  // black text
    Canvas.TextOut(X + 4, Y + 4, UpperCase(Copy(ExtractFileExt(Item.FileName), 2, 6)));  // show the file extension
    Canvas.Brush.Style := bsSolid;  // restore the fill
  end;
end;

{ Draws one card (or list row): background by status, thumbnail and text lines. }
procedure TPhotoView.DrawItem(Item: TImageItem; const R: TRect);
var
  Inner: TRect;  // Inner: card area without the border
  Bg: TColor;  // Bg: background color
  TX, TY, Y, MaxW: Integer;  // TX and TY: thumbnail position, Y: text line position, MaxW: right text limit
  Line1, Line2, Line3: string;  // the three text lines of a card

  { Draws one text line clipped to the area between X and Right. }
  procedure Txt(X, YY, Right: Integer; const S: string);
  begin
    Canvas.TextRect(Rect(X, YY, Right, YY + FLineH), X, YY, S);  // clip and draw the text
  end;

begin
  Inner := Rect(R.Left, R.Top, R.Right - 1, R.Bottom - 1);  // area inside the card
  if Item.IsProblem then  // picture has a problem
    if Item.Selected then Bg := ColSelProblem else Bg := ColProblem  // choose the problem color
  else if Item.Status = isDuplicate then  // duplicate of another file
    if Item.Selected then Bg := ColSelDuplicate else Bg := ColDuplicate  // choose the duplicate color
  else if Item.Status = isDownloaded then  // already downloaded
    if Item.Selected then Bg := ColSelDownloaded else Bg := ColDownloaded  // choose the downloaded color
  else
    if Item.Selected then Bg := ColSelected else Bg := ColNormal;  // choose the normal color
  Canvas.Brush.Style := bsSolid;  // solid fill
  Canvas.Brush.Color := Bg;  // fill color
  Canvas.Pen.Color := Bg;  // outline color
  Canvas.FillRect(Inner);  // paint the background
  Canvas.Font.Color := clBlack;  // black text

  Line1 := Format('%d) %s (%s)', [Item.Index, Item.FileName, Item.SizeText]);  // name, number and size
  Line2 := FormatDateTime('mm"/"dd"/"yy hh":"nn":"ss', Item.CaptureTime);  // capture date and time
  Line3 := 'Status: ' + Item.StatusText;  // status text

  if FMode = vmList then  // list view
  begin
    Y := Inner.Top + 1;  // text line position
    Txt(Inner.Left + 4, Y, Min(Inner.Left + 330, Inner.Right), Line1);  // file name and size
    Txt(Inner.Left + 336, Y, Inner.Left + 456, Line2);  // capture time
    Txt(Inner.Left + 462, Y, Inner.Left + 580, Item.StatusText);  // status
    Txt(Inner.Left + 586, Y, Inner.Left + 720, Item.Camera);  // camera
    if Inner.Right > Inner.Left + 726 then  // room for the destination
      Txt(Inner.Left + 726, Y, Inner.Right - 2,  // destination path, shortened from the left
        FitLeft(Item.DestPath, Inner.Right - Inner.Left - 730));
  end
  else
  begin
    TX := Inner.Left + 3;  // text and thumbnail start
    TY := Inner.Top + 3;  // top of the thumbnail
    DrawThumb(Item, TX, TY);  // draw the thumbnail
    Canvas.Brush.Color := Bg;  // restore the card colors
    Canvas.Pen.Color := Bg;  // restore the card colors
    Canvas.Font.Color := clBlack;  // black text
    MaxW := Inner.Right - 2;  // right limit of the text
    Y := TY;  // first text line position
    Txt(TX + FThumbBox + 4, Y, MaxW, Line1);  // line 1: number, name and size
    Txt(TX + FThumbBox + 4, Y + FLineH, MaxW, Line2);  // line 2: capture time
    Txt(TX + FThumbBox + 4, Y + FLineH * 2, MaxW, Line3);  // line 3: status
    Txt(TX + FThumbBox + 4, Y + FLineH * 3, MaxW, Item.Camera);  // line 4: camera
    Y := Inner.Bottom - FLineH - 1;  // last line sits at the bottom of the card
    Txt(Inner.Left + 2, Y, MaxW, FitLeft(Item.DestPath, MaxW - Inner.Left - 2));  // destination path
  end;
end;

const
  HdrLeft: array[0..4] of Integer = (4, 336, 462, 586, 726);  // left edge of each list column
  HdrText: array[0..4] of string = ('File', 'Captured', 'Status', 'Camera', 'Destination');  // heading of each list column

{ Returns the list column under pixel position X, or -1. }
function TPhotoView.HeaderCol(X: Integer): Integer;
var
  I: Integer;  // I: column index
begin
  Result := -1;  // none yet
  for I := 0 to 4 do  // check every column
    if X >= HdrLeft[I] - 4 then Result := I;  // the last column that starts before X wins
end;

{ Draws the list column headings with separators and a sort arrow. }
procedure TPhotoView.DrawHeader;
var
  I, Right, TW, AX, AY: Integer;  // I: column, Right: right edge of the heading, TW: text width, AX and AY: sort arrow position
begin
  Canvas.Brush.Style := bsSolid;  // solid fill
  Canvas.Brush.Color := clBtnFace;  // header color
  Canvas.Pen.Color := clBtnFace;  // header outline color
  Canvas.FillRect(Rect(0, 0, ClientWidth - FScroll.Width, FHdrH));  // paint the header band
  Canvas.Pen.Color := clBtnShadow;  // line color
  Canvas.MoveTo(0, FHdrH - 1);  // start of the bottom line
  Canvas.LineTo(ClientWidth - FScroll.Width, FHdrH - 1);  // draw the bottom line
  Canvas.Font.Color := clBtnText;  // header text color
  for I := 0 to 4 do  // each column
  begin
    if I < 4 then Right := HdrLeft[I + 1] - 4 else Right := ClientWidth - FScroll.Width;  // right edge of this heading
    if HdrLeft[I] > ClientWidth - FScroll.Width then Break;  // column starts outside the visible width: stop
    if I > 0 then  // not the first column
    begin
      Canvas.Pen.Color := clBtnShadow;  // separator color
      Canvas.MoveTo(HdrLeft[I] - 4, 2);  // start of the separator
      Canvas.LineTo(HdrLeft[I] - 4, FHdrH - 3);  // draw the separator
    end;
    Canvas.Brush.Style := bsClear;  // no fill for the text
    Canvas.TextRect(Rect(HdrLeft[I], 0, Right - 2, FHdrH - 1), HdrLeft[I], 3, HdrText[I]);  // draw the heading text
    if I = FSortCol then  // this is the sorted column
    begin
      TW := Canvas.TextWidth(HdrText[I]);  // width of the heading
      AX := HdrLeft[I] + TW + 10;  // arrow position right of the text
      AY := FHdrH div 2;  // arrow vertical center
      if AX + 6 < Right then  // the arrow fits
      begin
        Canvas.Brush.Style := bsSolid;  // solid fill for the arrow
        Canvas.Brush.Color := clBtnShadow;  // arrow color
        Canvas.Pen.Color := clBtnShadow;  // arrow outline color
        if FSortDesc then  // descending
          Canvas.Polygon([Point(AX - 4, AY - 2), Point(AX + 4, AY - 2), Point(AX, AY + 3)])  // arrow pointing down
        else
          Canvas.Polygon([Point(AX - 4, AY + 2), Point(AX + 4, AY + 2), Point(AX, AY - 3)]);  // arrow pointing up
      end;
    end;
  end;
  Canvas.Brush.Style := bsSolid;  // restore the solid fill
end;

{ Paints the grid: background, visible cards, focus frame and header. }
procedure TPhotoView.Paint;
var
  Y0, FirstRow, LastRow, Row, Col, I: Integer;  // Y0: scroll offset, FirstRow and LastRow: visible rows, Row, Col and I: current card
  R: TRect;  // R: area of the current card
begin
  if not FLaidOut then DoLayout;  // compute the layout if it has not been done
  FLoadBudget := 6;  // up to six thumbnails may be decoded in this paint
  FNeedMore := False;  // nothing postponed yet
  Canvas.Brush.Color := clWindow;  // white background
  Canvas.FillRect(ClientRect);  // clear everything
  if (FItems.Count = 0) or (FCellH <= 0) then  // nothing to draw
  begin
    if FMode = vmList then DrawHeader;  // list header only
    Exit;  // done
  end;
  Y0 := OffsetY;  // scroll offset
  FirstRow := Y0 div FCellH;  // first visible row
  LastRow := (Y0 + ViewH) div FCellH;  // last visible row
  for Row := FirstRow to LastRow do  // each visible row
    for Col := 0 to FCols - 1 do  // each column
    begin
      I := Row * FCols + Col;  // item number
      if I >= FItems.Count then Break;  // past the last item
      R := Rect(Col * FCellW, Row * FCellH - Y0 + TopPad, (Col + 1) * FCellW, (Row + 1) * FCellH - Y0 + TopPad);  // card area on screen
      if FItems[I] <> nil then  // valid item
        DrawItem(TImageItem(FItems[I]), R);  // draw the card
      if Focused and (I = FFocusIdx) then  // focused card
      begin
        Canvas.Brush.Style := bsClear;  // no fill for the frame
        Canvas.Pen.Color := clHighlight;  // highlight color
        Canvas.Rectangle(R.Left, R.Top, R.Right - 1, R.Bottom - 1);  // draw the focus frame
      end;
    end;
  if FMode = vmList then DrawHeader;      // drawn last so scrolled rows slide under it
  if FNeedMore then  // thumbnails were postponed
  begin
    FLoadTimer.Enabled := False;  // restart the timer
    FLoadTimer.Enabled := True;  // so the next paint loads more
  end;
end;

{ Selects item Idx following the Shift (range) and Ctrl (toggle) rules. }
procedure TPhotoView.SelectIndex(Idx: Integer; Shift: TShiftState);
var
  I, A, B: Integer;  // I: loop index, A and B: range ends
begin
  if (Idx < 0) or (Idx >= FItems.Count) then Exit;  // invalid index
  if ssShift in Shift then  // Shift: select a range from the anchor
  begin
    if FAnchor < 0 then FAnchor := Idx;  // first Shift click: anchor here
    A := Min(FAnchor, Idx);  // lower end of the range
    B := Max(FAnchor, Idx);  // upper end of the range
    if not (ssCtrl in Shift) then  // without Ctrl the old selection is cleared
      for I := 0 to FItems.Count - 1 do
        TImageItem(FItems[I]).Selected := False;  // deselect each item
    for I := A to B do  // select the range
      TImageItem(FItems[I]).Selected := True;  // select each item
  end
  else if ssCtrl in Shift then  // Ctrl: toggle one item
  begin
    with TImageItem(FItems[Idx]) do Selected := not Selected;  // flip its selection
    FAnchor := Idx;  // new anchor
  end
  else
  begin
    for I := 0 to FItems.Count - 1 do  // plain click: clear the selection
      TImageItem(FItems[I]).Selected := False;  // deselect each item
    TImageItem(FItems[Idx]).Selected := True;  // select this item
    FAnchor := Idx;  // new anchor
  end;
  FFocusIdx := Idx;  // focus follows the click
  EnsureVisible(Idx);  // scroll it into view
  SelectionChanged;  // redraw and notify
end;

{ Mouse button pressed: sorts by a heading, selects a card, or clears the selection. }
procedure TPhotoView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx, I: Integer;  // Idx: item or column index, I: loop index
begin
  inherited MouseDown(Button, Shift, X, Y);  // run the base handler
  FLastX := X;  // remember the position for double-click
  FLastY := Y;  // remember the position for double-click
  FLastButton := Button;  // remember the button for double-click
  if CanFocus then SetFocus;  // take the keyboard focus
  if (FMode = vmList) and (Y < FHdrH) then  // click on the list heading
  begin
    // click on the column headings: sort by that column
    if (Button = mbLeft) and Assigned(FOnHeaderClick) then  // left button with a handler
    begin
      Idx := HeaderCol(X);  // column at that position
      if Idx >= 0 then FOnHeaderClick(Self, Idx);  // tell the owner to sort
    end;
    Exit;  // done
  end;
  if Button = mbRight then  // right button
  begin
    // select the clicked image (unless it is already part of the selection);
    // the popup menu then acts on the selection
    Idx := HitTest(X, Y);  // item under the pointer
    if (Idx >= 0) and (not TImageItem(FItems[Idx]).Selected) then  // not already selected
      SelectIndex(Idx, []);  // select just this item
    Exit;  // done
  end;
  if Button <> mbLeft then Exit;  // other buttons do nothing
  Idx := HitTest(X, Y);  // item under the pointer
  if Idx >= 0 then  // clicked on a card
    SelectIndex(Idx, Shift)  // select it with the Shift/Ctrl rules
  else if not (ssCtrl in Shift) then  // clicked empty space without Ctrl
  begin
    for I := 0 to FItems.Count - 1 do  // deselect all
      TImageItem(FItems[I]).Selected := False;  // deselect each item
    SelectionChanged;  // redraw and notify
  end;
end;

{ Double-click: opens the clicked item through the OnOpenItem event. }
procedure TPhotoView.DblClick;
var
  Idx: Integer;  // Idx: item index
begin
  inherited DblClick;  // run the base handler
  if (FLastButton <> mbLeft) or (not Assigned(FOnOpenItem)) then Exit;  // only the left button, and only with a handler
  Idx := HitTest(FLastX, FLastY);  // item under the last click
  if Idx >= 0 then FOnOpenItem(Self, Idx);  // open it
end;

{ Keyboard: arrows, Home, End, Page Up/Down move the focus; Space toggles selection. }
procedure TPhotoView.KeyDown(var Key: Word; Shift: TShiftState);
var
  N, PageRows: Integer;  // N: new focus index, PageRows: rows per page
begin
  inherited KeyDown(Key, Shift);  // run the base handler
  if FItems.Count = 0 then Exit;  // nothing to navigate
  N := FFocusIdx;  // current focus
  if N < 0 then N := 0;  // start at the first item
  PageRows := Max(1, ViewH div Max(1, FCellH));  // rows per page
  case Key of
    VK_LEFT: Dec(N);  // one left
    VK_RIGHT: Inc(N);  // one right
    VK_UP: Dec(N, FCols);  // one row up
    VK_DOWN: Inc(N, FCols);  // one row down
    VK_HOME: N := 0;  // first item
    VK_END: N := FItems.Count - 1;  // last item
    VK_PRIOR: Dec(N, FCols * PageRows);  // page up
    VK_NEXT: Inc(N, FCols * PageRows);  // page down
    VK_SPACE:
      begin
        SelectIndex(N, Shift + [ssCtrl]);  // toggle selection of the focused item
        Key := 0;  // key handled
        Exit;  // done
      end;
  else
    Exit;  // other keys are left alone
  end;
  N := EnsureRange(N, 0, FItems.Count - 1);  // keep the index in range
  SelectIndex(N, Shift);  // move the focus and select
  Key := 0;  // key handled
end;

{ Mouse wheel: scrolls by whole rows. }
function TPhotoView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);  // let the base class try first
  if Result then Exit;  // already handled
  Result := True;  // report it as handled
  if FScroll.Enabled then  // scrolling is on
    FScroll.Position := EnsureRange(FScroll.Position - (WheelDelta div 120) * FCellH, 0, MaxOffset);  // scroll by rows, kept in range
end;

end.
