unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Math, Forms, Controls, Graphics, Dialogs, Menus,
  ExtCtrls, StdCtrls, ComCtrls, LCLType, LCLIntf, LazFileUtils,
  uSettings, uItems, uExif, uVersion, uPhotoView, uDialogs, uDrives, uViewer, uSingle;

type
  TMainForm = class(TForm)
  private
    FS: TAppSettings;
    FItems: TObjectList;            // all images found on the source (owned)
    FVisible: TList;                // images currently shown (not owned)
    FDateKeys: TStringList;         // parallel to lstDates
    FSourcePath, FCamera, FLastFile, FLastDir: string;
    FSession: Integer;
    FCancel: Boolean;
    FSyncing: Boolean;              // true while list/grid selections are being mirrored
    FProg: TForm;
    FProgBar: TProgressBar;
    FProgLbl: TLabel;
    FTimer: TTimer;
    FPopup: TPopupMenu;
    miPopView, miPopLocation, miPopProps, miPopDownload, miPopDelete: TMenuItem;
    miAuto, miEject, miShowDown, miShowDup, miList, miSmall, miLarge, miDateSel: TMenuItem;
    pnlLeft, pnlStatus, pnlButtons: TPanel;
    lblDate, lblStatus: TLabel;
    lstDates: TListBox;
    splLeft: TSplitter;
    FView: TPhotoView;
    btnDownload, btnDelete, btnClose, btnCustom: TButton;
    // construction
    function AddMenu(AParent: TMenuItem; const Cap: string; H: TNotifyEvent;
      SC: TShortCut): TMenuItem;
    procedure BuildMenu;
    procedure BuildUI;
    procedure PlaceButton(B: TButton; Right: TControl; ASpace: Integer);
    // helpers
    procedure SaveSettingsNow;
    procedure ApplyState;
    procedure SetViewMode(M: Integer);
    procedure SetStatus(const S: string);
    procedure UpdateCaption;
    procedure UpdateMenus;
    procedure UpdateStatus;
    procedure ScanProgress(Count: Integer);
    procedure LoadSource(const Path: string);
    procedure AutoDetectSource;
    procedure Reevaluate;
    procedure RebuildDates;
    procedure ApplyFilter;
    procedure GetDownloadList(L: TList);
    procedure SelectWhere(Mode: Integer);
    function PostProcess(It: TImageItem; const Dest: string): Boolean;
    procedure SyncDateHighlight;
    procedure SelectDatesFromList;
    procedure ChangeJobCode;
    procedure PopupPopup(Sender: TObject);
    procedure PopDownloadClick(Sender: TObject);
    procedure PopViewClick(Sender: TObject);
    procedure PopLocationClick(Sender: TObject);
    procedure PopPropsClick(Sender: TObject);
    procedure OpenItem(Sender: TObject; Index: Integer);
    function CanDeleteSource(It: TImageItem): Boolean;
    procedure DateMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure WriteXmp(const Dest: string);
    procedure ShowProgress(AMax: Integer);
    procedure HideProgress;
    function DoDownload(Silent: Boolean): Boolean;
    procedure DeleteFiles(OnlyDownloaded, Silent: Boolean);
    function DoEject(Silent: Boolean): Boolean;
    procedure RunAutoSequence;
    procedure LaunchCustom;
    procedure AskJobCode;
    procedure ListProfiles(L: TStrings);
    // events
    procedure StartupTimer(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure DateSelChange(Sender: TObject; User: Boolean);
    procedure ViewSelChange(Sender: TObject);
    procedure ProgCancelClick(Sender: TObject);
    procedure OpenSourceClick(Sender: TObject);
    procedure ProfileLoadClick(Sender: TObject);
    procedure ProfileSaveClick(Sender: TObject);
    procedure ProfileDeleteClick(Sender: TObject);
    procedure StatusClick(Sender: TObject);
    procedure PrefsClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure AutoClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure EjectClick(Sender: TObject);
    procedure ExitClick(Sender: TObject);
    procedure SelAllClick(Sender: TObject);
    procedure SelDownClick(Sender: TObject);
    procedure SelROClick(Sender: TObject);
    procedure SelJpgClick(Sender: TObject);
    procedure SelNoneClick(Sender: TObject);
    procedure InvertClick(Sender: TObject);
    procedure IptcClick(Sender: TObject);
    procedure JobClick(Sender: TObject);
    procedure GpsClick(Sender: TObject);
    procedure ShowDownClick(Sender: TObject);
    procedure ShowDupClick(Sender: TObject);
    procedure ListViewClick(Sender: TObject);
    procedure SmallViewClick(Sender: TObject);
    procedure LargeViewClick(Sender: TObject);
    procedure DateSelClick(Sender: TObject);
    procedure HelpContentsClick(Sender: TObject);
    procedure WebsiteClick(Sender: TObject);
    procedure UpdatesClick(Sender: TObject);
    procedure RegisterClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure CustomClick(Sender: TObject);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{ ====================================================================== }
{ construction                                                            }
{ ====================================================================== }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);
  Caption := AppTitle + ' - no image source';
  Position := poScreenCenter;
  ClientWidth := 1100;
  ClientHeight := 700;
  FS := TAppSettings.Create;
  FS.LoadFromFile(SettingsFileName);
  FItems := TObjectList.Create(True);
  FVisible := TList.Create;
  FDateKeys := TStringList.Create;
  BuildMenu;
  BuildUI;
  ApplyState;
  OnClose := @FormClose;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 150;
  FTimer.OnTimer := @StartupTimer;
end;

destructor TMainForm.Destroy;
begin
  FVisible.Free;
  FDateKeys.Free;
  FItems.Free;
  FS.Free;
  inherited Destroy;
end;

function TMainForm.AddMenu(AParent: TMenuItem; const Cap: string; H: TNotifyEvent;
  SC: TShortCut): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := Cap;
  if Assigned(H) then Result.OnClick := H;
  if SC <> 0 then Result.ShortCut := SC;
  AParent.Add(Result);
end;

procedure TMainForm.BuildMenu;
var
  MM: TMainMenu;
  MFile, MEdit, MView, MHelp, MProf, Cam: TMenuItem;
