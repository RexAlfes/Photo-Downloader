unit uPhotoView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, StdCtrls, ExtCtrls, Forms, LCLType, uItems;

type
  TViewMode = (vmList, vmSmall, vmLarge);
  TOpenItemEvent = procedure(Sender: TObject; Index: Integer) of object;

  { TPhotoView - scrolling grid of image cards (or a one-line-per-image list) }
  TPhotoView = class(TCustomControl)
  private
    FItems: TList;                  // visible items, not owned
    FMode: TViewMode;
    FScroll: TScrollBar;
    FCellW, FCellH, FCols, FLineH, FThumbBox, FTotalH: Integer;
    FFocusIdx, FAnchor: Integer;
    FLaidOut: Boolean;
    FLoadBudget: Integer;           // thumbnails that may still be decoded in this paint
    FNeedMore: Boolean;             // some thumbnails were postponed to the next paint
    FLoadTimer: TTimer;
    FOnSelChange: TNotifyEvent;
    FOnOpenItem: TOpenItemEvent;
    FLastX, FLastY: Integer;
    FLastButton: TMouseButton;
    procedure ScrollChange(Sender: TObject);
    procedure LoadTimerTick(Sender: TObject);
    procedure DoLayout;
    function OffsetY: Integer;
    function MaxOffset: Integer;
    function HitTest(X, Y: Integer): Integer;
    procedure DrawItem(Item: TImageItem; const R: TRect);
    procedure DrawThumb(Item: TImageItem; X, Y: Integer);
    function FitLeft(const S: string; MaxW: Integer): string;
    procedure SetMode(AValue: TViewMode);
    procedure SelectIndex(Idx: Integer; Shift: TShiftState);
    procedure EnsureVisible(Idx: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetItems(const L: TList);
    procedure SelectionChanged;
    procedure ScrollToItem(Item: TImageItem);
    property Mode: TViewMode read FMode write SetMode;
    property OnSelectionChange: TNotifyEvent read FOnSelChange write FOnSelChange;
    property OnOpenItem: TOpenItemEvent read FOnOpenItem write FOnOpenItem;
  end;

implementation

const
  ColNormal = $00EBEBEF;      // BGR of RGB(239,235,235)
  ColProblem = $006060FF;     // RGB(255,96,96)
  ColSelected = $00FAD7BE;    // RGB(190,215,250)
  ColSelProblem = $009664EB;  // RGB(235,100,150)

constructor TPhotoView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
  FMode := vmSmall;
  FFocusIdx := -1;
  FAnchor := -1;
  FLineH := 15;
  TabStop := True;
  Color := clWindow;
  ControlStyle := ControlStyle + [csOpaque];   // paint covers everything; avoids flicker
  FScroll := TScrollBar.Create(Self);
  FScroll.Parent := Self;
  FScroll.Kind := sbVertical;
  FScroll.Align := alRight;
  FScroll.TabStop := False;
  FScroll.OnChange := @ScrollChange;
  FLoadTimer := TTimer.Create(Self);
  FLoadTimer.Enabled := False;
  FLoadTimer.Interval := 15;
  FLoadTimer.OnTimer := @LoadTimerTick;
end;

destructor TPhotoView.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TPhotoView.SetMode(AValue: TViewMode);
begin
  if FMode = AValue then Exit;
  FMode := AValue;
  FScroll.Position := 0;
  DoLayout;
  Invalidate;
end;

procedure TPhotoView.SetItems(const L: TList);
var
  I: Integer;
begin
  FItems.Clear;
  for I := 0 to L.Count - 1 do
    FItems.Add(L[I]);
  FFocusIdx := -1;
  FAnchor := -1;
  DoLayout;
  Invalidate;
end;

procedure TPhotoView.ScrollToItem(Item: TImageItem);
begin
  EnsureVisible(FItems.IndexOf(Item));
  Invalidate;
end;

procedure TPhotoView.SelectionChanged;
begin
  Invalidate;
  if Assigned(FOnSelChange) then FOnSelChange(Self);
end;

procedure TPhotoView.DoLayout;
var
  W, Rows: Integer;
begin
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    FLineH := Canvas.TextHeight('Ag') + 1;
    FLaidOut := True;
  end;
  W := ClientWidth - FScroll.Width;
  if W < 60 then W := 60;
  case FMode of
    vmList:
      begin
        FCellW := W;
        FCellH := FLineH + 4;
      end;
    vmSmall:
      begin
        FThumbBox := 64;
        FCellW := 200;
        FCellH := FLineH * 5 + 10;
      end;
  else
    begin
      FThumbBox := 160;
      FCellW := 340;
      FCellH := FThumbBox + FLineH + 12;
    end;
  end;
  if FMode = vmList then FCols := 1 else FCols := Max(1, W div FCellW);
  Rows := (FItems.Count + FCols - 1) div FCols;
  FTotalH := Rows * FCellH;

  FScroll.OnChange := nil;
  try
    if FTotalH > ClientHeight then
    begin
      FScroll.Min := 0;
      FScroll.Max := FTotalH;
      FScroll.PageSize := Max(1, ClientHeight);
      FScroll.LargeChange := Max(1, ClientHeight);
      FScroll.SmallChange := Max(1, FCellH div 2);
      FScroll.Enabled := True;
      if FScroll.Position > MaxOffset then FScroll.Position := MaxOffset;
    end
    else
    begin
      FScroll.Position := 0;
      FScroll.Enabled := False;
    end;
  finally
    FScroll.OnChange := @ScrollChange;
  end;
end;

function TPhotoView.MaxOffset: Integer;
begin
  Result := Max(0, FTotalH - ClientHeight);
end;

function TPhotoView.OffsetY: Integer;
begin
  if FScroll.Enabled then
    Result := EnsureRange(FScroll.Position, 0, MaxOffset)
  else
    Result := 0;
end;

procedure TPhotoView.ScrollChange(Sender: TObject);
begin
  Repaint;      // draw the newly exposed rows straight away
end;

procedure TPhotoView.LoadTimerTick(Sender: TObject);
begin
  FLoadTimer.Enabled := False;
  Invalidate;   // continue loading the thumbnails postponed by the last paint
end;

procedure TPhotoView.Resize;
begin
  inherited Resize;
  if FScroll <> nil then
  begin
    DoLayout;
    Invalidate;
  end;
end;

function TPhotoView.HitTest(X, Y: Integer): Integer;
var
  Row, Col: Integer;
begin
  Result := -1;
  if (X < 0) or (Y < 0) or (FCellH <= 0) or (FCellW <= 0) then Exit;
  Col := X div FCellW;
  Row := (Y + OffsetY) div FCellH;
  if Col >= FCols then Exit;
  Result := Row * FCols + Col;
  if Result >= FItems.Count then Result := -1;
end;

procedure TPhotoView.EnsureVisible(Idx: Integer);
var
  RowTop, RowBottom: Integer;
begin
  RowTop := 0;
  RowBottom := 0;
  if (Idx < 0) or (not FScroll.Enabled) then Exit;
  RowTop := (Idx div FCols) * FCellH;
  RowBottom := RowTop + FCellH;
  if RowTop < OffsetY then
    FScroll.Position := RowTop
  else if RowBottom > OffsetY + ClientHeight then
    FScroll.Position := Min(MaxOffset, RowBottom - ClientHeight);
end;

function TPhotoView.FitLeft(const S: string; MaxW: Integer): string;
var
  T: string;
  N: Integer;
begin
  if Canvas.TextWidth(S) <= MaxW then
  begin
    Result := S;
    Exit;
  end;
  N := 1;
  repeat
    T := '...' + Copy(S, N, MaxInt);
    Inc(N);
  until (Canvas.TextWidth(T) <= MaxW) or (N > Length(S));
  Result := T;
end;

procedure TPhotoView.DrawThumb(Item: TImageItem; X, Y: Integer);
var
  W, H: Integer;
begin
  if (Item.Thumb = nil) and (not Item.ThumbTried) then
  begin
    // decode only a few thumbnails per paint so scrolling stays responsive;
    // the rest are picked up by the timer
    if FLoadBudget > 0 then
    begin
      Dec(FLoadBudget);
      EnsureThumb(Item, 160);
    end
    else
      FNeedMore := True;
  end;
  if Item.Thumb <> nil then
  begin
    W := Item.Thumb.Width;
    H := Item.Thumb.Height;
    if (W > FThumbBox) or (H > FThumbBox) then
    begin
      if W >= H then
      begin
        H := Max(1, H * FThumbBox div W);
        W := FThumbBox;
      end
      else
      begin
        W := Max(1, W * FThumbBox div H);
        H := FThumbBox;
      end;
    end;
    if (W > 0) and (H > 0) then
    begin
      Canvas.StretchDraw(Rect(X, Y, X + W, Y + H), Item.Thumb);
      // thin frame so an almost white photo is still recognisable as a thumbnail
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := clGray;
      Canvas.Rectangle(X - 1, Y - 1, X + W + 1, Y + H + 1);
      Canvas.Brush.Style := bsSolid;
    end;
  end
  else
  begin
    // placeholder for raw files / unreadable images
    Canvas.Brush.Color := $00D2D2D2;       // grey: no preview available (or not loaded yet)
    Canvas.Pen.Color := clGray;
    Canvas.Rectangle(X, Y, X + FThumbBox * 3 div 4, Y + FThumbBox * 2 div 3);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clBlack;
    Canvas.TextOut(X + 4, Y + 4, UpperCase(Copy(ExtractFileExt(Item.FileName), 2, 6)));
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TPhotoView.DrawItem(Item: TImageItem; const R: TRect);
var
  Inner: TRect;
  Bg: TColor;
  TX, TY, Y, MaxW: Integer;
  Line1, Line2, Line3: string;

  procedure Txt(X, YY, Right: Integer; const S: string);
  begin
    Canvas.TextRect(Rect(X, YY, Right, YY + FLineH), X, YY, S);
  end;

begin
  Inner := Rect(R.Left, R.Top, R.Right - 1, R.Bottom - 1);
  if Item.IsProblem then
    if Item.Selected then Bg := ColSelProblem else Bg := ColProblem
  else
    if Item.Selected then Bg := ColSelected else Bg := ColNormal;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Bg;
  Canvas.Pen.Color := Bg;
  Canvas.FillRect(Inner);
  Canvas.Font.Color := clBlack;

  Line1 := Format('%d) %s (%s)', [Item.Index, Item.FileName, Item.SizeText]);
  Line2 := FormatDateTime('mm"/"dd"/"yy hh":"nn":"ss', Item.CaptureTime);
  Line3 := 'Status: ' + Item.StatusText;

  if FMode = vmList then
  begin
    Y := Inner.Top + 1;
    Txt(Inner.Left + 4, Y, Min(Inner.Left + 330, Inner.Right), Line1);
    Txt(Inner.Left + 336, Y, Inner.Left + 456, Line2);
    Txt(Inner.Left + 462, Y, Inner.Left + 580, Item.StatusText);
    Txt(Inner.Left + 586, Y, Inner.Left + 720, Item.Camera);
    if Inner.Right > Inner.Left + 726 then
      Txt(Inner.Left + 726, Y, Inner.Right - 2,
        FitLeft(Item.DestPath, Inner.Right - Inner.Left - 730));
  end
  else
  begin
    TX := Inner.Left + 3;
    TY := Inner.Top + 3;
    DrawThumb(Item, TX, TY);
    Canvas.Brush.Color := Bg;
    Canvas.Pen.Color := Bg;
    Canvas.Font.Color := clBlack;
    MaxW := Inner.Right - 2;
    Y := TY;
    Txt(TX + FThumbBox + 4, Y, MaxW, Line1);
    Txt(TX + FThumbBox + 4, Y + FLineH, MaxW, Line2);
    Txt(TX + FThumbBox + 4, Y + FLineH * 2, MaxW, Line3);
    Txt(TX + FThumbBox + 4, Y + FLineH * 3, MaxW, Item.Camera);
    Y := Inner.Bottom - FLineH - 1;
    Txt(Inner.Left + 2, Y, MaxW, FitLeft(Item.DestPath, MaxW - Inner.Left - 2));
  end;
end;

procedure TPhotoView.Paint;
var
  Y0, FirstRow, LastRow, Row, Col, I: Integer;
  R: TRect;
begin
  if not FLaidOut then DoLayout;
  FLoadBudget := 6;
  FNeedMore := False;
  Canvas.Brush.Color := clWindow;
  Canvas.FillRect(ClientRect);
  if (FItems.Count = 0) or (FCellH <= 0) then Exit;
  Y0 := OffsetY;
  FirstRow := Y0 div FCellH;
  LastRow := (Y0 + ClientHeight) div FCellH;
  for Row := FirstRow to LastRow do
    for Col := 0 to FCols - 1 do
    begin
      I := Row * FCols + Col;
      if I >= FItems.Count then Break;
      R := Rect(Col * FCellW, Row * FCellH - Y0, (Col + 1) * FCellW, (Row + 1) * FCellH - Y0);
      if FItems[I] <> nil then
        DrawItem(TImageItem(FItems[I]), R);
      if Focused and (I = FFocusIdx) then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Pen.Color := clHighlight;
        Canvas.Rectangle(R.Left, R.Top, R.Right - 1, R.Bottom - 1);
      end;
    end;
  if FNeedMore then
  begin
    FLoadTimer.Enabled := False;
    FLoadTimer.Enabled := True;
  end;
end;

procedure TPhotoView.SelectIndex(Idx: Integer; Shift: TShiftState);
var
  I, A, B: Integer;
begin
  if (Idx < 0) or (Idx >= FItems.Count) then Exit;
  if ssShift in Shift then
  begin
    if FAnchor < 0 then FAnchor := Idx;
    A := Min(FAnchor, Idx);
    B := Max(FAnchor, Idx);
    if not (ssCtrl in Shift) then
      for I := 0 to FItems.Count - 1 do
        TImageItem(FItems[I]).Selected := False;
    for I := A to B do
      TImageItem(FItems[I]).Selected := True;
  end
  else if ssCtrl in Shift then
  begin
    with TImageItem(FItems[Idx]) do Selected := not Selected;
    FAnchor := Idx;
  end
  else
  begin
    for I := 0 to FItems.Count - 1 do
      TImageItem(FItems[I]).Selected := False;
    TImageItem(FItems[Idx]).Selected := True;
    FAnchor := Idx;
  end;
  FFocusIdx := Idx;
  EnsureVisible(Idx);
  SelectionChanged;
end;

procedure TPhotoView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx, I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  FLastX := X;
  FLastY := Y;
  FLastButton := Button;
  if CanFocus then SetFocus;
  if Button = mbRight then
  begin
    // select the clicked image (unless it is already part of the selection);
    // the popup menu then acts on the selection
    Idx := HitTest(X, Y);
    if (Idx >= 0) and (not TImageItem(FItems[Idx]).Selected) then
      SelectIndex(Idx, []);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  Idx := HitTest(X, Y);
  if Idx >= 0 then
    SelectIndex(Idx, Shift)
  else if not (ssCtrl in Shift) then
  begin
    for I := 0 to FItems.Count - 1 do
      TImageItem(FItems[I]).Selected := False;
    SelectionChanged;
  end;
end;

procedure TPhotoView.DblClick;
var
  Idx: Integer;
begin
  inherited DblClick;
  if (FLastButton <> mbLeft) or (not Assigned(FOnOpenItem)) then Exit;
  Idx := HitTest(FLastX, FLastY);
  if Idx >= 0 then FOnOpenItem(Self, Idx);
end;

procedure TPhotoView.KeyDown(var Key: Word; Shift: TShiftState);
var
  N, PageRows: Integer;
begin
  inherited KeyDown(Key, Shift);
  if FItems.Count = 0 then Exit;
  N := FFocusIdx;
  if N < 0 then N := 0;
  PageRows := Max(1, ClientHeight div Max(1, FCellH));
  case Key of
    VK_LEFT: Dec(N);
    VK_RIGHT: Inc(N);
    VK_UP: Dec(N, FCols);
    VK_DOWN: Inc(N, FCols);
    VK_HOME: N := 0;
    VK_END: N := FItems.Count - 1;
    VK_PRIOR: Dec(N, FCols * PageRows);
    VK_NEXT: Inc(N, FCols * PageRows);
    VK_SPACE:
      begin
        SelectIndex(N, Shift + [ssCtrl]);
        Key := 0;
        Exit;
      end;
  else
    Exit;
  end;
  N := EnsureRange(N, 0, FItems.Count - 1);
  SelectIndex(N, Shift);
  Key := 0;
end;

function TPhotoView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  Result := True;
  if FScroll.Enabled then
    FScroll.Position := EnsureRange(FScroll.Position - (WheelDelta div 120) * FCellH, 0, MaxOffset);
end;

end.