begin
  MM := TMainMenu.Create(Self);
  Menu := MM;

  MFile := AddMenu(MM.Items, '&File', nil, 0);
  AddMenu(MFile, 'Open Source Folder', @OpenSourceClick, ShortCut(VK_O, [ssCtrl]));
  AddMenu(MFile, '-', nil, 0);
  MProf := AddMenu(MFile, 'User Profiles', nil, 0);
  AddMenu(MProf, 'Load', @ProfileLoadClick, 0);
  AddMenu(MProf, 'Save', @ProfileSaveClick, 0);
  AddMenu(MProf, 'Delete', @ProfileDeleteClick, 0);
  AddMenu(MFile, '-', nil, 0);
  Cam := AddMenu(MFile, 'Camera Settings', nil, ShortCut(VK_S, [ssCtrl]));
  Cam.Enabled := False;            // direct camera (PTP) control is not supported
  AddMenu(MFile, 'Status', @StatusClick, 0);
  AddMenu(MFile, 'Preferences', @PrefsClick, ShortCut(VK_P, [ssCtrl]));
  AddMenu(MFile, 'Export Settings', @ExportClick, 0);
  AddMenu(MFile, '-', nil, 0);
  miAuto := AddMenu(MFile, 'Start Auto Sequence', @AutoClick, ShortCut(VK_F4, []));
  AddMenu(MFile, 'Refresh', @RefreshClick, ShortCut(VK_F5, []));
  miEject := AddMenu(MFile, 'Eject', @EjectClick, ShortCut(VK_F6, []));
  AddMenu(MFile, '-', nil, 0);
  AddMenu(MFile, 'Exit', @ExitClick, 0);

  MEdit := AddMenu(MM.Items, '&Edit', nil, 0);
  AddMenu(MEdit, 'Select All', @SelAllClick, ShortCut(VK_A, [ssCtrl]));
  AddMenu(MEdit, 'Select Downloaded', @SelDownClick, ShortCut(VK_D, [ssCtrl]));
  AddMenu(MEdit, 'Select Read Only', @SelROClick, ShortCut(VK_R, [ssCtrl]));
  AddMenu(MEdit, 'Select JPEGs', @SelJpgClick, ShortCut(VK_J, [ssCtrl, ssShift]));
  AddMenu(MEdit, 'Select None', @SelNoneClick, ShortCut(VK_N, [ssCtrl]));
  AddMenu(MEdit, 'Invert Selection', @InvertClick, ShortCut(VK_I, [ssCtrl]));
  AddMenu(MEdit, '-', nil, 0);
  AddMenu(MEdit, 'IPTC/XMP Data..', @IptcClick, ShortCut(VK_C, [ssCtrl]));
  AddMenu(MEdit, 'Job Code', @JobClick, ShortCut(VK_J, [ssCtrl]));
  AddMenu(MEdit, '-', nil, 0);
  AddMenu(MEdit, 'GPS Settings', @GpsClick, 0);
  AddMenu(MEdit, 'Check GPS Track Log', nil, 0).Enabled := False;

  MView := AddMenu(MM.Items, '&View', nil, 0);
  miShowDown := AddMenu(MView, 'Show ''Downloaded'' files', @ShowDownClick, 0);
  miShowDup := AddMenu(MView, 'Show ''Duplicate'' files', @ShowDupClick, 0);
  AddMenu(MView, '-', nil, 0);
  miList := AddMenu(MView, 'List View', @ListViewClick, ShortCut(VK_L, [ssCtrl]));
  miSmall := AddMenu(MView, 'Thumbnail View (small thumbnails)', @SmallViewClick,
    ShortCut(VK_T, [ssCtrl]));
  miLarge := AddMenu(MView, 'Thumbnail View (large thumbnails)', @LargeViewClick,
    ShortCut(VK_X, [ssCtrl]));
  AddMenu(MView, '-', nil, 0);
  miDateSel := AddMenu(MView, 'Image Date Selector', @DateSelClick, ShortCut(VK_TAB, [ssCtrl]));

  MHelp := AddMenu(MM.Items, '&Help', nil, 0);
  AddMenu(MHelp, 'Contents', @HelpContentsClick, 0);
  AddMenu(MHelp, 'Getting Started', @HelpContentsClick, 0);
  AddMenu(MHelp, '-', nil, 0);
  AddMenu(MHelp, 'Visit website', @WebsiteClick, 0);
  AddMenu(MHelp, 'Check for updates', @UpdatesClick, 0);
  AddMenu(MHelp, 'Register', @RegisterClick, 0);
  AddMenu(MHelp, '-', nil, 0);
  AddMenu(MHelp, 'About Photo Downloader', @AboutClick, 0);
end;

procedure TMainForm.PlaceButton(B: TButton; Right: TControl; ASpace: Integer);
begin
  B.AutoSize := False;
  B.Width := 80;
  B.Height := 25;
  B.Anchors := [akTop, akRight];
  B.AnchorSideTop.Control := pnlButtons;
  B.AnchorSideTop.Side := asrTop;
  B.BorderSpacing.Top := 9;
  B.AnchorSideRight.Control := Right;
  if Right = pnlButtons then
    B.AnchorSideRight.Side := asrRight
  else
    B.AnchorSideRight.Side := asrLeft;
  B.BorderSpacing.Right := ASpace;
end;

procedure TMainForm.BuildUI;
begin
  // bottom: button row, then the status row above it
  pnlButtons := TPanel.Create(Self);
  pnlButtons.Parent := Self;
  pnlButtons.Align := alBottom;
  pnlButtons.Height := 44;
  pnlButtons.BevelOuter := bvNone;
  pnlButtons.Caption := '';

  pnlStatus := TPanel.Create(Self);
  pnlStatus.Parent := Self;
  pnlStatus.Align := alBottom;
  pnlStatus.Height := 26;
  pnlStatus.BevelOuter := bvLowered;
  pnlStatus.Caption := '';
  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlStatus;
  lblStatus.Align := alClient;
  lblStatus.Layout := tlCenter;
  lblStatus.BorderSpacing.Left := 6;
  lblStatus.Caption := 'No files';

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlButtons;
  btnClose.Caption := 'Close';
  btnClose.OnClick := @CloseClick;
  PlaceButton(btnClose, pnlButtons, 10);
  btnDelete := TButton.Create(Self);
  btnDelete.Parent := pnlButtons;
  btnDelete.Caption := 'Delete';
  btnDelete.OnClick := @DeleteClick;
  PlaceButton(btnDelete, btnClose, 8);
  btnDownload := TButton.Create(Self);
  btnDownload.Parent := pnlButtons;
  btnDownload.Caption := 'Download';
  btnDownload.OnClick := @DownloadClick;
  PlaceButton(btnDownload, btnDelete, 8);
  btnCustom := TButton.Create(Self);
  btnCustom.Parent := pnlButtons;
  btnCustom.Caption := 'C&ustom';
  btnCustom.OnClick := @CustomClick;
  PlaceButton(btnCustom, btnDownload, 8);

  // left: date selector
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 180;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.Caption := '';
  lblDate := TLabel.Create(Self);
  lblDate.Parent := pnlLeft;
  lblDate.Align := alTop;
  lblDate.Caption := 'Date - Job code:';
  lblDate.BorderSpacing.Around := 4;
  lstDates := TListBox.Create(Self);
  lstDates.Parent := pnlLeft;
  lstDates.Align := alClient;
  lstDates.MultiSelect := True;
  lstDates.BorderSpacing.Around := 4;
  lstDates.OnSelectionChange := @DateSelChange;
  lstDates.OnMouseDown := @DateMouseDown;

  splLeft := TSplitter.Create(Self);
  splLeft.Parent := Self;
  splLeft.Align := alLeft;
  splLeft.Left := pnlLeft.Width + 1;
  splLeft.ResizeStyle := rsUpdate;

  FView := TPhotoView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.BorderSpacing.Around := 4;
  FView.OnSelectionChange := @ViewSelChange;
  FView.OnOpenItem := @OpenItem;

  // right click on an image: act on the selected image(s)
  FPopup := TPopupMenu.Create(Self);
  FPopup.OnPopup := @PopupPopup;
  miPopView := AddMenu(FPopup.Items, 'View image', @PopViewClick, 0);
  miPopLocation := AddMenu(FPopup.Items, 'Open image location', @PopLocationClick, 0);
  miPopDownload := AddMenu(FPopup.Items, 'Download selected file(s)', @PopDownloadClick, 0);
  miPopDelete := AddMenu(FPopup.Items, 'Delete selected file(s) from source', @DeleteClick, 0);
  miPopProps := AddMenu(FPopup.Items, 'Properties', @PopPropsClick, 0);
  FView.PopupMenu := FPopup;
end;

{ ====================================================================== }
{ state                                                                   }
{ ====================================================================== }

procedure TMainForm.SaveSettingsNow;
begin
  try
    FS.SaveToFile(SettingsFileName);
  except
    // never let a read-only config folder stop the application
  end;
end;

procedure TMainForm.SetViewMode(M: Integer);
begin
  FS.ViewMode := M;
  FView.Mode := TViewMode(M);
  miList.Checked := M = 0;
  miSmall.Checked := M = 1;
  miLarge.Checked := M = 2;
end;

procedure TMainForm.ApplyState;
begin
  miShowDown.Checked := FS.ShowDownloaded;
  miShowDup.Checked := FS.ShowDuplicates;
  miDateSel.Checked := FS.ShowDateSelector;
  pnlLeft.Visible := FS.ShowDateSelector;
  splLeft.Visible := FS.ShowDateSelector;
  SetViewMode(FS.ViewMode);
  btnCustom.Visible := FS.CustomEnabled;
  btnCustom.Caption := FS.CustomCaption;
  UpdateMenus;
end;

procedure TMainForm.UpdateMenus;
begin
  miAuto.Enabled := FS.AutoMenu;
  miEject.Enabled := FSourcePath <> '';
end;

procedure TMainForm.SetStatus(const S: string);
begin
  lblStatus.Caption := S;
end;

procedure TMainForm.UpdateCaption;
begin
  if FSourcePath = '' then
    Caption := AppTitle + ' - no image source'
  else if ExcludeTrailingPathDelimiter(FSourcePath) = ExtractFileDrive(FSourcePath) then
    Caption := AppTitle + ' - Cardreader ' + FSourcePath
  else
    Caption := AppTitle + ' - Folder ' + FSourcePath;
end;

procedure TMainForm.ScanProgress(Count: Integer);
begin
  SetStatus(Format('Scanning... %d files found', [Count]));
  lblStatus.Repaint;      // no message pump here: the grid must not repaint mid-scan
end;

procedure TMainForm.UpdateStatus;
var
  L: TList;
  N, P, I: Integer;
  S: string;
begin
  if FItems.Count = 0 then
  begin
    SetStatus('No files');
    btnDownload.Enabled := False;
    btnDelete.Enabled := False;
    Exit;
  end;
  L := TList.Create;
  try
    GetDownloadList(L);
    N := L.Count;
    P := 0;
    for I := 0 to L.Count - 1 do
      if TImageItem(L[I]).IsProblem then Inc(P);
  finally
    L.Free;
  end;
  if N = 0 then
    S := 'No files to download.'
  else
  begin
    if N = 1 then S := '1 file to download' else S := Format('%d files to download', [N]);
    if P > 0 then
    begin
      if P = 1 then S := S + ' of which 1 is a problem file.'
      else S := S + Format(' of which %d are problem files.', [P]);
    end
    else
      S := S + '.';
  end;
  SetStatus(S);
  btnDownload.Enabled := N > 0;
  btnDelete.Enabled := False;
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Status = isDownloaded then
    begin
      btnDelete.Enabled := True;
      Break;
    end;
end;

{ ====================================================================== }
{ loading and filtering                                                   }
{ ====================================================================== }

procedure TMainForm.LoadSource(const Path: string);
var
  I: Integer;
begin
  FSourcePath := Path;
  FS.LastSource := Path;
  Screen.Cursor := crHourGlass;
  try
    // detach the grid and lists from the old images before they are freed
    FVisible.Clear;
    FView.SetItems(FVisible);
    FItems.Clear;
    RebuildDates;
    ScanFolder(Path, FS, FItems, @ScanProgress);
    FCamera := '';
    for I := 0 to FItems.Count - 1 do
      if ItemAt(FItems, I).Camera <> '' then
      begin
        FCamera := ItemAt(FItems, I).Camera;
        Break;
      end;
    EvaluateItems(FItems, FS);
    RebuildDates;
    ApplyFilter;
  finally
    Screen.Cursor := crDefault;
  end;
  UpdateCaption;
  UpdateMenus;
end;

procedure TMainForm.AutoDetectSource;
var
  L: TStringList;
  I: Integer;
  Root: string;
begin
  case FS.SourceMode of
    smCamera:
      begin
        SetStatus('Direct camera (PTP) download is not supported. ' +
          'Use a card reader or File > Open Source Directory.');
      end;
    smCardReader:
      for I := 1 to Length(FS.DriveLetters) do
        if FS.DriveLetters[I] in ['A'..'Z', 'a'..'z'] then
        begin
          Root := UpperCase(FS.DriveLetters[I]) + ':\';
          if DirectoryExistsUTF8(Root) then
          begin
            LoadSource(Root);
            Exit;
          end;
        end;
  else
    L := TStringList.Create;
    try
      ListRemovableDrives(L);
      for I := 0 to L.Count - 1 do
        if DirectoryExistsUTF8(L[I] + 'DCIM') then
        begin
          LoadSource(L[I]);
          Break;
        end;
    finally
      L.Free;
    end;
  end;
end;

procedure TMainForm.Reevaluate;
begin
  EvaluateItems(FItems, FS);
  RebuildDates;
  ApplyFilter;
end;

procedure TMainForm.RebuildDates;
var
  I: Integer;
  It: TImageItem;
begin
  lstDates.Items.BeginUpdate;
  try
    lstDates.Items.Clear;
    FDateKeys.Clear;
    for I := 0 to FItems.Count - 1 do
    begin
      It := ItemAt(FItems, I);
      if FDateKeys.IndexOf(It.DateKey) < 0 then
      begin
        FDateKeys.Add(It.DateKey);
        lstDates.Items.Add(It.DateKey + ' - ' + JobCodeFor(FS, It));
      end;
    end;
  finally
    lstDates.Items.EndUpdate;
  end;
end;

procedure TMainForm.ApplyFilter;
var
  I: Integer;
  It: TImageItem;
begin
  FVisible.Clear;
  for I := 0 to FItems.Count - 1 do
  begin
    It := ItemAt(FItems, I);
    if (It.Status = isDownloaded) and (not FS.ShowDownloaded) then Continue;
    if (It.Status = isDuplicate) and (not FS.ShowDuplicates) then Continue;
    FVisible.Add(It);
  end;
  FView.SetItems(FVisible);
  UpdateStatus;
  SyncDateHighlight;
end;

procedure TMainForm.GetDownloadList(L: TList);
var
  I: Integer;
  It: TImageItem;
  AnySel: Boolean;
begin
  AnySel := False;
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      AnySel := True;
      Break;
    end;
  for I := 0 to FVisible.Count - 1 do
  begin
    It := TImageItem(FVisible[I]);
    if AnySel and (not It.Selected) then Continue;
    if It.Status in [isNew, isNameClash] then L.Add(It);
  end;
end;

procedure TMainForm.DateSelChange(Sender: TObject; User: Boolean);
begin
  if User and (not FSyncing) then SelectDatesFromList;
end;

{ thumbnails -> date list: highlight every date that has a selected image }
procedure TMainForm.SyncDateHighlight;
var
  I, J: Integer;
  Keys: TStringList;
begin
  if FSyncing then Exit;
  FSyncing := True;
  Keys := TStringList.Create;
  try
    Keys.Sorted := True;
    Keys.Duplicates := dupIgnore;
    for I := 0 to FVisible.Count - 1 do
      if TImageItem(FVisible[I]).Selected then
        Keys.Add(TImageItem(FVisible[I]).DateKey);
    for J := 0 to lstDates.Items.Count - 1 do
      if J < FDateKeys.Count then
        lstDates.Selected[J] := Keys.IndexOf(FDateKeys[J]) >= 0;
  finally
    Keys.Free;
    FSyncing := False;
  end;
end;

{ date list -> thumbnails: select every image of the highlighted dates }
procedure TMainForm.SelectDatesFromList;
var
  I, J: Integer;
  Keys: TStringList;
  It, First: TImageItem;
begin
  FSyncing := True;
  Keys := TStringList.Create;
  try
    for J := 0 to lstDates.Items.Count - 1 do
      if lstDates.Selected[J] and (J < FDateKeys.Count) then
        Keys.Add(FDateKeys[J]);
    First := nil;
    for I := 0 to FVisible.Count - 1 do
    begin
      It := TImageItem(FVisible[I]);
      It.Selected := Keys.IndexOf(It.DateKey) >= 0;
      if It.Selected and (First = nil) then First := It;
    end;
  finally
    Keys.Free;
    FSyncing := False;
  end;
  if First <> nil then FView.ScrollToItem(First);
  FView.Invalidate;
  UpdateStatus;
end;

{ right click on a date-job entry: change the job code for it (or the highlighted dates) }
procedure TMainForm.DateMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Idx: Integer;
begin
  if (Button <> mbRight) or (ssLeft in Shift) then Exit;     // plain right click only
  Idx := lstDates.ItemAtPos(Point(X, Y), True);
  if Idx < 0 then Exit;
  if not lstDates.Selected[Idx] then
  begin
    FSyncing := True;
    try
      lstDates.ClearSelection;
      lstDates.Selected[Idx] := True;
    finally
      FSyncing := False;
    end;
    SelectDatesFromList;
  end;
  ChangeJobCode;
end;

procedure TMainForm.ChangeJobCode;
var
  Job: string;
  J: Integer;
  Keys: TStringList;
begin
  Keys := TStringList.Create;
  try
    for J := 0 to lstDates.Items.Count - 1 do
      if lstDates.Selected[J] and (J < FDateKeys.Count) then
        Keys.Add(FDateKeys[J]);
    Job := '';
    if Keys.Count > 0 then Job := FS.DateJobCodes.Values[Keys[0]];
    if Job = '' then Job := FS.JobCode;
    if ExecuteJobCode(FS, Job, FCamera) then
    begin
      if Keys.Count > 0 then
        for J := 0 to Keys.Count - 1 do
          FS.DateJobCodes.Values[Keys[J]] := Job     // only the chosen dates
      else
      begin
        FS.JobCode := Job;
        FS.DateJobCodes.Clear;
      end;
    end;
    // also covers Preferences changed from inside the job code dialog
    SaveSettingsNow;
    Reevaluate;
  finally
    Keys.Free;
  end;
end;

procedure TMainForm.PopupPopup(Sender: TObject);
var
  I, NSel, NDel: Integer;
  L: TList;
begin
  NSel := 0;
  NDel := 0;
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      Inc(NSel);
      if TImageItem(FVisible[I]).Status = isDownloaded then Inc(NDel);
    end;
  miPopView.Enabled := NSel > 0;
  miPopLocation.Enabled := NSel > 0;
  miPopProps.Enabled := NSel > 0;
  L := TList.Create;
  try
    GetDownloadList(L);
    miPopDownload.Caption := Format('Download selected file(s) (%d)', [L.Count]);
    miPopDownload.Enabled := (NSel > 0) and (L.Count > 0);
  finally
    L.Free;
  end;
  miPopDelete.Enabled := NDel > 0;
end;

procedure TMainForm.OpenItem(Sender: TObject; Index: Integer);
begin
  ShowImageViewer(FVisible, Index);
end;

procedure TMainForm.PopViewClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      ShowImageViewer(FVisible, I);
      Exit;
    end;
end;

procedure TMainForm.PopLocationClick(Sender: TObject);
var
  I: Integer;
  P: string;
begin
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      P := TImageItem(FVisible[I]).FullPath;
      // select the file in Explorer; elsewhere just open its folder
      if not RevealFile(P) then
        OpenDocument(ExtractFilePath(P));
      Exit;
    end;
end;

procedure TMainForm.PopPropsClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      ShowImageProperties(TImageItem(FVisible[I]));
      Exit;
    end;
end;

procedure TMainForm.PopDownloadClick(Sender: TObject);
begin
  DoDownload(False);
end;

procedure TMainForm.ViewSelChange(Sender: TObject);
var
  I, NSel: Integer;
  One: TImageItem;
begin
  UpdateStatus;
  SyncDateHighlight;
  // a single selected problem image: say exactly what is wrong and what its new name would be
  NSel := 0;
  One := nil;
  for I := 0 to FVisible.Count - 1 do
    if TImageItem(FVisible[I]).Selected then
    begin
      Inc(NSel);
      One := TImageItem(FVisible[I]);
    end;
  if (NSel = 1) and (One <> nil) and One.IsProblem then
    SetStatus(Format('#%d %s - %s -> %s', [One.Index, One.FileName, One.StatusText, One.DestPath]));
end;

{ ====================================================================== }
{ downloading                                                             }
{ ====================================================================== }

function XmlEsc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

procedure TMainForm.WriteXmp(const Dest: string);
var
  X: TStringList;
  KW: TStringList;
  I: Integer;
  V: string;

  procedure Alt(const Tag, Val: string);
  begin
    if Val <> '' then
      X.Add('   <' + Tag + '><rdf:Alt><rdf:li xml:lang="x-default">' + XmlEsc(Val) +
        '</rdf:li></rdf:Alt></' + Tag + '>');
  end;

  procedure Plain(const Tag, Val: string);
  begin
    if Val <> '' then X.Add('   <' + Tag + '>' + XmlEsc(Val) + '</' + Tag + '>');
  end;

begin
  X := TStringList.Create;
  KW := TStringList.Create;
  try
    X.Add('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>');
    X.Add('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
    X.Add(' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
    X.Add('  <rdf:Description rdf:about=""');
    X.Add('    xmlns:dc="http://purl.org/dc/elements/1.1/"');
    X.Add('    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">');
    V := FS.Iptc.Values['Creator'];
    if V <> '' then
      X.Add('   <dc:creator><rdf:Seq><rdf:li>' + XmlEsc(V) + '</rdf:li></rdf:Seq></dc:creator>');
    Alt('dc:rights', FS.Iptc.Values['Copyright']);
    Alt('dc:title', FS.Iptc.Values['Title']);
    Alt('dc:description', FS.Iptc.Values['Description']);
    Plain('photoshop:Credit', FS.Iptc.Values['Credit']);
    Plain('photoshop:Source', FS.Iptc.Values['Source']);
    Plain('photoshop:City', FS.Iptc.Values['City']);
    Plain('photoshop:Country', FS.Iptc.Values['Country']);
    KW.Delimiter := ',';
    KW.StrictDelimiter := True;
    KW.DelimitedText := FS.Iptc.Values['Keywords'];
    if (KW.Count > 0) and (Trim(KW[0]) <> '') then
    begin
      X.Add('   <dc:subject><rdf:Bag>');
      for I := 0 to KW.Count - 1 do
        if Trim(KW[I]) <> '' then
          X.Add('    <rdf:li>' + XmlEsc(Trim(KW[I])) + '</rdf:li>');
      X.Add('   </rdf:Bag></dc:subject>');
    end;
    X.Add('  </rdf:Description>');
    X.Add(' </rdf:RDF>');
    X.Add('</x:xmpmeta>');
    X.Add('<?xpacket end="w"?>');
    X.SaveToFile(ChangeFileExt(Dest, '.xmp'));
  finally
    KW.Free;
    X.Free;
  end;
end;

function TMainForm.PostProcess(It: TImageItem; const Dest: string): Boolean;
var
  SL: TStringList;
  Names: TStringList;
  BDir, ParentDir: string;
  I: Integer;
begin
  Result := True;
  if FS.WriteExifOwner and It.IsJpeg then
    Result := WriteExifOwnerFields(Dest, FS.ExifAuthor, FS.ExifCopyright);

  if FS.UseCaptureTime then
    FileSetDateUTF8(Dest, DateTimeToFileDate(It.CaptureTime));

  if FS.WriteExifText then
  begin
    SL := TStringList.Create;
    try
      SL.Add('File: ' + ExtractFileName(Dest));
      SL.Add('Original: ' + It.FileName);
      SL.Add('Date taken: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', It.CaptureTime));
      SL.Add('Camera: ' + It.Camera);
      SL.Add('Serial: ' + It.Serial);
      SL.Add('ISO: ' + IntToStr(It.ISO));
      SL.SaveToFile(Dest + '.txt');
    finally
      SL.Free;
    end;
  end;

  if FS.AddIptc and (FS.Iptc.Count > 0) then
    WriteXmp(Dest);

  if FS.PluginEnabled('Backup') then
  begin
    BDir := FS.PluginOpts.Values['Backup'];
    if BDir <> '' then
      if ForceDirectoriesUTF8(BDir) then
        CopyFileStream(Dest, IncludeTrailingPathDelimiter(BDir) + ExtractFileName(Dest));
  end;

  if FS.PluginEnabled('Directory Maker') and (FS.PluginOpts.Values['Directory Maker'] <> '') then
  begin
    Names := TStringList.Create;
    try
      Names.Delimiter := ',';
      Names.StrictDelimiter := True;
      Names.DelimitedText := FS.PluginOpts.Values['Directory Maker'];
      ParentDir := ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(Dest)));
      for I := 0 to Names.Count - 1 do
        if Trim(Names[I]) <> '' then
          ForceDirectoriesUTF8(ParentDir + Trim(Names[I]));
    finally
      Names.Free;
    end;
  end;

  // read-only last, so the steps above can still touch the file
  if FS.SaveReadOnly or (FS.PreserveReadOnly and It.IsReadOnly) then
    FileSetAttrUTF8(Dest, FileGetAttrUTF8(Dest) or faReadOnly);
end;

procedure TMainForm.ProgCancelClick(Sender: TObject);
begin
  FCancel := True;
end;

procedure TMainForm.ShowProgress(AMax: Integer);
var
  B: TButton;
begin
  FCancel := False;
  FProg := TForm.CreateNew(Self);
  FProg.Caption := 'Downloading...';
  FProg.BorderStyle := bsDialog;
  FProg.Position := poMainFormCenter;
  FProg.ClientWidth := 440;
  FProg.ClientHeight := 110;
  FProgLbl := TLabel.Create(FProg);
  FProgLbl.Parent := FProg;
  FProgLbl.SetBounds(12, 12, 416, 18);
  FProgLbl.AutoSize := False;
  FProgBar := TProgressBar.Create(FProg);
  FProgBar.Parent := FProg;
  FProgBar.SetBounds(12, 38, 416, 20);
  FProgBar.Min := 0;
  FProgBar.Max := Max(1, AMax);
  B := TButton.Create(FProg);
  B.Parent := FProg;
  B.Caption := 'Cancel';
  B.SetBounds(348, 72, 80, 25);
  B.OnClick := @ProgCancelClick;
  FProg.Show;
  Self.Enabled := False;
  Application.ProcessMessages;
end;

procedure TMainForm.HideProgress;
begin
  Self.Enabled := True;
  FreeAndNil(FProg);
end;

function TMainForm.DoDownload(Silent: Boolean): Boolean;
var
  L: TList;
  I, Done, Skipped, Failed, Problems, ExifFail: Integer;
  It: TImageItem;
  Dest, Msg: string;
  UniqueMode: Boolean;
  R: TModalResult;
begin
  Result := False;
  Done := 0; Skipped := 0; Failed := 0; Problems := 0; ExifFail := 0;
  UniqueMode := False;
  Msg := '';
  L := TList.Create;
  try
    GetDownloadList(L);
    if L.Count = 0 then
    begin
      if not Silent then
        MessageDlg(AppTitle, 'There are no files to download.', mtInformation, [mbOK], 0);
      Exit;
    end;
    for I := 0 to L.Count - 1 do
      if TImageItem(L[I]).IsProblem then Inc(Problems);
    if (Problems > 0) and (not Silent) then
    begin
      R := MessageDlg(AppTitle,
        Format('%d file(s) have a name clash with another file or an existing file.'#13#10#13#10 +
          'Yes = download them anyway, adding -1, -2 ... to the file name'#13#10 +
          'No = skip the problem files'#13#10 +
          'Cancel = do not download anything', [Problems]),
        mtWarning, [mbYes, mbNo, mbCancel], 0);
      if R = mrCancel then Exit;
      UniqueMode := R = mrYes;
    end;
    if (not Silent) and FS.AddIptc and FS.PromptIptc then
      if not ExecuteIptc(FS.Iptc) then Exit;

    ShowProgress(L.Count);
    try
      for I := 0 to L.Count - 1 do
      begin
        if FCancel then Break;
        It := TImageItem(L[I]);
        FProgBar.Position := I;
        FProgLbl.Caption := Format('Downloading %d of %d: %s', [I + 1, L.Count, It.FileName]);
        Application.ProcessMessages;
        if FCancel then Break;

        if It.IsProblem and (not UniqueMode) then
        begin
          Inc(Skipped);
          Continue;
        end;
        Dest := ComputeDest(FS, It, FS.SeqNext, FSession + 1);
        if FileExistsUTF8(Dest) then
        begin
          if UniqueMode then
            Dest := UniqueName(Dest)
          else
          begin
            Inc(Skipped);
            Continue;
          end;
        end;
        if not ForceDirectoriesUTF8(ExtractFilePath(Dest)) then
        begin
          Msg := 'Cannot create the folder:'#13#10 + ExtractFilePath(Dest);
          Inc(Failed);
          Break;
        end;
        if not CopyFileStream(It.FullPath, Dest) then
        begin
          Msg := 'Could not copy:'#13#10 + It.FullPath + #13#10'to'#13#10 + Dest;
          Inc(Failed);
          Break;
        end;
        if not PostProcess(It, Dest) then Inc(ExifFail);
        It.Status := isDownloaded;
        It.DestPath := Dest;
        FLastFile := Dest;
        FLastDir := ExtractFilePath(Dest);
        Inc(FS.SeqNext);
        Inc(FSession);
        Inc(Done);
      end;
    finally
      HideProgress;
    end;
  finally
    L.Free;
  end;

  SaveSettingsNow;
  ApplyFilter;
  if Failed > 0 then
    MessageDlg(AppTitle, Msg, mtError, [mbOK], 0)
  else
  begin
    if FCancel then
      SetStatus(Format('Download canceled after %d file(s).', [Done]))
    else if Skipped > 0 then
      SetStatus(Format('%d file(s) downloaded, %d skipped.', [Done, Skipped]))
    else
      SetStatus(Format('%d file(s) downloaded.', [Done]));
    if ExifFail > 0 then
      SetStatus(lblStatus.Caption + Format(' Author/copyright could not be written to %d file(s).', [ExifFail]));
  end;
  Result := (Failed = 0) and (not FCancel);
end;

function TMainForm.CanDeleteSource(It: TImageItem): Boolean;
begin
  // a source file may only be removed once it has been downloaded
  // and the copy really exists in the destination
  Result := (It.Status = isDownloaded) and (It.DestPath <> '') and FileExistsUTF8(It.DestPath);
end;

procedure TMainForm.DeleteFiles(OnlyDownloaded, Silent: Boolean);
var
  L, E: TList;
  I, Fail, Kept: Integer;
  It: TImageItem;
  AnySel: Boolean;
  Msg: string;
begin
  L := TList.Create;
  E := TList.Create;
  try
    if OnlyDownloaded then
    begin
      for I := 0 to FItems.Count - 1 do
        if ItemAt(FItems, I).Status = isDownloaded then L.Add(FItems[I]);
    end
    else
    begin
      AnySel := False;
      for I := 0 to FVisible.Count - 1 do
        if TImageItem(FVisible[I]).Selected then AnySel := True;
      for I := 0 to FVisible.Count - 1 do
        if (not AnySel) or TImageItem(FVisible[I]).Selected then L.Add(FVisible[I]);
    end;
    if L.Count = 0 then Exit;

    for I := 0 to L.Count - 1 do
      if CanDeleteSource(TImageItem(L[I])) then E.Add(L[I]);
    Kept := L.Count - E.Count;

    if E.Count = 0 then
    begin
      if not Silent then
        MessageDlg(AppTitle,
          'Nothing was deleted. Only files that have been downloaded and exist in ' +
          'the destination can be deleted from the image source.', mtInformation, [mbOK], 0);
      Exit;
    end;
    if not Silent then
    begin
      Msg := Format('Delete %d downloaded file(s) from the image source?'#13#10 +
        'Each one has been checked to exist in the destination.', [E.Count]);
      if Kept > 0 then
        Msg := Msg + #13#10 + Format('%d selected file(s) have not been downloaded and will be kept.', [Kept]);
      Msg := Msg + #13#10#13#10'This cannot be undone.';
      if MessageDlg(AppTitle, Msg, mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;
    end;
    Fail := 0;
    for I := 0 to E.Count - 1 do
    begin
      It := TImageItem(E[I]);
      if It.IsReadOnly then FileSetAttrUTF8(It.FullPath, 0);
      if DeleteFileUTF8(It.FullPath) then
        FItems.Remove(It)          // the list owns and frees the item
      else
        Inc(Fail);
    end;
    for I := 0 to FItems.Count - 1 do
      ItemAt(FItems, I).Index := I + 1;
    RebuildDates;
    ApplyFilter;
    if Fail > 0 then
      MessageDlg(AppTitle, Format('%d file(s) could not be deleted.', [Fail]), mtError, [mbOK], 0);
  finally
    E.Free;
    L.Free;
  end;
end;

function TMainForm.DoEject(Silent: Boolean): Boolean;
var
  Root: string;
begin
  Result := False;
  if FSourcePath = '' then Exit;
  Root := ExtractFileDrive(FSourcePath);
  if Root = '' then
  begin
    if not Silent then
      MessageDlg(AppTitle, 'The current source is not a removable drive.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Root := Root + PathDelim;
  if EjectDrive(Root) then
  begin
    FItems.Clear;
    FVisible.Clear;
    FSourcePath := '';
    RebuildDates;
    ApplyFilter;
    UpdateCaption;
    UpdateMenus;
    Result := True;
  end
  else if not Silent then
    MessageDlg(AppTitle, 'The media could not be ejected. Close any programs using it and try again.',
      mtWarning, [mbOK], 0);
end;

procedure TMainForm.LaunchCustom;
var
  Cmd: string;
begin
  if (not FS.CustomEnabled) or (Trim(FS.CustomCmd) = '') then Exit;
  Cmd := StringReplace(FS.CustomCmd, '%f', FLastFile, [rfReplaceAll]);
  Cmd := StringReplace(Cmd, '%d', FLastDir, [rfReplaceAll]);
  try
    LaunchCommand(Cmd);
  except
    on E: Exception do
      MessageDlg(AppTitle, 'Could not run the custom command:'#13#10 + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.RunAutoSequence;
begin
  if FItems.Count = 0 then Exit;
  if FS.AutoMenu and FS.AutoPrompt then
    if MessageDlg(AppTitle, 'Start the automatic download sequence?', mtConfirmation,
         [mbYes, mbNo], 0) <> mrYes then Exit;
  if FS.AutoDownload then
    if not DoDownload(True) then Exit;     // stop on error or cancel
  if FS.AutoDelete then DeleteFiles(True, True);
  if FS.AutoSoftEject then
    if not DoEject(True) then Exit;
  if FS.AutoLaunch then LaunchCustom;
  if FS.AutoExit then Close;
end;

procedure TMainForm.AskJobCode;
var
  Job: string;
begin
  Job := FS.JobCode;
  if ExecuteJobCode(FS, Job, FCamera) then
    FS.JobCode := Job;
end;

{ ====================================================================== }
{ events                                                                  }
{ ====================================================================== }

procedure TMainForm.StartupTimer(Sender: TObject);
var
  L: TStringList;
  Choice: string;
begin
  FTimer.Enabled := False;
  if FS.SingleInstance then RegisterMainWindow(Handle);   // lets a second copy find this window
  if FS.PromptProfile then
  begin
    L := TStringList.Create;
    try
      ListProfiles(L);
      if (L.Count > 0) and ChooseFromList('User Profiles', 'Select a profile to load:', L, Choice) then
      begin
        FS.LoadFromFile(ProfilesDir + Choice + '.ini');
        ApplyState;
      end;
    finally
      L.Free;
    end;
  end;
  if FS.PromptJobCode then AskJobCode;
  // nothing is scanned at start-up unless the user asked for it
  if FS.LoadLastAtStartup and (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then
    LoadSource(FS.LastSource)
  else if FS.AutoAtStartup then
    AutoDetectSource
  else if FS.LastSource <> '' then
    SetStatus('Last source: ' + FS.LastSource + '   (F5 loads it, or use File > Open Source Folder)')
  else
    SetStatus('Choose File > Open Source Folder (Ctrl+O) to load images.');
  FS.FirstRunDone := True;
  if FS.AutoAtStartup then RunAutoSequence;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if CloseAction = caNone then Exit;     // closing was cancelled
  SaveSettingsNow;
end;

procedure TMainForm.OpenSourceClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Open Source Folder';
    if (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then
      D.InitialDir := FS.LastSource;
    if D.Execute then
    begin
      LoadSource(D.FileName);
      SaveSettingsNow;
    end;
  finally
    D.Free;
  end;
end;

procedure TMainForm.ListProfiles(L: TStrings);
var
  SR: TSearchRec;
begin
  L.Clear;
  if FindFirstUTF8(ProfilesDir + '*.ini', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        L.Add(ChangeFileExt(SR.Name, ''));
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
end;

procedure TMainForm.ProfileLoadClick(Sender: TObject);
var
  L: TStringList;
  Choice: string;
begin
  L := TStringList.Create;
  try
    ListProfiles(L);
    if L.Count = 0 then
    begin
      MessageDlg(AppTitle, 'There are no saved user profiles.', mtInformation, [mbOK], 0);
      Exit;
    end;
    if ChooseFromList('Load User Profile', 'Select a profile to load:', L, Choice) then
    begin
      FS.LoadFromFile(ProfilesDir + Choice + '.ini');
      SaveSettingsNow;
      ApplyState;
      Reevaluate;
    end;
  finally
    L.Free;
  end;
end;

procedure TMainForm.ProfileSaveClick(Sender: TObject);
var
  Nm: string;
  I: Integer;
begin
  Nm := '';
  if not InputQuery('Save User Profile', 'Profile name:', Nm) then Exit;
  Nm := Trim(Nm);
  for I := 1 to Length(Nm) do
    if Nm[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then Nm[I] := '_';
  if Nm = '' then Exit;
  try
    FS.SaveToFile(ProfilesDir + Nm + '.ini');
  except
    on E: Exception do
      MessageDlg(AppTitle, 'Could not save the profile:'#13#10 + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.ProfileDeleteClick(Sender: TObject);
var
  L: TStringList;
  Choice: string;
begin
  L := TStringList.Create;
  try
    ListProfiles(L);
    if L.Count = 0 then
    begin
      MessageDlg(AppTitle, 'There are no saved user profiles.', mtInformation, [mbOK], 0);
      Exit;
    end;
    if ChooseFromList('Delete User Profile', 'Select a profile to delete:', L, Choice) then
      if MessageDlg(AppTitle, 'Delete the profile "' + Choice + '"?', mtConfirmation,
           [mbYes, mbNo], 0) = mrYes then
        DeleteFileUTF8(ProfilesDir + Choice + '.ini');
  finally
    L.Free;
  end;
end;

procedure TMainForm.StatusClick(Sender: TObject);
var
  I, NNew, NDown, NClash, NDup: Integer;
  S: string;
begin
  NNew := 0; NDown := 0; NClash := 0; NDup := 0;
  for I := 0 to FItems.Count - 1 do
    case ItemAt(FItems, I).Status of
      isNew: Inc(NNew);
      isDownloaded: Inc(NDown);
      isNameClash: Inc(NClash);
      isDuplicate: Inc(NDup);
    end;
  if FSourcePath = '' then S := 'Source: (none)' else S := 'Source: ' + FSourcePath;
  S := AppTitle + ' ' + AppVersionString + #13#10#13#10 + S + #13#10 + Format('Files found: %d', [FItems.Count]) +
    #13#10 + Format('  New: %d   Already downloaded: %d   Name clashes: %d   Duplicates: %d',
      [NNew, NDown, NClash, NDup]) +
    #13#10#13#10 + 'Job code: ' + FS.JobCode +
    #13#10 + 'Next sequence number: ' + IntToStr(FS.SeqNext) +
    #13#10 + 'Example: ' + ExampleDest(FS, FS.DownloadDir, FS.FileNameMask, FS.JobCode) +
    #13#10#13#10 + 'Settings file: ' + SettingsFileName;
  MessageDlg('Status', S, mtInformation, [mbOK], 0);
end;

procedure TMainForm.PrefsClick(Sender: TObject);
begin
  if ExecutePreferences(FS, FCamera) then
  begin
    SaveSettingsNow;
    ApplyState;
    Reevaluate;
  end;
end;

procedure TMainForm.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Export Settings';
    D.FileName := 'DownloaderProSettings.ini';
    D.Filter := 'Settings (*.ini)|*.ini|All files|*.*';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
      try
        FS.SaveToFile(D.FileName);
      except
        on E: Exception do
          MessageDlg(AppTitle, 'Could not export settings:'#13#10 + E.Message, mtError, [mbOK], 0);
      end;
  finally
    D.Free;
  end;
end;

procedure TMainForm.AutoClick(Sender: TObject);
begin
  RunAutoSequence;
end;

procedure TMainForm.RefreshClick(Sender: TObject);
begin
  if FSourcePath <> '' then
    LoadSource(FSourcePath)
  else if (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then
    LoadSource(FS.LastSource)
  else
    AutoDetectSource;
end;

procedure TMainForm.EjectClick(Sender: TObject);
begin
  DoEject(False);
end;

procedure TMainForm.ExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.SelectWhere(Mode: Integer);
var
  I: Integer;
  It: TImageItem;
begin
  for I := 0 to FVisible.Count - 1 do
  begin
    It := TImageItem(FVisible[I]);
    case Mode of
      0: It.Selected := True;
      1: It.Selected := It.Status = isDownloaded;
      2: It.Selected := It.IsReadOnly;
      3: It.Selected := It.IsJpeg;
      4: It.Selected := False;
      5: It.Selected := not It.Selected;
    end;
  end;
  FView.SelectionChanged;
end;

procedure TMainForm.SelAllClick(Sender: TObject);  begin SelectWhere(0); end;
procedure TMainForm.SelDownClick(Sender: TObject); begin SelectWhere(1); end;
procedure TMainForm.SelROClick(Sender: TObject);   begin SelectWhere(2); end;
procedure TMainForm.SelJpgClick(Sender: TObject);  begin SelectWhere(3); end;
procedure TMainForm.SelNoneClick(Sender: TObject); begin SelectWhere(4); end;
procedure TMainForm.InvertClick(Sender: TObject);  begin SelectWhere(5); end;

procedure TMainForm.IptcClick(Sender: TObject);
begin
  if ExecuteIptc(FS.Iptc) then SaveSettingsNow;
end;

procedure TMainForm.JobClick(Sender: TObject);
begin
  ChangeJobCode;
end;

procedure TMainForm.GpsClick(Sender: TObject);
begin
  MessageDlg('GPS settings', 'GPS track log geotagging is not available in this version.',
    mtInformation, [mbOK], 0);
end;

procedure TMainForm.ShowDownClick(Sender: TObject);
begin
  FS.ShowDownloaded := not FS.ShowDownloaded;
  miShowDown.Checked := FS.ShowDownloaded;
  ApplyFilter;
end;

procedure TMainForm.ShowDupClick(Sender: TObject);
begin
  FS.ShowDuplicates := not FS.ShowDuplicates;
  miShowDup.Checked := FS.ShowDuplicates;
  ApplyFilter;
end;

procedure TMainForm.ListViewClick(Sender: TObject);  begin SetViewMode(0); end;
procedure TMainForm.SmallViewClick(Sender: TObject); begin SetViewMode(1); end;
procedure TMainForm.LargeViewClick(Sender: TObject); begin SetViewMode(2); end;

procedure TMainForm.DateSelClick(Sender: TObject);
begin
  FS.ShowDateSelector := not FS.ShowDateSelector;
  miDateSel.Checked := FS.ShowDateSelector;
  pnlLeft.Visible := FS.ShowDateSelector;
  splLeft.Visible := FS.ShowDateSelector;
end;

procedure TMainForm.HelpContentsClick(Sender: TObject);
begin
  MessageDlg('Getting Started',
    '1. Insert a memory card, or choose File > Open Source Directory.' + #13#10 +
    '2. Enter a job code when prompted (Edit > Job code... changes it later).' + #13#10 +
    '3. Click Download. Files are copied to the folder set in File > Preferences.' + #13#10#13#10 +
    'Red images have a name clash: another file would be written to the same name.' + #13#10 +
    'Press F1 in the Preferences dialog for the list of file name tokens.',
    mtInformation, [mbOK], 0);
end;

procedure TMainForm.WebsiteClick(Sender: TObject);
begin
  if not OpenURL(WebsiteURL) then
    MessageDlg('Visit website', 'The web browser could not be started. The address is:'#13#10 +
      WebsiteURL, mtWarning, [mbOK], 0);
end;

procedure TMainForm.UpdatesClick(Sender: TObject);
begin
  // new versions are published as GitHub releases
  if not OpenURL(UpdatesURL) then
    MessageDlg('Check for updates', 'The web browser could not be started. The address is:'#13#10 +
      UpdatesURL, mtWarning, [mbOK], 0);
end;

procedure TMainForm.RegisterClick(Sender: TObject);
begin
  ShowRegister;
end;

procedure TMainForm.AboutClick(Sender: TObject);
begin
  ShowAbout;
end;

procedure TMainForm.DownloadClick(Sender: TObject);
begin
  DoDownload(False);
end;

procedure TMainForm.DeleteClick(Sender: TObject);
begin
  DeleteFiles(False, False);
end;

procedure TMainForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.CustomClick(Sender: TObject);
begin
  LaunchCustom;
end;

end.
