unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Math, Forms, Controls, Graphics, Dialogs, Menus,
  ExtCtrls, StdCtrls, ComCtrls, LCLType, LCLIntf, LazFileUtils, IniFiles,
  uSettings, uItems, uExif, uVersion, uPhotoView, uDialogs, uHeic, uDrives, uViewer, uLrPrev, uLrCat, uSingle, uRotate, uSafeDel, uSplash, uPlugins, uExtPlugin, uIccEmbed, uJpegDpi,
  uDevices, uDeviceDlg,  // phones and cameras by USB: Shell access and the import window
  uTheme,  // light and dark colors
  uMsgDlg;  // MessageDlg with Yes on the left on every system (after Dialogs)

type
  { Which files a download takes: dsAuto = the selected ones, or all when nothing is selected (automation);
    dsSelected = only the selected ones (Download Selected); dsAll = all shown files (Download All) }
  TDownloadScope = (dsAuto, dsSelected, dsAll);

  TMainForm = class(TForm)
  private
    FPluginErr: string;  // problems found while loading plug-in libraries (shown after the splash)
    FAutoClosing: Boolean;  // the automatic sequence closes the program: no questions
    FStepFails: TStringList;  // plug-in steps that failed during the current download (one line each)
    FWantClientH: Integer;  // client height the window was given at creation (GTK may shrink it before it is shown)
    FS: TAppSettings;  // program settings
    FItems: TObjectList;            // all images found on the source (owned)
    FVisible: TList;                // images currently shown (not owned)
    FDateKeys: TStringList;         // parallel to lstDates
    FSourcePath, FCamera, FLastFile, FLastDir: string;  // FSourcePath: current source folder; FCamera: camera name; FLastFile: last downloaded file; FLastDir: its folder
    FSession: Integer;  // download session number
    FDevName, FDevId, FDevStage: string;  // the device that is the source: name, what finds it again, its staging folder ('' = no device)
    FDevFolderNames, FDevFolderIds: TStringList;  // the device folders that were imported (Refresh imports them again)
    FDevFiles: TStringList;  // the device's files: staging path below FDevStage -> TDeviceFile (owned)
    FDevDoneKb: Int64;  // KB imported before the current file (progress bar)
    FThumbCols: Integer;            // thumbnail columns the window was sized for
    FCancel: Boolean;  // True when the user pressed Cancel
    FSyncing: Boolean;              // true while list/grid selections are being mirrored
    FProg: TForm;  // progress window
    FProgBar: TProgressBar;  // progress bar
    FProgLbl, FProgLbl2: TLabel;  // labels of the progress window
    FProgBar2: TProgressBar;  // second progress bar
    FTimer: TTimer;  // timer for the start-up work
    FLastTick: QWord;  // time of the last window update
    FPopup: TPopupMenu;  // pop-up menu of the grid
    miPopLrJpg: TMenuItem;  // pop-up item: save the selected .lrprev previews as JPG files
    FLrOutDir: string;  // folder last chosen for the JPG files made from .lrprev previews
    miPopView, miPopLocation, miPopDestLoc, miPopProps, miPopDownload, miPopDelete: TMenuItem;  // pop-up menu items
    miPopShowDown, miPopShowDup, miPopList, miPopSmall, miPopMedium, miPopLarge, miPopFit: TMenuItem;  // pop-up copies of the View menu items
    miThemeSys, miThemeLight, miThemeDark: TMenuItem;  // View > Theme choices
    FThemeTimer: TTimer;  // looks for a change of the system's light/dark setting
    FThemeWasDark: Boolean;  // the system setting last seen
    miAuto, miPlugins, miEject, miShowDown, miShowDup, miList, miSmall, miMedium, miLarge, miFit, miDateSel, miLogging: TMenuItem;  // menu items that are checked or switched
    pnlLeft, pnlStatus, pnlButtons: TPanel;  // left panel, status panel and button panel
    lblDate, lblStatus: TLabel;  // labels for the date list and the status
    lstDates: TListBox;  // list of image dates
    splLeft: TSplitter;  // splitter between the date list and the grid
    FView: TPhotoView;  // grid or list of images
    btnDownload, btnDownloadAll, btnDelete, btnClose, btnCustom: TButton;  // main buttons (btnDownload = Download Selected)
    // construction
    function AddMenu(AParent: TMenuItem; const Cap: string; H: TNotifyEvent;
      SC: TShortCut): TMenuItem;
    procedure BuildMenu;
    procedure BuildUI;
    procedure PlaceButton(B: TButton; Right: TControl; ASpace: Integer);
    // helpers
    procedure SaveSettingsNow;
    procedure ApplyState;
    procedure SizeForThumbColumns(Cols: Integer);
    procedure FixThumbWidth;
    procedure CenterOnWorkArea;
    procedure SetViewMode(M: Integer);
    procedure SetThumbPreset(Size: Integer);
    procedure UpdateViewChecks;
    procedure ApplyTheme;  // colors of the theme in the window, the grid and the title bar
    procedure ThemeChecks;  // marks the theme choice in the menu, watches the system setting
    procedure ThemeClick(Sender: TObject);  // View > Theme: Follow system / Light / Dark
    procedure ThemeTimerTick(Sender: TObject);  // follows a change of the system setting
    function RestartProgram: Boolean;  // closes and starts the program again (after a theme change); False when canceled
    procedure ThumbSizeChanged(Sender: TObject);
    procedure SetStatus(const S: string);
    procedure UpdateCaption;
    procedure UpdateMenus;
    procedure UpdateStatus;
    procedure ScanProgress(Count: Integer);
    procedure LoadSource(const Path: string);
    procedure AutoDetectSource;
    function ImportFromDevice(const DevName, DevId: string; FolderNames, FolderIds: TStrings; Silent: Boolean): Boolean;  // copies device folders to staging and loads them
    function ImportFirstDevice(Silent: Boolean): Boolean;  // imports DCIM of the first connected device (Refresh, automation)
    function ImportDeviceDcim(const DevName, DevId: string; Silent: Boolean): Boolean;  // imports DCIM of one device
    function DevCountProgress(Count: Integer): Boolean;  // progress while listing device files
    function DevBytesProgress(Bytes: Int64): Boolean;  // progress while copying a device file
    procedure LeaveDevice;  // the device stops being the source: downloaded staged copies are removed
    function DeviceFileOf(It: TImageItem): TDeviceFile;  // the device file a staged item came from (nil when none)
    procedure Reevaluate;
    procedure ReloadPlugins;  // looks for plug-in libraries again and reports problems
    procedure SaveDownloadToProfile;  // writes the download path and plug-in values just used into the profile in use
    procedure RebuildDates;
    procedure ApplyFilter;
    procedure GetDownloadList(L: TList; Scope: TDownloadScope = dsAuto);
    function ToDownload(It: TImageItem): Boolean;  // True when a download would copy this item (or files of this scan)
    procedure SelectWhere(Mode: Integer);
    function PostProcess(It: TImageItem; const Dest: string): Boolean;
    procedure RunPluginSteps(It: TImageItem; const Dest: string);  // runs the switched-on plug-in steps on a downloaded file
    function JpegProfileStep(It: TImageItem; const Dest: string; out Msg: string): Integer;  // the JPEG auto profile step
    function JpegResolutionStep(const Dest: string; out Msg: string): Integer;  // the JPEG resolution step
    procedure SyncDateHighlight;
    procedure SelectDatesFromList;
    procedure ChangeJobCode;
    procedure PopupPopup(Sender: TObject);
    procedure PopDownloadClick(Sender: TObject);
    procedure PopViewClick(Sender: TObject);
    procedure PopLocationClick(Sender: TObject);
    procedure PopDestLocClick(Sender: TObject);
    procedure PopPropsClick(Sender: TObject);
    procedure PopLrJpgClick(Sender: TObject);
    procedure OpenItem(Sender: TObject; Index: Integer);
    procedure HeaderClick(Sender: TObject; Col: Integer);
    procedure ViewTrashClick(Sender: TObject);
    procedure EmptyTrashClick(Sender: TObject);
    function CanDeleteSource(It: TImageItem): Boolean;
    procedure DateMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure WriteXmp(const Dest: string);
    procedure ShowProgress(AMax: Integer; const ACaption: string = 'Downloading...';
      TwoBars: Boolean = False);
    function ItemVisible(It: TImageItem): Boolean;
    procedure HideProgress;
    function DoDownload(Silent: Boolean; Scope: TDownloadScope = dsAuto): Boolean;
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
    procedure CopyTick;
    procedure OpenSourceClick(Sender: TObject);
    procedure ImportDeviceClick(Sender: TObject);  // File > Import from Device...
    procedure ProfilesClick(Sender: TObject);  // File > User Profiles...: the profiles window
    function ProfileAction(Act: TProfileAction; const Nm: string): Boolean;  // does what the profiles window asks
    function ProfileInUse: string;  // the profile in use (for the profiles window)
    procedure LoadProfileNamed(const Nm: string);  // loads a saved profile and makes it the profile in use
    function WriteProfile(const Nm: string): Boolean;  // saves the settings as the profile Nm (no questions)
    function ProfileChanged: Boolean;  // True when the settings differ from the saved profile in use
    function AskSaveProfile: Boolean;  // asks to save unsaved profile changes; False when the user canceled
    procedure UseDefaultProfile;  // makes "Default" the profile in use (loads it, or creates it from the settings)
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);  // asks about unsaved profile changes
    procedure StatusClick(Sender: TObject);
    procedure PrefsClick(Sender: TObject);
    procedure FileTypesClick(Sender: TObject);
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
    procedure MediumViewClick(Sender: TObject);
    procedure FitViewClick(Sender: TObject);
    procedure LargeViewClick(Sender: TObject);
    procedure DateSelClick(Sender: TObject);
    procedure HelpContentsClick(Sender: TObject);
    procedure WebsiteClick(Sender: TObject);
    procedure UpdatesClick(Sender: TObject);
    procedure DonatePayPalClick(Sender: TObject);
    procedure DonateVenmoClick(Sender: TObject);
    procedure RegisterClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure LoggingClick(Sender: TObject);
    procedure SaveLogClick(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure DownloadAllClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure CustomClick(Sender: TObject);
  protected
    procedure DoShow; override;  // the window is on the screen: title bar of the theme
    procedure TitleBarLater(Data: PtrInt);  // the title bar again once the window is really shown
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{ Returns the number of thumbnail columns wanted for a view mode. }
function WantedColumns(Mode: TViewMode; Size: Integer): Integer; forward;

{ ====================================================================== }
{ construction                                                            }
{ ====================================================================== }

{ Creates the main window, loads the settings and builds the menu and controls. }
constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);  // create the form without a resource file
  Caption := AppTitle + ' - no image source';  // window title
  Position := poScreenCenter;  // open in the middle of the screen
  ClientWidth := 1100;  // window width
  ClientHeight := 700;  // window height
  // small screens (for example 1366x768): keep the window inside the work area
  {$IFDEF WINDOWS}
  if ClientHeight > Screen.WorkAreaHeight - 80 then ClientHeight := Screen.WorkAreaHeight - 80;  // keep the window inside the work area of a small screen
  {$ELSE}
  // some Linux desktops report the whole screen as work area although a panel covers part of it
  if ClientHeight > Screen.WorkAreaHeight - 150 then ClientHeight := Screen.WorkAreaHeight - 150;  // keep the window inside the work area, leaving room for a panel
  {$ENDIF}
  if ClientWidth > Screen.WorkAreaWidth - 20 then ClientWidth := Screen.WorkAreaWidth - 20;  // keep the window inside the work area
  FWantClientH := ClientHeight;  // remember the wanted height
  FS := TAppSettings.Create;  // create the settings
  FS.LoadFromFile(SettingsFileName);  // read the settings file
  LogEnabled := FS.LoggingOn;  // switch the log on or off
  FPluginErr := LoadPlugins(FS);  // plug-in libraries (their tokens are needed for the first scan)
  FItems := TObjectList.Create(True);  // list of all images (owns them)
  FDevFolderNames := TStringList.Create;  // imported device folders: names
  FDevFolderIds := TStringList.Create;  // imported device folders: what finds them again
  FDevFiles := TStringList.Create;  // the device's files by staging path
  FDevFiles.OwnsObjects := True;  // frees the TDeviceFile objects
  FDevFiles.Sorted := True;  // fast lookup
  FDevFiles.CaseSensitive := False;  // Windows paths
  FVisible := TList.Create;  // list of the visible images
  FDateKeys := TStringList.Create;  // list of the image dates
  BuildMenu;  // build the menu
  BuildUI;  // build the controls
  FThemeTimer := TTimer.Create(Self);  // follows the system's light/dark setting
  FThemeTimer.Interval := 2000;  // a look every 2 seconds (one registry value)
  FThemeTimer.Enabled := False;  // ApplyTheme switches it on when following the system
  FThemeTimer.OnTimer := @ThemeTimerTick;  // before ApplyState, which calls ApplyTheme
  ApplyState;  // apply the saved window state
  if not FS.FitWindow then  // Fit to Window adapts to the window, so the window keeps its size
    SizeForThumbColumns(WantedColumns(FView.Mode, FView.ThumbSize));  // size the window for the thumbnail columns
  OnClose := @FormClose;  // close handler
  OnCloseQuery := @FormCloseQuery;  // asks about unsaved profile changes first
  FTimer := TTimer.Create(Self);  // create the start-up timer
  FTimer.Interval := 150;  // fire after 150 ms
  FTimer.OnTimer := @StartupTimer;  // start-up work
end;

{ Frees the lists and the settings. }
destructor TMainForm.Destroy;
begin
  Application.RemoveAsyncCalls(Self);  // a queued title bar call must not reach a freed window
  FVisible.Free;  // free the visible list
  FDateKeys.Free;  // free the date list
  FItems.Free;  // free the item list
  FDevFiles.Free;  // free the device file list
  FDevFolderNames.Free;  // free the device folder names
  FDevFolderIds.Free;  // free the device folder ids
  FStepFails.Free;  // free the list of failed plug-in steps (may be nil)
  FS.Free;  // free the settings
  inherited Destroy;  // run the inherited destructor
end;

{$IFDEF UNIX}
type
  { Runs a menu handler a moment after the menu has closed. With GTK 3 a dialog that is opened
    from inside the menu click (for example the folder chooser) blocks while the menu still holds
    the mouse and keyboard grab: the menu stays pressed and the program seems to hang. }
  TDeferredClick = class(TComponent)
  public
    Handler: TNotifyEvent;  // the real click handler
    Item: TMenuItem;  // the menu item that was clicked
    procedure Click(Sender: TObject);  // menu click: queue the call
    procedure Fire(Data: PtrInt);  // runs the real handler after the menu is gone
  end;

procedure TDeferredClick.Click(Sender: TObject);
begin
  Application.QueueAsyncCall(@Fire, 0);  // run it when the main loop is idle
end;

procedure TDeferredClick.Fire(Data: PtrInt);
begin
  if Assigned(Handler) then Handler(Item);  // call the real handler
end;
{$ENDIF}

{ Adds a menu item with a handler and a shortcut to a parent item. On Linux the handler runs
  a moment after the menu has closed (see TDeferredClick).}
function TMainForm.AddMenu(AParent: TMenuItem; const Cap: string; H: TNotifyEvent;
  SC: TShortCut): TMenuItem;
{$IFDEF UNIX}
var
  D: TDeferredClick;  // D: helper that delays the click handler
{$ENDIF}
begin
  Result := TMenuItem.Create(Self);  // create the item
  Result.Caption := Cap;  // set the text
  {$IFDEF UNIX}
  if Assigned(H) then  // Linux: run the handler after the menu has closed
  begin
    D := TDeferredClick.Create(Self);  // helper owned by the form
    D.Handler := H;  // the real handler
    D.Item := Result;  // the item
    Result.OnClick := @D.Click;  // the menu calls the helper
  end;
  {$ELSE}
  if Assigned(H) then Result.OnClick := H;  // set the handler
  {$ENDIF}
  if SC <> 0 then Result.ShortCut := SC;  // set the shortcut
  AParent.Add(Result);  // add it to the parent
end;

{ Builds the main menu. }
procedure TMainForm.BuildMenu;
var
  MM: TMainMenu;  // MM: the main menu
  MFile, MEdit, MView, MHelp, Cam, MTheme: TMenuItem;  // menu items that are used below
begin
  MM := TMainMenu.Create(Self);  // create the main menu
  Menu := MM;  // attach it to the form

  MFile := AddMenu(MM.Items, '&File', nil, 0);  // File menu
  AddMenu(MFile, 'Open Source Folder', @OpenSourceClick, ShortCut(VK_O, [ssCtrl]));  // open a source folder
  AddMenu(MFile, 'Import from Device...', @ImportDeviceClick, ShortCut(VK_O, [ssCtrl, ssShift]));  // phone, camera or drone controller by USB
  AddMenu(MFile, '-', nil, 0);  // separator
  AddMenu(MFile, 'User Profiles...', @ProfilesClick, 0);  // the profiles window: load, save, save as, new, delete
  AddMenu(MFile, '-', nil, 0);  // separator
  Cam := AddMenu(MFile, 'Camera Settings', nil, ShortCut(VK_S, [ssCtrl]));  // camera settings
  Cam.Enabled := False;            // direct camera (PTP) control is not supported
  AddMenu(MFile, 'Status', @StatusClick, 0);  // status window
  AddMenu(MFile, 'Preferences', @PrefsClick, ShortCut(VK_P, [ssCtrl]));  // preferences
  miPlugins := AddMenu(MFile, 'Plug-ins...', @PrefsClick, 0);  // Preferences, opened on the Plug-ins tab
  AddMenu(MFile, 'Export Settings', @ExportClick, 0);  // export the settings
  AddMenu(MFile, 'View Trash', @ViewTrashClick, 0);  // view the trash
  AddMenu(MFile, 'Empty Trash...', @EmptyTrashClick, 0);  // empty the trash
  AddMenu(MFile, '-', nil, 0);  // separator
  miAuto := AddMenu(MFile, 'Start Auto Sequence', @AutoClick, ShortCut(VK_F4, []));  // start the auto sequence
  AddMenu(MFile, 'Refresh', @RefreshClick, ShortCut(VK_F5, []));  // refresh the source
  miEject := AddMenu(MFile, 'Eject', @EjectClick, ShortCut(VK_F6, []));  // eject the media
  AddMenu(MFile, '-', nil, 0);  // separator
  AddMenu(MFile, 'Exit', @ExitClick, 0);  // exit the program

  MEdit := AddMenu(MM.Items, '&Edit', nil, 0);  // Edit menu
  AddMenu(MEdit, 'Select All', @SelAllClick, ShortCut(VK_A, [ssCtrl]));  // select all images
  AddMenu(MEdit, 'Select Downloaded', @SelDownClick, ShortCut(VK_D, [ssCtrl]));  // select downloaded images
  AddMenu(MEdit, 'Select Read Only', @SelROClick, ShortCut(VK_R, [ssCtrl]));  // select read-only images
  AddMenu(MEdit, 'Select JPEGs', @SelJpgClick, ShortCut(VK_J, [ssCtrl, ssShift]));  // select JPEG images
  AddMenu(MEdit, 'Select None', @SelNoneClick, ShortCut(VK_N, [ssCtrl]));  // clear the selection
  AddMenu(MEdit, 'Invert Selection', @InvertClick, ShortCut(VK_I, [ssCtrl]));  // invert the selection
  AddMenu(MEdit, '-', nil, 0);  // separator
  AddMenu(MEdit, 'IPTC/XMP Data..', @IptcClick, ShortCut(VK_C, [ssCtrl]));  // edit IPTC and XMP data
  AddMenu(MEdit, 'Job Code', @JobClick, ShortCut(VK_J, [ssCtrl]));  // change the job code
  AddMenu(MEdit, '-', nil, 0);  // separator
  AddMenu(MEdit, 'GPS Settings', @GpsClick, 0);  // GPS settings
  AddMenu(MEdit, 'Check GPS Track Log', nil, 0).Enabled := False;  // GPS track log (not available)

  MView := AddMenu(MM.Items, '&View', nil, 0);  // View menu
  miShowDown := AddMenu(MView, 'Show ''Downloaded'' files', @ShowDownClick, 0);  // show or hide downloaded files
  miShowDup := AddMenu(MView, 'Show ''Duplicate'' files', @ShowDupClick, 0);  // show or hide duplicate files
  AddMenu(MView, 'File Types...', @FileTypesClick, 0);  // choose the file types
  AddMenu(MView, '-', nil, 0);  // separator
  miList := AddMenu(MView, 'List View', @ListViewClick, ShortCut(VK_L, [ssCtrl]));  // list view
  miSmall := AddMenu(MView, 'Thumbnail View (small thumbnails)', @SmallViewClick,  // small thumbnails (64 pixels)
    ShortCut(VK_T, [ssCtrl]));
  miMedium := AddMenu(MView, 'Thumbnail View (medium thumbnails)', @MediumViewClick,  // medium thumbnails (160 pixels)
    ShortCut(VK_M, [ssCtrl]));
  miLarge := AddMenu(MView, 'Thumbnail View (large thumbnails)', @LargeViewClick,  // large thumbnails (320 pixels)
    ShortCut(VK_X, [ssCtrl]));
  miFit := AddMenu(MView, 'Thumbnail View (fit to window)', @FitViewClick,  // cards fill the window width
    ShortCut(VK_F, [ssCtrl]));
  AddMenu(MView, '-', nil, 0);  // separator
  miDateSel := AddMenu(MView, 'Image Date Selector', @DateSelClick, ShortCut(VK_TAB, [ssCtrl]));  // show or hide the date list
  AddMenu(MView, '-', nil, 0);  // separator
  MTheme := AddMenu(MView, 'Theme', nil, 0);  // light or dark colors
  miThemeSys := AddMenu(MTheme, {$IFDEF WINDOWS}'Follow Windows'{$ELSE}'Follow System'{$ENDIF}, @ThemeClick, 0);  // the system's light/dark setting
  miThemeLight := AddMenu(MTheme, 'Light', @ThemeClick, 0);  // always light
  miThemeDark := AddMenu(MTheme, 'Dark', @ThemeClick, 0);  // always dark
  miThemeSys.RadioItem := True; miThemeLight.RadioItem := True; miThemeDark.RadioItem := True;  // one of the three
  miThemeSys.GroupIndex := 7; miThemeLight.GroupIndex := 7; miThemeDark.GroupIndex := 7;
  // GTK creates a menu item without a check box until it is first checked (and keeps the box after that):
  // ShowAlwaysCheckable creates the box from the start, as in the right-click menu
  miList.RadioItem := True; miSmall.RadioItem := True; miMedium.RadioItem := True;  // the views exclude each other
  miLarge.RadioItem := True; miFit.RadioItem := True;
  miList.GroupIndex := 2; miSmall.GroupIndex := 2; miMedium.GroupIndex := 2;  // one group
  miLarge.GroupIndex := 2; miFit.GroupIndex := 2;
  miShowDown.ShowAlwaysCheckable := True; miShowDup.ShowAlwaysCheckable := True;  // check boxes
  miList.ShowAlwaysCheckable := True; miSmall.ShowAlwaysCheckable := True; miMedium.ShowAlwaysCheckable := True;
  miLarge.ShowAlwaysCheckable := True; miFit.ShowAlwaysCheckable := True;  // round marks
  miDateSel.ShowAlwaysCheckable := True;  // check box
  miThemeSys.ShowAlwaysCheckable := True; miThemeLight.ShowAlwaysCheckable := True;
  miThemeDark.ShowAlwaysCheckable := True;  // round marks

  MHelp := AddMenu(MM.Items, '&Help', nil, 0);  // Help menu
  AddMenu(MHelp, 'Contents', @HelpContentsClick, 0);  // help contents
  AddMenu(MHelp, 'Getting Started', @HelpContentsClick, 0);  // getting started
  AddMenu(MHelp, '-', nil, 0);  // separator
  AddMenu(MHelp, 'Visit website', @WebsiteClick, 0);  // open the web site
  AddMenu(MHelp, 'Check for updates', @UpdatesClick, 0);  // check for updates
  AddMenu(MHelp, 'Support: donate with PayPal', @DonatePayPalClick, 0);  // donate with PayPal
  AddMenu(MHelp, 'Support: donate with Venmo', @DonateVenmoClick, 0);  // donate with Venmo
  AddMenu(MHelp, 'Register', @RegisterClick, 0);  // show the license
  AddMenu(MHelp, '-', nil, 0);  // separator
  miLogging := AddMenu(MHelp, 'Logging (for troubleshooting)', @LoggingClick, 0);  // logging for troubleshooting
  miLogging.ShowAlwaysCheckable := True;  // its check box also when off (GTK)
  miLogging.Checked := FS.LoggingOn;  // show the logging state
  AddMenu(MHelp, 'Save log file...', @SaveLogClick, 0);  // save the log file
  AddMenu(MHelp, '-', nil, 0);  // separator
  AddMenu(MHelp, 'About Photo Downloader', @AboutClick, 0);  // About box
end;

{ Anchors a button to the right edge of the button panel or to the left of another button. }
procedure TMainForm.PlaceButton(B: TButton; Right: TControl; ASpace: Integer);
begin
  B.AutoSize := False;  // fixed size
  B.Width := 80;  // width 80 pixels
  B.Height := 25;  // height 25 pixels
  B.Anchors := [akTop, akRight];  // anchor to top and right
  B.AnchorSideTop.Control := pnlButtons;  // attach to the top of the button panel
  B.AnchorSideTop.Side := asrTop;  // attach at the panel's top edge
  B.BorderSpacing.Top := 9;  // space above the button
  B.AnchorSideRight.Control := Right;  // attach to the neighbor
  if Right = pnlButtons then
    B.AnchorSideRight.Side := asrRight  // right edge of the panel
  else
    B.AnchorSideRight.Side := asrLeft;  // left edge of the neighbor
  B.BorderSpacing.Right := ASpace;  // space between the buttons
end;

{ Builds the panels, buttons, date list and image grid. }
procedure TMainForm.BuildUI;
begin
  // bottom: button row, then the status row above it
  pnlButtons := TPanel.Create(Self);  // button panel at the bottom
  pnlButtons.Parent := Self;  // place it on the form
  pnlButtons.Align := alBottom;  // dock it at the bottom
  pnlButtons.Height := 44;  // height 44 pixels
  pnlButtons.BevelOuter := bvNone;  // no bevel
  pnlButtons.Caption := '';  // no text

  pnlStatus := TPanel.Create(Self);  // status panel
  pnlStatus.Parent := Self;  // place it on the form
  pnlStatus.Align := alBottom;  // dock it at the bottom
  pnlStatus.Height := 26;  // height 26 pixels
  pnlStatus.BevelOuter := bvLowered;  // lowered bevel
  pnlStatus.Caption := '';  // no text
  lblStatus := TLabel.Create(Self);  // status label
  lblStatus.Parent := pnlStatus;  // place it on the status panel
  lblStatus.Align := alClient;  // fill the panel
  lblStatus.Layout := tlCenter;  // center the text vertically
  lblStatus.BorderSpacing.Left := 6;  // space on the left
  lblStatus.Caption := 'No files';  // initial text

  btnClose := TButton.Create(Self);  // Close button
  btnClose.Parent := pnlButtons;  // place it on the button panel
  btnClose.Caption := 'Close';  // button text
  btnClose.OnClick := @CloseClick;  // click handler
  PlaceButton(btnClose, pnlButtons, 10);  // attach to the right edge
  btnDelete := TButton.Create(Self);  // Delete button
  btnDelete.Parent := pnlButtons;  // place it on the button panel
  btnDelete.Caption := 'Delete';  // button text
  btnDelete.OnClick := @DeleteClick;  // click handler
  PlaceButton(btnDelete, btnClose, 8);  // attach to the left of Close
  btnDownload := TButton.Create(Self);  // Download Selected button
  btnDownload.Parent := pnlButtons;  // place it on the button panel
  btnDownload.Caption := 'Download Selected';  // button text
  btnDownload.OnClick := @DownloadClick;  // click handler
  PlaceButton(btnDownload, btnDelete, 8);  // attach to the left of Delete
  btnDownload.Width := 120;  // room for the longer text
  btnDownloadAll := TButton.Create(Self);  // Download All button
  btnDownloadAll.Parent := pnlButtons;  // place it on the button panel
  btnDownloadAll.Caption := 'Download All';  // button text
  btnDownloadAll.OnClick := @DownloadAllClick;  // click handler
  PlaceButton(btnDownloadAll, btnDownload, 8);  // attach to the left of Download Selected
  btnDownloadAll.Width := 100;  // room for the text
  btnCustom := TButton.Create(Self);  // Custom button
  btnCustom.Parent := pnlButtons;  // place it on the button panel
  btnCustom.Caption := 'C&ustom';  // button text
  btnCustom.OnClick := @CustomClick;  // click handler
  PlaceButton(btnCustom, btnDownloadAll, 8);  // attach to the left of Download All

  // left: date selector
  pnlLeft := TPanel.Create(Self);  // left panel
  pnlLeft.Parent := Self;  // place it on the form
  pnlLeft.Align := alLeft;  // dock it at the left
  pnlLeft.Width := 180;  // width 180 pixels
  pnlLeft.BevelOuter := bvNone;  // no bevel
  pnlLeft.Caption := '';  // no text
  lblDate := TLabel.Create(Self);  // date label
  lblDate.Parent := pnlLeft;  // place it on the left panel
  lblDate.Align := alTop;  // dock it at the top
  lblDate.Caption := 'Date - Job code:';  // label text
  lblDate.BorderSpacing.Around := 4;  // space around the label
  lstDates := TListBox.Create(Self);  // list of dates
  lstDates.Parent := pnlLeft;  // place it on the left panel
  lstDates.Align := alClient;  // fill the rest of the panel
  lstDates.MultiSelect := True;  // allow several dates to be selected
  lstDates.BorderSpacing.Around := 4;  // space around the list
  lstDates.OnSelectionChange := @DateSelChange;  // selection handler
  lstDates.OnMouseDown := @DateMouseDown;  // mouse handler

  splLeft := TSplitter.Create(Self);  // splitter
  splLeft.Parent := Self;  // place it on the form
  splLeft.Align := alLeft;  // dock it at the left
  splLeft.Left := pnlLeft.Width + 1;  // position next to the left panel
  splLeft.ResizeStyle := rsUpdate;  // update the layout while dragging

  FView := TPhotoView.Create(Self);  // image grid
  FView.Parent := Self;  // place it on the form
  FView.Align := alClient;  // fill the rest of the window
  FView.BorderSpacing.Around := 4;  // space around the grid
  FView.OnSelectionChange := @ViewSelChange;  // selection handler
  FView.OnOpenItem := @OpenItem;  // handler for opening an image
  FView.OnHeaderClick := @HeaderClick;  // handler for clicks on the list header
  FView.OnThumbSizeChange := @ThumbSizeChanged;  // handler for Ctrl + mouse wheel sizing

  // right click on an image: act on the selected image(s)
  FPopup := TPopupMenu.Create(Self);  // create the pop-up menu
  FPopup.OnPopup := @PopupPopup;  // handler that sets up the items
  miPopView := AddMenu(FPopup.Items, 'View image', @PopViewClick, 0);  // view image item
  miPopLocation := AddMenu(FPopup.Items, 'Show in source folder', @PopLocationClick, 0);  // show in source folder item
  miPopDestLoc := AddMenu(FPopup.Items, 'Show in destination folder', @PopDestLocClick, 0);  // show in destination folder item
  miPopDownload := AddMenu(FPopup.Items, 'Download selected file(s)', @PopDownloadClick, 0);  // download item
  miPopDelete := AddMenu(FPopup.Items, 'Delete selected file(s) from source', @DeleteClick, 0);  // delete item
  miPopLrJpg := AddMenu(FPopup.Items, 'Save .lrprev preview(s) as JPG...', @PopLrJpgClick, 0);  // shown only when .lrprev files are selected
  miPopProps := AddMenu(FPopup.Items, 'Properties', @PopPropsClick, 0);  // properties item
  AddMenu(FPopup.Items, 'Refresh (rescan the source)', @RefreshClick, 0);  // rescan the source, same as File > Refresh (F5)
  AddMenu(FPopup.Items, '-', nil, 0);  // separator
  // the same choices as the View menu (without the Image Date Selector); their check marks are set in PopupPopup
  miPopShowDown := AddMenu(FPopup.Items, 'Show ''Downloaded'' files', @ShowDownClick, 0);  // show or hide downloaded files
  miPopShowDup := AddMenu(FPopup.Items, 'Show ''Duplicate'' files', @ShowDupClick, 0);  // show or hide duplicate files
  AddMenu(FPopup.Items, 'File Types...', @FileTypesClick, 0);  // file types item
  AddMenu(FPopup.Items, '-', nil, 0);  // separator
  miPopList := AddMenu(FPopup.Items, 'List View', @ListViewClick, 0);  // list view
  miPopSmall := AddMenu(FPopup.Items, 'Thumbnail View (small thumbnails)', @SmallViewClick, 0);  // small thumbnails
  miPopMedium := AddMenu(FPopup.Items, 'Thumbnail View (medium thumbnails)', @MediumViewClick, 0);  // medium thumbnails
  miPopLarge := AddMenu(FPopup.Items, 'Thumbnail View (large thumbnails)', @LargeViewClick, 0);  // large thumbnails
  miPopFit := AddMenu(FPopup.Items, 'Thumbnail View (fit to window)', @FitViewClick, 0);  // fit to window
  miPopFit.RadioItem := True;  // round mark
  miPopFit.GroupIndex := 1;  // same group
  miPopFit.ShowAlwaysCheckable := True;  // show the empty mark too
  miPopShowDown.ShowAlwaysCheckable := True;  // show the empty check box too (Linux hides it otherwise)
  miPopShowDup.ShowAlwaysCheckable := True;  // show the empty check box too
  miPopList.RadioItem := True;  // the three views exclude each other: round marks
  miPopList.GroupIndex := 1;  // same group as the other two views
  miPopSmall.RadioItem := True;  // round mark
  miPopSmall.GroupIndex := 1;  // same group
  miPopMedium.RadioItem := True;  // round mark
  miPopMedium.GroupIndex := 1;  // same group
  miPopMedium.ShowAlwaysCheckable := True;  // show the empty mark too
  miPopLarge.RadioItem := True;  // round mark
  miPopLarge.GroupIndex := 1;  // same group
  miPopList.ShowAlwaysCheckable := True;  // show the empty mark too
  miPopSmall.ShowAlwaysCheckable := True;  // show the empty mark too
  miPopLarge.ShowAlwaysCheckable := True;  // show the empty mark too
  FView.PopupMenu := FPopup;  // attach the menu to the grid
end;

{ ====================================================================== }
{ state                                                                   }
{ ====================================================================== }

{ Saves the settings file; errors are ignored. }
procedure TMainForm.SaveSettingsNow;
begin
  try
    FS.SaveToFile(SettingsFileName);  // write the settings file
  except
    // never let a read-only config folder stop the application
  end;
end;

{ Switches between list view and small or large thumbnails. }
procedure TMainForm.SetViewMode(M: Integer);
begin
  if M <> 0 then M := 1;  // 0 list, otherwise thumbnail cards
  FS.ViewMode := M;  // remember the mode
  FView.ThumbSize := FS.ThumbSize;  // thumbnail size in pixels
  FView.FitToWindow := FS.FitWindow;  // Fit to Window
  FView.Mode := TViewMode(M);  // apply it to the grid
  UpdateViewChecks;  // marks in the View menu
end;

{ Thumbnail cards at a preset size: 64 small, 160 medium, 320 large pixels. }
procedure TMainForm.SetThumbPreset(Size: Integer);
begin
  FS.ThumbSize := Size;  // remember the size
  FS.FitWindow := False;  // a fixed size, not Fit to Window
  SetViewMode(1);  // cards
end;

{ Ctrl + mouse wheel changed the thumbnail size in the grid. }
procedure TMainForm.ThumbSizeChanged(Sender: TObject);
begin
  FS.ThumbSize := FView.ThumbSize;  // remember the new size
  FS.FitWindow := FView.FitToWindow;  // the wheel leaves Fit to Window
  UpdateViewChecks;  // a preset is marked only when the size matches it exactly
end;

{ Marks the View menu item that matches the current view and thumbnail size. }
procedure TMainForm.UpdateViewChecks;
var
  Cards: Boolean;  // True in the thumbnail view
begin
  Cards := FS.ViewMode <> 0;  // thumbnail view
  miList.Checked := not Cards;  // list view item
  miSmall.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 64);  // small thumbnails item
  miMedium.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 160);  // medium thumbnails item
  miLarge.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 320);  // large thumbnails item
  miFit.Checked := Cards and FS.FitWindow;  // fit to window item
  miPopList.Checked := not Cards;  // the same marks in the right-click menu
  miPopSmall.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 64);
  miPopMedium.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 160);
  miPopLarge.Checked := Cards and not FS.FitWindow and (FS.ThumbSize = 320);
  miPopFit.Checked := Cards and FS.FitWindow;
end;

{ Applies the theme (View > Theme) to the window, the date list, the grid and the title bar. Menus and
  buttons keep the system's look. }
procedure TMainForm.ApplyTheme;
begin
  SetTheme(TThemeMode(FS.ThemeMode));  // pick the colors
  Color := Th.Panel;  // window background
  pnlLeft.Color := Th.Panel;  // date list panel
  pnlStatus.Color := Th.Panel;  // status bar
  pnlButtons.Color := Th.Panel;  // button panel
  lblDate.Font.Color := Th.PanelText;  // date list heading
  lblStatus.Font.Color := Th.PanelText;  // status text
  if ThemeDark or StartDark then  // dark list, or light after a dark start (the system colors are dark then)
  begin
    lstDates.Color := Th.Back;  // date list background of the theme
    lstDates.Font.Color := Th.Text;
  end
  else
  begin
    lstDates.Color := clDefault;  // the system's list colors
    lstDates.Font.Color := clDefault;
  end;
  FView.Color := Th.Back;  // grid background
  FView.Invalidate;  // draw the cards again
  ApplyTitleBar(Self, ThemeDark);  // dark title bar on Windows
  ThemeChecks;  // the menu marks and the system watch
end;

{ Marks the theme choice in View > Theme and watches the system's light/dark setting when following it. }
procedure TMainForm.ThemeChecks;
begin
  miThemeSys.Checked := FS.ThemeMode = 0;  // mark the choice
  miThemeLight.Checked := FS.ThemeMode = 1;
  miThemeDark.Checked := FS.ThemeMode = 2;
  FThemeWasDark := SystemPrefersDark;  // the system setting now
  FThemeTimer.Enabled := FS.ThemeMode = 0;  // only following the system needs a look now and then
end;

{ View > Theme: Follow system, Light or Dark. }
procedure TMainForm.ThemeClick(Sender: TObject);
begin
  if Sender = miThemeLight then FS.ThemeMode := 1  // always light
  else if Sender = miThemeDark then FS.ThemeMode := 2  // always dark
  else FS.ThemeMode := 0;  // follow the system
  SaveSettingsNow;  // remember it (a restart reads it)
  // menus, buttons and dialogs were set at start: ask first, so the window does not change halfway
  // before a restart
  if ModeIsDark(TThemeMode(FS.ThemeMode)) <> StartDark then
  begin
    if MessageDlg(AppTitle, 'Menus, buttons and dialog windows change to the new theme when Photo Downloader ' +
         'starts. Restart Photo Downloader now?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      if RestartProgram then Exit;  // closing: the new copy starts in the new theme
    // No (or the restart was canceled): the window keeps the theme it started with, as a whole (changing
    // only the parts that can change left a mix of light and dark); the choice is used at the next start
    ThemeChecks;
    SetStatus('The new theme is used from the next start of Photo Downloader.');
    Exit;
  end;
  ApplyTheme;  // show it
end;

{ Closes the program and starts it again, so menus, buttons and dialogs use the new theme. Unsaved
  profile changes are asked about first; Cancel keeps the program open (False). }
function TMainForm.RestartProgram: Boolean;
begin
  Result := False;  // not restarting yet
  if not AskSaveProfile then Exit;  // canceled
  SaveSettingsNow;  // the new theme is read at the next start
  if not StartRestartedCopy then  // the new copy waits until this one has closed
  begin
    MessageDlg(AppTitle, 'Photo Downloader could not be started again. Please start it yourself.', mtError, [mbOK], 0);
    Exit;
  end;
  FAutoClosing := True;  // no further questions while closing
  Result := True;  // restarting
  Close;  // the new copy starts when this one is gone
end;

{ The window is shown: now it exists on the screen, so the title bar can get the theme's light or dark. }
procedure TMainForm.DoShow;
begin
  inherited DoShow;
  ApplyTitleBar(Self, ThemeDark);  // dark title bar with the dark theme (Windows: the window exists now)
  Application.QueueAsyncCall(@TitleBarLater, 0);  // GTK: the window exists on the screen a moment later
end;

{ Called after the window was shown: on Linux the window manager's window exists now. }
procedure TMainForm.TitleBarLater(Data: PtrInt);
begin
  ApplyTitleBar(Self, ThemeDark);  // dark title bar with the dark theme
end;

{ Follows the system: when its light/dark setting changed, the colors change too. }
procedure TMainForm.ThemeTimerTick(Sender: TObject);
begin
  if (FS.ThemeMode = 0) and (SystemPrefersDark <> FThemeWasDark) then  // the setting changed
  begin
    FThemeWasDark := SystemPrefersDark;  // seen
    if SystemPrefersDark = StartDark then
      ApplyTheme  // back to the theme the program started with: the whole window follows
    else
      SetStatus('The system switched between light and dark: Photo Downloader follows from its next start.');  // the window stays as a whole
  end;
end;

{ Window width (client area) needed for Cols thumbnail columns. The grid loses the width of its
  vertical scroll bar and, on the left, the date list and its splitter. }
function ThumbClientWidth(View: TPhotoView; PaneW: Integer; Cols: Integer): Integer;
begin
  Result := Cols * View.CellWidthNow + View.ScrollBarWidth + 2 + PaneW;  // columns, scroll bar, frame and side panes
end;

{ Columns wanted at start-up: 4 small, 3 medium or 2 large thumbnails; the list view needs no sizing. }
function WantedColumns(Mode: TViewMode; Size: Integer): Integer;
begin
  if Mode = vmList then Exit(0);  // list view needs no sizing
  if Size <= 96 then Result := 4  // four small thumbnails
  else if Size <= 200 then Result := 3  // three medium thumbnails
  else Result := 2;  // two large thumbnails
end;

{ Sizes the window so that Cols thumbnail columns fit. }
procedure TMainForm.SizeForThumbColumns(Cols: Integer);
var
  W, PaneW, Frame, Desk: Integer;  // W: width needed; PaneW: width of the left pane; Frame: window frame; Desk: work area width
begin
  if Cols < 1 then Exit;  // nothing to do
  Desk := Screen.WorkAreaWidth;  // work area width
  PaneW := 0;  // no left pane yet
  if pnlLeft.Visible then PaneW := pnlLeft.Width + splLeft.Width;  // add the date list and splitter when shown
  Frame := Width - ClientWidth;  // window frame width
  W := ThumbClientWidth(FView, PaneW, Cols);  // width needed for the columns
  // wider than 66% of the desktop: use 2 columns
  if (Cols > 2) and (W + Frame > Desk * 66 div 100) then  // too wide for the desktop: use 2 columns
  begin
    Cols := 2;  // use 2 columns
    W := ThumbClientWidth(FView, PaneW, Cols);  // width needed for 2 columns
  end;
  FThumbCols := Cols;  // remember the columns
  if W > Desk - 24 then W := Desk - 24;  // limit to the desktop
  if W < 640 then W := 640;  // minimum width
  ClientWidth := W;  // set the width
  Left := Screen.WorkAreaLeft + (Screen.WorkAreaWidth - Width) div 2;  // center the window
  if Left < Screen.WorkAreaLeft then Left := Screen.WorkAreaLeft;  // keep it on the screen
end;

{ Centers the window on the work area of the screen, using its real size. On Linux (GTK) the
  automatic centering (poScreenCenter) happens before the window has its final size and can leave
  the window shifted to the right and down, so the start-up code calls this once the window exists. }
procedure TMainForm.CenterOnWorkArea;
begin
  if WindowState <> wsNormal then Exit;  // a maximized window needs no centering
  if ClientHeight < FWantClientH - 40 then ClientHeight := FWantClientH;  // GTK made the window too short: restore the wanted height
  Left := Screen.WorkAreaLeft + (Screen.WorkAreaWidth - Width) div 2;  // center horizontally
  Top := Screen.WorkAreaTop + (Screen.WorkAreaHeight - Height) div 2;  // center vertically
  if Left < Screen.WorkAreaLeft then Left := Screen.WorkAreaLeft;  // keep it on the screen
  if Top < Screen.WorkAreaTop then Top := Screen.WorkAreaTop;  // keep the title bar visible
end;

{ Called once the window really exists: measures the grid and corrects the width so the
  columns are not squeezed by the scroll bar, frame or screen scaling. }
procedure TMainForm.FixThumbWidth;
var
  Need, Have, Desk: Integer;  // Need: width needed; Have: width available; Desk: work area width
begin
  if (FThumbCols < 1) or (FView.Mode = vmList) or (WindowState <> wsNormal) then Exit;  // nothing to do for the list view or a maximized window
  Desk := Screen.WorkAreaWidth;  // work area width
  Have := FView.ClientWidth;  // width available
  Need := FThumbCols * FView.CellWidthNow + FView.ScrollBarWidth + 2;  // width needed
  if Have <= 0 then Exit;  // window not ready
  if (FThumbCols > 2) and (Width + (Need - Have) > Desk * 66 div 100) then  // too wide for the desktop: use 2 columns
  begin
    FThumbCols := 2;  // use 2 columns
    Need := FThumbCols * FView.CellWidthNow + FView.ScrollBarWidth + 2;  // width needed for 2 columns
  end;
  if Need = Have then Exit;  // already right
  ClientWidth := ClientWidth + (Need - Have);  // change the width by the difference
  Left := Screen.WorkAreaLeft + (Screen.WorkAreaWidth - Width) div 2;  // center the window
  if Left < Screen.WorkAreaLeft then Left := Screen.WorkAreaLeft;  // keep it on the screen
end;

{ Applies the saved settings to the menu items and controls. }
procedure TMainForm.ApplyState;
begin
  miShowDown.Checked := FS.ShowDownloaded;  // check the downloaded files item
  miShowDup.Checked := FS.ShowDuplicates;  // check the duplicates item
  miDateSel.Checked := FS.ShowDateSelector;  // check the date selector item
  pnlLeft.Visible := FS.ShowDateSelector;  // show or hide the date list
  splLeft.Visible := FS.ShowDateSelector;  // show or hide the splitter
  SetViewMode(FS.ViewMode);  // apply the view mode
  ApplyTheme;  // light or dark colors
  btnCustom.Visible := FS.CustomEnabled;  // show the custom button
  btnCustom.Caption := FS.CustomCaption;  // its caption
  UpdateMenus;  // update the menus
end;

{ Enables the menu items that depend on the settings. }
procedure TMainForm.UpdateMenus;
begin
  miAuto.Enabled := FS.AutoMenu;  // auto sequence needs the menu option
  miEject.Enabled := FSourcePath <> '';  // eject needs a source
end;

{ Shows a text in the status bar. }
procedure TMainForm.SetStatus(const S: string);
begin
  lblStatus.Caption := S;  // set the text
end;

{ Sets the window title from the user profile in use and the source folder. The profile comes right
  after the program name, so it stays visible when a long source path is cut off (the title also shows
  on the taskbar button and in Alt+Tab). }
procedure TMainForm.UpdateCaption;
var
  T: string;  // T: program name and profile
begin
  T := AppTitle;  // program name
  if FS.ProfileName <> '' then T := T + ' - Profile: ' + FS.ProfileName;  // the profile in use
  if FSourcePath = '' then  // no source
    Caption := T + ' - no image source'
  else if FDevName <> '' then  // a phone or camera (its staging folder)
    Caption := T + ' - Device ' + FDevName
  else if ExcludeTrailingPathDelimiter(FSourcePath) = ExcludeTrailingPathDelimiter(MountPointOf(FSourcePath)) then  // source is a card reader (a mount point)
    Caption := T + ' - Cardreader ' + FSourcePath  // title with the card reader
  else
    Caption := T + ' - Folder ' + FSourcePath;  // title with the folder
end;

{ Shows the number of files found during a scan and lets the user cancel it. }
procedure TMainForm.ScanProgress(Count: Integer);
var
  S: string;  // S: folder text, shortened to fit the label
begin
  SetStatus(Format('Scanning... %d files found - %s', [Count, ScanCurrentDir]));  // status text with the folder being read
  if FProg <> nil then  // progress window is open
  begin
    FProgLbl.Caption := Format('Reading the source folder... %d files found', [Count]);  // progress text
    if FProgLbl2 <> nil then  // second label exists
    begin
      S := ScanCurrentDir;  // folder being read
      while (Length(S) > 8) and (FProgLbl2.Canvas.TextWidth(S) > FProgLbl2.Width) do
        S := '...' + Copy(S, 5, MaxInt);  // too wide: drop the start of the path
      FProgLbl2.Caption := S;  // show it
    end;
    Application.ProcessMessages;  // let the window update
    if FCancel then ScanAbort := True;  // pass cancel to the scan
  end;
end;

{ Shows how many files are ready to download and enables the buttons. }
procedure TMainForm.UpdateStatus;
var
  L: TList;  // L: files to download
  N, P, I: Integer;  // N: file count; P: problem file count; I: loop counter
  S: string;  // S: status text
  It: TImageItem;  // It: current item
  AnySel, AnyAll, AnyDone: Boolean;  // AnySel/AnyAll: selected/any items to download; AnyDone: a downloaded item
begin
  if FItems.Count = 0 then  // no files
  begin
    SetStatus('No files');  // status text
    btnDownload.Enabled := False;  // nothing to download
    btnDownloadAll.Enabled := False;  // nothing to download
    btnDelete.Enabled := False;  // nothing to delete
    Exit;  // done
  end;
  L := TList.Create;  // create the list
  try
    GetDownloadList(L);  // get the files to download
    N := L.Count;  // file count
    P := 0;  // no problems yet
    for I := 0 to L.Count - 1 do  // every file
      if TImageItem(L[I]).IsProblem then Inc(P);  // count problem files
  finally
    L.Free;  // free the list
  end;
  if N = 0 then  // nothing to download
    S := 'No files to download.'  // status text
  else
  begin
    if N = 1 then S := '1 file to download' else S := Format('%d files to download', [N]);  // singular or plural text
    if P > 0 then  // some are problem files
    begin
      if P = 1 then S := S + ' of which 1 is a problem file.'  // singular text
      else S := S + Format(' of which %d are problem files.', [P]);  // plural text
    end
    else
      S := S + '.';  // end the sentence
  end;
  SetStatus(S);  // show the text
  // the buttons need only yes/no answers: one pass over the shown items, with the same rule as the download list
  AnySel := False;  // a selected item still to download
  AnyAll := False;  // any item still to download
  AnyDone := False;  // a downloaded item (for Delete)
  for I := 0 to FVisible.Count - 1 do  // every visible item
  begin
    It := TImageItem(FVisible[I]);  // current item
    if It.Status = isDownloaded then AnyDone := True;  // something to delete
    if ToDownload(It) then  // a download would copy it
    begin
      AnyAll := True;  // Download All has work
      if It.Selected then AnySel := True;  // Download Selected has work
    end;
    if AnySel and AnyAll and AnyDone then Break;  // all three known
  end;
  btnDownload.Enabled := AnySel;  // Download Selected only with selected files to download
  btnDownloadAll.Enabled := AnyAll;  // Download All when there are files to download
  btnDelete.Enabled := AnyDone;  // Delete only when a downloaded file is visible
end;

{ ====================================================================== }
{ loading and filtering                                                   }
{ ====================================================================== }

{ Scans a source folder, renders the first thumbnails and fills the grid. }
procedure TMainForm.LoadSource(const Path: string);
const
  PrerenderKeep = 300;  // number of ordinary thumbnails rendered up front
var
  I, Kept: Integer;  // I: loop counter; Kept: thumbnails kept
  Heavy: Boolean;  // Heavy: slow file type
  It: TImageItem;  // It: current item
begin
  if (FDevStage <> '') and not SameText(Path, FDevStage) then LeaveDevice;  // another source: the device is done
  FSourcePath := Path;  // remember the source
  FS.LastSource := Path;  // remember it in the settings
  UpdateCaption;  // show the new source in the title bar at once, not only after the scan
  Screen.Cursor := crHourGlass;  // show the wait cursor
  try
    // detach the grid and lists from the old images before they are freed
    FVisible.Clear;  // empty the visible list
    FView.SetItems(FVisible);  // detach the grid from the old items
    FItems.Clear;  // free the old items
    RebuildDates;  // clear the date list
    ShowProgress(0, 'Loading source folder...', True);  // show the progress window
    try
      FProgLbl.Caption := 'Reading files...';  // progress text
      ScanFolder(Path, FS, FItems, @ScanProgress);  // scan the folder
      FProgBar.Style := pbstNormal;  // progress bar is finished
      FProgBar.Max := 1;  // maximum value
      FProgBar.Position := 1;  // current value
      FProgLbl.Caption := Format('Read %d files.', [FItems.Count]);  // progress text
      Application.ProcessMessages;  // let the window update
      FCamera := '';  // no camera yet
      for I := 0 to FItems.Count - 1 do  // find the first camera name
        if ItemAt(FItems, I).Camera <> '' then
        begin  // item has a camera
          FCamera := ItemAt(FItems, I).Camera;  // remember it
          Break;  // stop searching
        end;
      EvaluateItems(FItems, FS);  // work out status and destination
      RebuildDates;  // fill the date list
      // render the thumbnails here, with a progress bar, instead of while the grid paints
      if FS.ViewMode <> 0 then  // render thumbnails when not in list view
      begin
        HeicPump := True;  // let slow decoders keep the window alive
        FProgBar2.Max := Max(1, FItems.Count);  // maximum of the second bar
        Kept := 0;  // none kept yet
        for I := 0 to FItems.Count - 1 do  // every item
        begin
          if FCancel then Break;  // stop when canceled
          It := ItemAt(FItems, I);  // current item
          if not ItemVisible(It) then Continue;  // skip hidden items
          Heavy := ThumbIsHeavy(It.FileName);  // slow file type
          // ordinary pictures beyond the first screens are rendered when they scroll into view
          if (not Heavy) and (Kept >= PrerenderKeep) then Continue;  // ordinary pictures beyond the first screens are rendered later
          FProgBar2.Position := I;  // progress position
          FProgLbl2.Caption := Format('Rendering thumbnails: %d of %d  %s',  // progress text
            [I + 1, FItems.Count, It.FileName]);
          Application.ProcessMessages;  // let the window update
          if FCancel then Break;  // stop when canceled
          EnsureThumb(It, FView.DecodeBox);  // create the thumbnail
          // slow HEIC/AVIF/TIFF thumbnails are now in the disk cache; keep the picture only
          // for the first screens so that thousands of files do not use up Windows handles
          if Heavy and (Kept >= PrerenderKeep) then ReleaseThumb(It) else Inc(Kept);  // keep or release the thumbnail
        end;
      end;
    finally
      HeicPump := False;  // stop the keep-alive
      HideProgress;  // close the progress window
    end;
    ApplyFilter;  // fill the grid
  finally
    Screen.Cursor := crDefault;  // restore the cursor
  end;
  UpdateCaption;  // update the window title
  UpdateMenus;  // update the menus
end;

{ Looks for a card reader or removable drive with a DCIM folder and loads it. }
procedure TMainForm.AutoDetectSource;
var
  L: TStringList;  // L: removable drives
  I: Integer;  // I: loop counter
  {$IFDEF WINDOWS}Root: string;{$ENDIF}  // Root: drive root (Windows only)
begin
  case FS.SourceMode of  // by source mode
    smCamera:  // phone or camera mode
      if FS.DisablePTP then  // devices are switched off
        SetStatus('Phone and camera downloads are switched off (Preferences > General > Disable PTP downloads).')
      else if not ImportFirstDevice(True) then  // the first device with a DCIM folder
        SetStatus('No phone or camera with a DCIM folder was found. Connect it, unlock it and choose File transfer.');
    smCardReader:  // card reader mode
      {$IFDEF WINDOWS}
      for I := 1 to Length(FS.DriveLetters) do  // every drive letter
        if FS.DriveLetters[I] in ['A'..'Z', 'a'..'z'] then  // valid letter
        begin
          Root := UpperCase(FS.DriveLetters[I]) + ':\';  // drive root
          if DirectoryExistsUTF8(Root) then  // drive exists
          begin
            LoadSource(Root);  // load it
            Exit;
          end;
        end;
      {$ELSE}
      begin
        // Linux has no drive letters: use the mounted removable drive that holds a DCIM folder
        L := TStringList.Create;  // create the list
        try
          ListRemovableDrives(L);  // find removable drives
          for I := 0 to L.Count - 1 do  // every drive
            if DirectoryExistsUTF8(L[I] + 'DCIM') then  // drive has a DCIM folder
            begin
              LoadSource(L[I]);  // load it
              Break;  // stop searching
            end;
        finally
          L.Free;  // free the list
        end;
      end;
      {$ENDIF}
  else
    L := TStringList.Create;  // automatic mode: create the list
    try
      ListRemovableDrives(L);  // find removable drives
      for I := 0 to L.Count - 1 do  // every drive
        if DirectoryExistsUTF8(L[I] + 'DCIM') then  // drive has a DCIM folder
        begin
          LoadSource(L[I]);  // load it
          Exit;  // a card was found
        end;
    finally
      L.Free;  // free the list
    end;
    if not FS.DisablePTP then ImportFirstDevice(True);  // no card: a phone or camera, when devices are switched on
  end;
end;

{ Works out status and destination again after a setting changed. }
{ Writes the download path ([Path] DownloadDir) and the plug-in values ([PluginOpts]) just used into the
  user profile in use, so loading the profile later downloads to the same place with the same plug-in
  values. Only these are changed in the profile file. }
procedure TMainForm.SaveDownloadToProfile;
var
  Fn: string;  // Fn: the profile file
  Ini: TMemIniFile;  // Ini: the profile as an ini object
begin
  if FS.ProfileName = '' then Exit;  // no profile in use
  Fn := ProfilesDir + FS.ProfileName + '.ini';  // its file
  if not FileExistsUTF8(Fn) then Exit;  // deleted meanwhile
  try
    Ini := TMemIniFile.Create(Fn);  // open it
    try
      Ini.WriteString('Path', 'DownloadDir', FS.DownloadDir);  // the download path just used
      SaveList(Ini, 'PluginOpts', FS.PluginOpts);  // the plug-in values just used
      Ini.UpdateFile;  // write it back
      LogThumb('profile ' + FS.ProfileName + ': download path and plug-in values saved: ' + FS.DownloadDir);  // log it
    finally
      Ini.Free;  // close it
    end;
  except
    on E: Exception do LogThumb('profile ' + FS.ProfileName + ': download path and plug-in values not saved: ' + E.Message);  // log the failure
  end;
end;

{ Looks for plug-in libraries again (after a profile was loaded) and reports problems. }
procedure TMainForm.ReloadPlugins;
var
  Err: string;  // Err: libraries that could not be loaded
begin
  Err := LoadPlugins(FS);  // list new libraries, load the switched-on ones
  if Err <> '' then  // some were switched off
    MessageDlg(AppTitle, 'These plug-ins could not be loaded and were switched off:'#13#10#13#10 + Err,
      mtWarning, [mbOK], 0);  // tell the user
end;

procedure TMainForm.Reevaluate;
begin
  EvaluateItems(FItems, FS);  // work out status and destination
  RebuildDates;  // fill the date list
  ApplyFilter;  // fill the grid
end;

{ Fills the date list from the items. }
procedure TMainForm.RebuildDates;
var
  I, J, N: Integer;  // I: loop counter; J: date index; N: scans of a date
  It: TImageItem;  // It: current item
begin
  lstDates.Items.BeginUpdate;  // stop redrawing
  try
    lstDates.Items.Clear;  // clear the list
    FDateKeys.Clear;  // clear the keys
    for I := 0 to FItems.Count - 1 do  // every item
    begin
      It := ItemAt(FItems, I);  // current item
      if It.Group <> nil then Continue;  // files of a scan are counted with their scan
      if FDateKeys.IndexOf(It.DateKey) < 0 then  // first item of this date
      begin
        FDateKeys.Add(It.DateKey);  // remember the date
        lstDates.Items.Add(It.DateKey + ' - ' + JobCodeFor(FS, It));  // add the date with its job code
      end;
    end;
    for J := 0 to FDateKeys.Count - 1 do  // add the number of scans of each date
    begin
      N := 0;
      for I := 0 to FItems.Count - 1 do
        if ItemAt(FItems, I).IsGroup and (ItemAt(FItems, I).DateKey = FDateKeys[J]) then Inc(N);
      if N = 1 then lstDates.Items[J] := lstDates.Items[J] + '  (1 scan)'
      else if N > 1 then lstDates.Items[J] := lstDates.Items[J] + Format('  (%d scans)', [N]);
    end;
  finally
    lstDates.Items.EndUpdate;  // resume redrawing
  end;
end;

{ True when the filters allow the item to be shown. }
function TMainForm.ItemVisible(It: TImageItem): Boolean;
begin
  if It.Group <> nil then Exit(False);  // a file of a scan: its scan card stands for it
  Result := not (((It.Status = isDownloaded) and (not FS.ShowDownloaded)) or  // hide downloaded files, duplicates and file types that are turned off
                 ((It.Status = isDuplicate) and (not FS.ShowDuplicates)) or
                 ((not FS.TypeShown(It.FileName)) and not It.WholeFolder));  // a folder copied whole is shown with all its files
end;

var
  GSortCol: Integer = -1;       // list view heading the pictures are sorted by (-1 = card order)
  GSortDesc: Boolean = False;  // True for descending order

{ Compares two items by the column chosen in the list view. }
function CompareVisible(A, B: Pointer): Integer;
var
  X, Y: TImageItem;  // X, Y: the items
  D: Double;  // D: time difference
begin
  X := TImageItem(A);  // first item
  Y := TImageItem(B);  // second item
  case GSortCol of  // by column
    0: Result := CompareText(X.FileName, Y.FileName);  // file name
    1:
      begin
        D := X.CaptureTime - Y.CaptureTime;  // difference of the capture times
        if D < 0 then Result := -1 else if D > 0 then Result := 1 else Result := 0;  // sign of the difference
      end;
    2: Result := CompareText(X.StatusText, Y.StatusText);  // status text
    3: Result := CompareText(X.Camera, Y.Camera);  // camera
    4: Result := CompareText(X.DestPath, Y.DestPath);  // destination
  else
    Result := 0;  // no sorting
  end;
  if GSortDesc then Result := -Result;  // reverse for descending order
  if Result = 0 then Result := X.Index - Y.Index;      // keep card order for equal values
end;

{ Opens the trash folder of the source drive. }
procedure TMainForm.ViewTrashClick(Sender: TObject);
var
  Dir: string;  // Dir: trash folder
begin
  Dir := FindTrashFolder(FSourcePath, FS.SafeDeleteFolder);  // find the trash folder
  if Dir = '' then  // no trash folder
    MessageDlg(AppTitle, 'There is no trash folder (' + FS.SafeDeleteFolder + ') on the source drive.' +  // explain
      #13#10'Files deleted from a fixed disk go to the Recycle Bin instead.', mtInformation, [mbOK], 0)
  else
    OpenDocument(Dir);  // open the folder
end;

{ Erases all files in the trash folder after asking. }
procedure TMainForm.EmptyTrashClick(Sender: TObject);
var
  Dir: string;  // Dir: trash folder
  N, Failed: Integer;  // N: file count; Failed: files that could not be erased
  Bytes: Int64;  // Bytes: total size
begin
  Dir := FindTrashFolder(FSourcePath, FS.SafeDeleteFolder);  // find the trash folder
  if Dir = '' then  // no trash folder
  begin
    MessageDlg(AppTitle, 'There is no trash folder (' + FS.SafeDeleteFolder + ') on the source drive.',  // explain
      mtInformation, [mbOK], 0);
    Exit;
  end;
  TrashStats(Dir, N, Bytes);  // count the files and bytes
  if MessageDlg(AppTitle, Format('Permanently erase %d file(s) (%.1f MB) from' + #13#10 + '%s ?' +  // ask for confirmation
    #13#10#13#10'This cannot be undone.', [N, Bytes / (1024 * 1024), Dir]), mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;
  Screen.Cursor := crHourGlass;  // show the wait cursor
  try
    EmptyTrashFolder(Dir, Failed);  // erase the files
  finally
    Screen.Cursor := crDefault;  // restore the cursor
  end;
  if Failed > 0 then  // some files remain
    MessageDlg(AppTitle, Format('%d file(s) could not be erased.', [Failed]), mtError, [mbOK], 0)  // report them
  else
    SetStatus('Trash emptied.');  // report success
end;

{ Sorts the list by the clicked column; a second click reverses the order. }
procedure TMainForm.HeaderClick(Sender: TObject; Col: Integer);
begin
  if Col = GSortCol then  // same column
    GSortDesc := not GSortDesc  // reverse the order
  else
  begin
    GSortCol := Col;  // new column
    GSortDesc := False;  // ascending
  end;
  ApplyFilter;  // apply the sorting
end;

{ Rebuilds the list of visible items and refreshes the grid. }
procedure TMainForm.ApplyFilter;
var
  I: Integer;  // I: loop counter
  It: TImageItem;  // It: current item
begin
  FVisible.Clear;  // empty the visible list
  for I := 0 to FItems.Count - 1 do  // every item
  begin
    It := ItemAt(FItems, I);  // current item
    if ItemVisible(It) then FVisible.Add(It);  // add it when the filters allow
  end;
  if GSortCol >= 0 then FVisible.Sort(@CompareVisible);  // sort when a column was chosen
  FView.SortCol := GSortCol;  // tell the grid the sort column
  FView.SortDesc := GSortDesc;  // tell the grid the sort direction
  FView.SetItems(FVisible);  // give the grid the items
  UpdateStatus;  // update the status text
  SyncDateHighlight;  // highlight the dates
end;

{ Compares two items by card order. }
function CompareByIndex(A, B: Pointer): Integer;
begin
  Result := TImageItem(A).Index - TImageItem(B).Index;  // difference of the numbers
end;

{ The one rule for what a download copies: new files and name clashes, and duplicates unless they are
  ignored. A scan counts while any of its files is still to download (its status is then new or name
  clash, uItems.GroupStatus); its files themselves are never duplicates. GetDownloadList and the buttons
  in UpdateStatus both use it, so they always agree. }
function TMainForm.ToDownload(It: TImageItem): Boolean;
begin
  if It.IsGroup then
    Result := (It.Status in [isNew, isNameClash]) and (It.Members.Count > 0)  // a scan with files still to download
  else
    Result := (It.Status in [isNew, isNameClash]) or
      ((It.Status = isDuplicate) and (not FS.IgnoreDuplicates));  // a file
end;

{ Collects the items to download: the selected ones, or all when none is selected. }
procedure TMainForm.GetDownloadList(L: TList; Scope: TDownloadScope = dsAuto);
var
  I, J: Integer;  // I: loop counter; J: file of a scan
  It: TImageItem;  // It: current item
  AnySel: Boolean;  // AnySel: True when only selected items are taken
begin
  AnySel := False;  // nothing selected yet
  if Scope <> dsAll then  // Download All ignores the selection
    for I := 0 to FVisible.Count - 1 do  // look at all visible items
      if TImageItem(FVisible[I]).Selected then  // item is selected
      begin
        AnySel := True;  // something is selected
        Break;  // enough
      end;
  if (Scope = dsSelected) and not AnySel then Exit;  // Download Selected without a selection: nothing
  for I := 0 to FVisible.Count - 1 do  // every visible item
  begin
    It := TImageItem(FVisible[I]);  // current item
    if AnySel and (not It.Selected) then Continue;  // skip unselected items when something is selected
    if It.IsGroup then  // a scan: its files that are not downloaded yet
    begin
      for J := 0 to It.Members.Count - 1 do
        if ToDownload(TImageItem(It.Members[J])) then L.Add(It.Members[J]);
      Continue;
    end;
    if ToDownload(It) then L.Add(It);  // new files and name clashes (and duplicates unless they are ignored) are downloaded
  end;
  if GSortCol >= 0 then L.Sort(@CompareByIndex);   // downloads and sequence numbers follow card order
end;

{ Selects the images of the dates chosen in the list. }
procedure TMainForm.DateSelChange(Sender: TObject; User: Boolean);
begin
  if User and (not FSyncing) then SelectDatesFromList;  // only for user changes
end;

{ thumbnails -> date list: highlight every date that has a selected image }
procedure TMainForm.SyncDateHighlight;
var
  I, J: Integer;  // I, J: loop counters
  Keys: TStringList;  // Keys: dates with a selected image
  First: Integer;  // First: index of the first highlighted date
  Seen: Boolean;  // Seen: True when a highlighted date is visible
  RC: TRect;  // RC: rectangle of a date in the list
begin
  if FSyncing then Exit;  // already synchronizing
  FSyncing := True;  // block recursion
  Keys := TStringList.Create;  // list of dates
  try
    Keys.Sorted := True;  // keep sorted
    Keys.Duplicates := dupIgnore;  // ignore duplicates
    for I := 0 to FVisible.Count - 1 do  // every visible item
      if TImageItem(FVisible[I]).Selected then  // selected item
        Keys.Add(TImageItem(FVisible[I]).DateKey);  // add its date
    for J := 0 to lstDates.Items.Count - 1 do  // every date in the list
      if J < FDateKeys.Count then  // date exists
        lstDates.Selected[J] := Keys.IndexOf(FDateKeys[J]) >= 0;  // highlight it when it has a selected image
    // scroll the date list when none of the highlighted dates is on screen
    First := -1;  // first highlighted date
    Seen := False;  // True when a highlighted date is visible
    for J := 0 to lstDates.Items.Count - 1 do  // every date in the list
      if lstDates.Selected[J] then  // highlighted date
      begin
        if First < 0 then First := J;  // remember the first one
        RC := lstDates.ItemRect(J);  // its rectangle in the list
        if (RC.Top >= 0) and (RC.Bottom <= lstDates.ClientHeight) then Seen := True;  // it is visible
      end;
    if (First >= 0) and (not Seen) then lstDates.TopIndex := First;  // bring the first highlighted date into view
  finally
    Keys.Free;  // free the list
    FSyncing := False;  // allow synchronizing again
  end;
end;

{ date list -> thumbnails: select every image of the highlighted dates }
procedure TMainForm.SelectDatesFromList;
var
  I, J: Integer;  // I, J: loop counters
  Keys: TStringList;  // Keys: highlighted dates
  It, First: TImageItem;  // It: current item; First: first selected item
begin
  FSyncing := True;  // block recursion
  Keys := TStringList.Create;  // list of dates
  try
    for J := 0 to lstDates.Items.Count - 1 do  // every date in the list
      if lstDates.Selected[J] and (J < FDateKeys.Count) then  // date is highlighted
        Keys.Add(FDateKeys[J]);  // remember it
    First := nil;  // no item selected yet
    for I := 0 to FVisible.Count - 1 do  // every visible item
    begin
      It := TImageItem(FVisible[I]);  // current item
      It.Selected := Keys.IndexOf(It.DateKey) >= 0;  // select it when its date is highlighted
      if It.Selected and (First = nil) then First := It;  // remember the first one
    end;
  finally
    Keys.Free;  // free the list
    FSyncing := False;  // allow synchronizing again
  end;
  if First <> nil then FView.ScrollToItem(First);  // scroll to the first selected image
  FView.Invalidate;  // redraw the grid
  UpdateStatus;  // update the status text
end;

{ right click on a date-job entry: change the job code for it (or the highlighted dates) }
procedure TMainForm.DateMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Idx: Integer;  // Idx: index of the clicked date
begin
  if (Button <> mbRight) or (ssLeft in Shift) then Exit;     // plain right click only
  Idx := lstDates.ItemAtPos(Point(X, Y), True);  // date under the mouse
  if Idx < 0 then Exit;  // none
  if not lstDates.Selected[Idx] then  // not highlighted yet
  begin
    FSyncing := True;  // block recursion
    try
      lstDates.ClearSelection;  // clear the highlight
      lstDates.Selected[Idx] := True;  // highlight only this date
    finally
      FSyncing := False;  // allow synchronizing again
    end;
    SelectDatesFromList;  // select its images
  end;
  ChangeJobCode;  // change the job code
end;

{ Asks for a job code and applies it to the highlighted dates, or to all dates. }
procedure TMainForm.ChangeJobCode;
var
  Job: string;  // Job: job code
  J: Integer;  // J: loop counter
  Keys: TStringList;  // Keys: highlighted dates
begin
  Keys := TStringList.Create;  // list of dates
  try
    for J := 0 to lstDates.Items.Count - 1 do  // every date in the list
      if lstDates.Selected[J] and (J < FDateKeys.Count) then  // date is highlighted
        Keys.Add(FDateKeys[J]);  // remember it
    Job := '';  // no job code yet
    if Keys.Count > 0 then Job := FS.DateJobCodes.Values[Keys[0]];  // job code stored for the first date
    if Job = BlankJobMark then  // blank on purpose
      Job := ''  // blank job code
    else if Job = '' then  // nothing stored
      Job := FS.JobCode;  // use the general job code
    if ExecuteJobCode(FS, Job, FCamera) then  // ask for the job code
    begin
      if Keys.Count > 0 then  // dates are highlighted
        for J := 0 to Keys.Count - 1 do  // every highlighted date
          if Job = '' then
            FS.DateJobCodes.Values[Keys[J]] := BlankJobMark   // blank on purpose
          else
            FS.DateJobCodes.Values[Keys[J]] := Job     // only the chosen dates
      else
      begin
        FS.JobCode := Job;  // general job code
        FS.DateJobCodes.Clear;  // remove the per-date codes
      end;
    end;
    // also covers Preferences changed from inside the job code dialog
    SaveSettingsNow;  // save the settings
    Reevaluate;  // work out the names again
  finally
    Keys.Free;  // free the list
  end;
end;

{ Enables the pop-up menu items according to the selection. }
procedure TMainForm.PopupPopup(Sender: TObject);
var
  I, NSel, NDel, NLr: Integer;  // I: loop counter; NSel: selected images; NDel: downloaded selected images; NLr: selected .lrprev files
  L: TList;  // L: files to download
  One: TImageItem;  // One: first selected image
begin
  NSel := 0;  // no selected image yet
  NDel := 0;  // no downloaded image yet
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      Inc(NSel);  // count it
      if TImageItem(FVisible[I]).Status = isDownloaded then Inc(NDel);  // count downloaded ones
    end;
  miPopView.Enabled := NSel > 0;  // view needs a selection
  miPopLocation.Enabled := NSel > 0;  // location needs a selection
  One := nil;  // first selected image
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      One := TImageItem(FVisible[I]);  // remember it
      Break;  // enough
    end;
  miPopDestLoc.Enabled := (One <> nil) and (One.Status = isDownloaded) and FileExistsUTF8(One.DestPath);  // only for files that are already in the destination
  miPopProps.Enabled := NSel > 0;  // properties need a selection
  miPopShowDown.Checked := FS.ShowDownloaded;  // check marks follow the current settings
  miPopShowDup.Checked := FS.ShowDuplicates;  // check mark for duplicates
  UpdateViewChecks;  // check marks for the view items
  L := TList.Create;  // create the list
  try
    GetDownloadList(L);  // get the files to download
    miPopDownload.Caption := Format('Download selected file(s) (%d)', [L.Count]);  // show how many
    miPopDownload.Enabled := (NSel > 0) and (L.Count > 0);  // enable when something can be downloaded
  finally
    L.Free;  // free the list
  end;
  miPopDelete.Enabled := NDel > 0;  // delete needs downloaded images
  NLr := 0;  // no selected .lrprev file yet
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected and (Pos(';' + LowerCase(ExtractFileExt(TImageItem(FVisible[I]).FileName)) + ';', LrPrevExts) > 0) then
      Inc(NLr);  // count selected .lrprev files
  miPopLrJpg.Visible := NLr > 0;  // only offered for .lrprev files
  if NLr > 0 then miPopLrJpg.Caption := Format('Save .lrprev preview(s) as JPG... (%d)', [NLr]);  // show how many
end;

{ Opens the image viewer at the double-clicked image. }
procedure TMainForm.OpenItem(Sender: TObject; Index: Integer);
begin
  ShowImageViewer(FVisible, Index);  // show the viewer
end;

{ Opens the viewer at the first selected image. }
procedure TMainForm.PopViewClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      ShowImageViewer(FVisible, I);  // show the viewer
      Exit;  // done
    end;
end;

{ Shows the first selected image in its source folder. }
procedure TMainForm.PopLocationClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
  P: string;  // P: path of the image
begin
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      P := TImageItem(FVisible[I]).FullPath;  // path of the image
      // select the file in Explorer; elsewhere just open its folder
      if not RevealFile(P) then  // show the file in the file manager
        OpenDocument(ExtractFilePath(P));  // otherwise open its folder
      Exit;  // done
    end;
end;

{ Shows the destination copy of the first selected image (already downloaded) in its folder. }
procedure TMainForm.PopDestLocClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
  P: string;  // P: path of the copy in the destination
begin
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      P := TImageItem(FVisible[I]).DestPath;  // path of the copy
      if not FileExistsUTF8(P) then Exit;  // copy is gone: nothing to show
      if not RevealFile(P) then  // show the file in the file manager
        OpenDocument(ExtractFilePath(P));  // otherwise open its folder
      Exit;  // done
    end;
end;

{ Saves the largest preview picture of every selected .lrprev file as a JPG file in a folder the user picks.
  The JPG is the picture stored in the file as it is (not re-encoded); the file keeps the .lrprev name with .jpg. }
procedure TMainForm.PopLrJpgClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser
  I, NOk, NFail: Integer;  // I: loop counter; NOk: files saved; NFail: files that failed
  It: TImageItem;  // It: item being saved
  Mem: TMemoryStream;  // Mem: the JPEG
  Info: TLrPrevInfo;  // Info: header data of the preview
  Err, Dest, Msg, Fails: string;  // Err: error text; Dest: output file; Msg: result text; Fails: names that failed
begin
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  OkFirst(D);  // Open/Save on the left on Linux too (uMsgDlg)
  try
    D.Title := 'Save .lrprev previews as JPG in folder';  // window title
    if (FLrOutDir <> '') and DirectoryExistsUTF8(FLrOutDir) then D.InitialDir := FLrOutDir;  // start in the last folder
    if not D.Execute then Exit;  // cancelled
    FLrOutDir := D.FileName;  // remember the folder
  finally
    D.Free;  // free the chooser
  end;
  NOk := 0;  // nothing saved yet
  NFail := 0;  // nothing failed yet
  Fails := '';  // no failed names
  Mem := TMemoryStream.Create;  // buffer for the JPEG
  Screen.Cursor := crHourGlass;  // wait cursor
  try
    for I := 0 to FVisible.Count - 1 do  // every visible item
    begin
      It := TImageItem(FVisible[I]);  // the item
      if not It.Selected then Continue;  // not selected
      if Pos(';' + LowerCase(ExtractFileExt(It.FileName)) + ';', LrPrevExts) = 0 then Continue;  // only .lrprev files
      try
        if LrPrevExtract(It.FullPath, Mem, Info, Err) then  // largest level found
        begin
          if It.CatalogName <> '' then  // the photo's name from the Lightroom catalog
            Dest := IncludeTrailingPathDelimiter(FLrOutDir) + ChangeFileExt(It.CatalogName, '') + '.jpg'  // output name
          else
            Dest := IncludeTrailingPathDelimiter(FLrOutDir) + ChangeFileExt(It.FileName, '') + '.jpg';  // output name
          if FileExistsUTF8(Dest) then Dest := UniqueName(Dest, True);  // never overwrite: add (1), (2) ...
          Mem.SaveToFile(Dest);  // write the JPEG
          Inc(NOk);  // count it
        end
        else
        begin
          Inc(NFail);  // count the failure
          Fails := Fails + #13#10 + It.FileName + ': ' + Err;  // remember why
        end;
      except
        on E: Exception do
        begin
          Inc(NFail);  // count the failure
          Fails := Fails + #13#10 + It.FileName + ': ' + E.Message;  // remember why
        end;
      end;
    end;
  finally
    Screen.Cursor := crDefault;  // normal cursor
    Mem.Free;  // free the buffer
  end;
  Msg := Format('%d JPG file(s) saved in %s', [NOk, FLrOutDir]);  // result text
  if NFail > 0 then Msg := Msg + #13#10 + Format('%d file(s) could not be saved:', [NFail]) + Fails;  // add the failures
  SetStatus(Format('%d JPG file(s) saved from .lrprev previews', [NOk]));  // status line
  MessageDlg('Photo Downloader', Msg, mtInformation, [mbOK], 0);  // tell the user
end;

{ Shows the properties of the first selected image. }
procedure TMainForm.PopPropsClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      ShowImageProperties(TImageItem(FVisible[I]));  // show the dialog
      Exit;  // done
    end;
end;

{ Downloads the selected files. }
procedure TMainForm.PopDownloadClick(Sender: TObject);
begin
  DoDownload(False, dsSelected);  // download the selected files, with questions
end;

{ Updates the status and the date highlight after the selection changed. }
procedure TMainForm.ViewSelChange(Sender: TObject);
var
  I, NSel: Integer;  // I: loop counter; NSel: selected images
  One: TImageItem;  // One: the only selected image
begin
  UpdateStatus;  // update the status text
  SyncDateHighlight;  // highlight the dates
  // a single selected problem image: say exactly what is wrong and what its new name would be
  NSel := 0;  // no selected image yet
  One := nil;  // none
  for I := 0 to FVisible.Count - 1 do  // every visible item
    if TImageItem(FVisible[I]).Selected then  // selected item
    begin
      Inc(NSel);  // count it
      One := TImageItem(FVisible[I]);  // remember it
    end;
  if (NSel = 1) and (One <> nil) and One.IsProblem then  // one problem image selected
    SetStatus(Format('#%d %s - %s (%s) -> %s', [One.Index, One.FileName, One.StatusText, One.ClashInfo, One.DestPath]));  // show what is wrong
end;

{ ====================================================================== }
{ downloading                                                             }
{ ====================================================================== }

{ Escapes the characters that are special in XML. }
function XmlEsc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);  // ampersand
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);  // less-than sign
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);  // greater-than sign
end;

{ Writes an XMP sidecar file with the IPTC data. }
procedure TMainForm.WriteXmp(const Dest: string);
var
  X: TStringList;  // X: lines of the XMP file
  KW: TStringList;  // KW: keywords
  I: Integer;  // I: loop counter
  V: string;  // V: value

  { Adds a language alternative tag. }
  procedure Alt(const Tag, Val: string);
  begin
    if Val <> '' then  // only when there is a value
      X.Add('   <' + Tag + '><rdf:Alt><rdf:li xml:lang="x-default">' + XmlEsc(Val) +  // add the line
        '</rdf:li></rdf:Alt></' + Tag + '>');
  end;

  { Adds a simple tag. }
  procedure Plain(const Tag, Val: string);
  begin
    if Val <> '' then X.Add('   <' + Tag + '>' + XmlEsc(Val) + '</' + Tag + '>');  // add the line when there is a value
  end;

begin
  X := TStringList.Create;  // create the line list
  KW := TStringList.Create;  // create the keyword list
  try
    X.Add('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>');  // XMP packet header
    X.Add('<x:xmpmeta xmlns:x="adobe:ns:meta/">');  // XMP metadata start
    X.Add(' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
    X.Add('  <rdf:Description rdf:about=""');  // description start
    X.Add('    xmlns:dc="http://purl.org/dc/elements/1.1/"');
    X.Add('    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">');
    V := FS.Iptc.Values['Creator'];  // creator
    if V <> '' then
      X.Add('   <dc:creator><rdf:Seq><rdf:li>' + XmlEsc(V) + '</rdf:li></rdf:Seq></dc:creator>');  // add the creator
    Alt('dc:rights', FS.Iptc.Values['Copyright']);  // copyright
    Alt('dc:title', FS.Iptc.Values['Title']);  // title
    Alt('dc:description', FS.Iptc.Values['Description']);  // description
    Plain('photoshop:Credit', FS.Iptc.Values['Credit']);  // credit
    Plain('photoshop:Source', FS.Iptc.Values['Source']);  // source
    Plain('photoshop:City', FS.Iptc.Values['City']);  // city
    Plain('photoshop:Country', FS.Iptc.Values['Country']);  // country
    KW.Delimiter := ',';  // keywords are separated by commas
    KW.StrictDelimiter := True;  // do not split at blanks
    KW.DelimitedText := FS.Iptc.Values['Keywords'];  // split the keywords
    if (KW.Count > 0) and (Trim(KW[0]) <> '') then  // keywords exist
    begin
      X.Add('   <dc:subject><rdf:Bag>');  // start of the keyword list
      for I := 0 to KW.Count - 1 do  // every keyword
        if Trim(KW[I]) <> '' then  // skip empty keywords
          X.Add('    <rdf:li>' + XmlEsc(Trim(KW[I])) + '</rdf:li>');  // add the keyword
      X.Add('   </rdf:Bag></dc:subject>');  // end of the keyword list
    end;
    X.Add('  </rdf:Description>');  // end of the description
    X.Add(' </rdf:RDF>');  // end of the RDF block
    X.Add('</x:xmpmeta>');  // end of the metadata
    X.Add('<?xpacket end="w"?>');  // end of the packet
    X.SaveToFile(ChangeFileExt(Dest, '.xmp'));  // save next to the image
  finally
    KW.Free;  // free the keywords
    X.Free;  // free the lines
  end;
end;

{ Post-processes a downloaded file: rotation, owner fields, time stamp, text file, XMP and read-only flag. }
{ The JPEG auto profile step: embeds the ICC profile chosen for the camera (or the default) into a
  downloaded JPEG. Returns 1 = done, 0 = skipped (Msg says why), -1 = failed (Msg says why). }
function TMainForm.JpegProfileStep(It: TImageItem; const Dest: string; out Msg: string): Integer;
var
  Opts, Prof, Ext: string;  // Opts: the plug-in choices; Prof: profile file; Ext: extension of the copy
begin
  Msg := '';  // nothing yet
  Ext := LowerCase(ExtractFileExt(Dest));  // extension of the downloaded copy
  if (Ext <> '.jpg') and (Ext <> '.jpeg') and (Ext <> '.jpe') then Exit(0);  // only JPEGs
  Opts := PluginValues(FS.PluginOpts, 'JPEG auto profile');  // choices from Setup...
  Prof := LineValue(Opts, 'Cam.' + It.Camera);  // profile of this camera
  if (Prof = '') or (It.Camera = '') then Prof := LineValue(Opts, 'Default');  // or the default
  if Prof = '' then
  begin
    Msg := 'no profile chosen for camera "' + It.Camera + '"';  // nothing to do
    Exit(0);
  end;
  Result := EmbedIccProfile(Dest, Prof, LineValue(Opts, 'Replace') = '1', Msg);  // embed it
  if Result = 0 then Msg := 'the JPEG already has a profile'  // left alone
  else if Result = 1 then Msg := 'profile ' + ExtractFileName(Prof);  // done
end;

{ The built-in plug-in "JPEG resolution": writes the chosen DPI (or dots per cm) into a downloaded
  JPEG without touching the image data. Returns 1 = done, 0 = skipped, -1 = failed. }
function TMainForm.JpegResolutionStep(const Dest: string; out Msg: string): Integer;
var
  Ext: string;  // Ext: extension of the copy
  V: Double;  // V: the chosen resolution
  PerCm: Boolean;  // PerCm: the resolution is in dots per centimeter
begin
  Msg := '';  // nothing yet
  Ext := LowerCase(ExtractFileExt(Dest));  // extension of the downloaded copy
  if (Ext <> '.jpg') and (Ext <> '.jpeg') and (Ext <> '.jpe') then Exit(0);  // only JPEGs
  ParseResolutionOpts(PluginValues(FS.PluginOpts, 'JPEG resolution'), V, PerCm);  // choices from Setup... (300 dpi when none)
  Result := SetJpegResolution(Dest, V, PerCm, Msg);  // write it
  if PerCm then Ext := FormatFloat('0.##', V) + ' dots/cm' else Ext := FormatFloat('0.##', V) + ' dpi';  // as text
  if Result = 0 then Msg := 'the JPEG has ' + Ext + ' already'  // nothing to change
  else if Result = 1 then Msg := Ext;  // done
end;

{ Runs the switched-on plug-in steps on a downloaded file, in the order of the Plug-ins list.
  A step that fails switches its plug-in off (so it does not run again in this download) and keeps the
  original on the card (it is not offered for deletion); FStepFails collects the failures for the
  message at the end of the download. }
procedure TMainForm.RunPluginSteps(It: TImageItem; const Dest: string);
var
  I, R: Integer;  // I: list index; R: result of a step (1 done, 0 skipped, -1 failed)
  Key, Msg, OutFile: string;  // Key: plug-in key; Msg: what the step reports; OutFile: file a program made
  X: TExtPlugin;  // X: an external-program plug-in
begin
  for I := 0 to FS.Plugins.Count - 1 do  // in the order of the Plug-ins tab
  begin
    if FS.Plugins.ValueFromIndex[I] <> '1' then Continue;  // switched off
    Key := FS.Plugins.Names[I];  // the plug-in
    OutFile := '';  // no file made yet
    if Key = 'JPEG auto profile' then
      R := JpegProfileStep(It, Dest, Msg)  // built in
    else if Key = 'JPEG resolution' then
      R := JpegResolutionStep(Dest, Msg)  // built in
    else
    begin
      X := FindExtPlugin(Key);  // an external-program plug-in?
      if (X = nil) or (not X.Available) or (not SameText(X.Hook, 'AfterFile')) or (not X.Handles(Dest)) then Continue;  // not for this file
      FProgLbl.Caption := X.Name + ': ' + It.FileName;  // progress text
      Application.ProcessMessages;  // let the window update
      R := X.Run(PluginValues(FS.PluginOpts, Key), Dest, It.FullPath, @CopyTick, OutFile, Msg);  // run the program
      if (R = 1) and (OutFile <> '') and FileExistsUTF8(OutFile) then  // a new file made by the program (for example a DNG)
      begin
        KeepFileTimes(It.FullPath, OutFile, not FS.UseCaptureTime);  // the original's creation time (and modification time)
        if FS.UseCaptureTime then FileSetDateUTF8(OutFile, FileDateFor(It.CaptureTime));  // the new file gets the capture time too
      end;
    end;
    case R of
      1: if Msg <> '' then LogThumb('plug-in ' + Key + ': ' + Dest + ': done (' + Msg + ')')  // log it
         else LogThumb('plug-in ' + Key + ': ' + Dest + ': done');
      0: LogThumb('plug-in ' + Key + ': ' + Dest + ': skipped (' + Msg + ')');  // log it
    else
      begin
        It.NoDelete := True;  // keep the original on the card
        FS.Plugins.ValueFromIndex[I] := '0';  // switch the plug-in off (decision: a failed plug-in is switched off)
        if FStepFails <> nil then FStepFails.Add(Key + ': ' + It.FileName + ': ' + Msg);  // for the message
        LogThumb('plug-in ' + Key + ': ' + Dest + ': FAILED: ' + Msg + ' - plug-in switched off');  // log it
      end;
    end;
  end;
end;

function TMainForm.PostProcess(It: TImageItem; const Dest: string): Boolean;
var
  SL: TStringList;  // SL: lines of the EXIF text file
  Names: TStringList;  // Names: folders to create
  ParentDir: string;  // ParentDir: folder above the download folder
  I: Integer;  // I: loop counter
begin
  Result := True;  // success unless writing the owner fields fails
  if It.IsOther then  // a file that is no picture (scan report, CSV ...): copied unchanged, no picture steps
  begin
    KeepFileTimes(It.FullPath, Dest, not FS.UseCaptureTime);  // the original's creation time (and modification time)
    if FS.UseCaptureTime then FileSetDateUTF8(Dest, FileDateFor(It.CaptureTime));  // its own file time
    Exit;
  end;
  // lossless turn first, so the owner fields are written into the final file
  if FS.AutoRotate and It.IsJpeg then  // turn JPEGs upright
    if AutoRotateJpegFile(Dest) < 0 then  // log a failure
      LogThumb(It.FullPath + ': could not be turned upright (' + RotateLastError + ')');  // log the reason
  if FS.WriteExifOwner and It.IsJpeg then  // add author and copyright
    Result := WriteExifOwnerFields(Dest, FS.ExifAuthor, FS.ExifCopyright);  // remember whether it worked

  // plug-in steps on the downloaded copy (the backup copy was made before and is never changed)
  RunPluginSteps(It, Dest);  // for example a color profile or a DNG copy

  // turning, color profiles and the resolution step write a new file: give it the original's times again
  KeepFileTimes(It.FullPath, Dest, not FS.UseCaptureTime);  // creation time always; modification time unless set below
  if FS.UseCaptureTime then  // use the capture time as file time
    FileSetDateUTF8(Dest, FileDateFor(It.CaptureTime));  // set the file time

  if FS.WriteExifText then  // write the EXIF text file
  begin
    SL := TStringList.Create;  // create the line list
    try
      SL.Add('File: ' + ExtractFileName(Dest));  // file name
      SL.Add('Original: ' + It.FileName);  // original name
      SL.Add('Date taken: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', It.CaptureTime));  // capture date
      SL.Add('Camera: ' + It.Camera);  // camera
      SL.Add('Serial: ' + It.Serial);  // serial number
      SL.Add('ISO: ' + IntToStr(It.ISO));  // ISO speed
      SL.SaveToFile(Dest + '.txt');  // save next to the image
    finally
      SL.Free;  // free the lines
    end;
  end;

  if FS.AddIptc and (FS.Iptc.Count > 0) then  // write the XMP file
    WriteXmp(Dest);  // write it

  if FS.PluginEnabled('Directory Maker') and (FS.PluginOpts.Values['Directory Maker'] <> '') then  // Directory Maker plug-in
  begin
    Names := TStringList.Create;  // create the list
    try
      Names.Delimiter := ',';  // names are separated by commas
      Names.StrictDelimiter := True;  // do not split at blanks
      Names.DelimitedText := FS.PluginOpts.Values['Directory Maker'];  // split the names
      ParentDir := ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(Dest)));  // folder above the download folder
      for I := 0 to Names.Count - 1 do  // every name
        if Trim(Names[I]) <> '' then  // skip empty names
          ForceDirectoriesUTF8(ParentDir + Trim(Names[I]));  // create the folder
    finally
      Names.Free;  // free the list
    end;
  end;

  // read-only last, so the steps above can still touch the file
  if FS.SaveReadOnly or (FS.PreserveReadOnly and It.IsReadOnly) then  // read-only flag last
    FileSetAttrUTF8(Dest, FileGetAttrUTF8(Dest) or faReadOnly);  // set the read-only flag
end;

{ Keeps the window alive during long copies and passes Cancel on to the copy. }
procedure TMainForm.CopyTick;
var
  T: QWord;  // T: current tick count
begin
  // keeps the progress window responsive during long copies; Cancel stops the copy
  T := GetTickCount64;  // current time
  if T - FLastTick < 80 then Exit;  // update at most every 80 ms
  FLastTick := T;  // remember the time
  Application.ProcessMessages;  // let the window update
  if FCancel then CopyAbort := True;  // stop the copy when canceled
end;

{ Handles the Cancel button of the progress window. }
procedure TMainForm.ProgCancelClick(Sender: TObject);
begin
  FCancel := True;  // stop the running work
  HeicCancel := True;  // stop the HEIC decoder
end;

{ Shows the progress window (with one or two bars) and disables the main window. }
procedure TMainForm.ShowProgress(AMax: Integer; const ACaption: string; TwoBars: Boolean);
var
  B: TButton;  // B: Cancel button
  Y: Integer;  // Y: vertical position of the button
begin
  FCancel := False;  // clear the cancel flag
  HeicCancel := False;  // clear the HEIC cancel flag
  FProgBar2 := nil;  // no second bar yet
  FProgLbl2 := nil;  // no second label yet
  FProg := TForm.CreateNew(Self);  // create the window
  FProg.Caption := ACaption;  // window title
  FProg.BorderStyle := bsDialog;  // fixed-size border
  FProg.PopupParent := Self;           // stays above the main window (needed on Linux)
  FProg.PopupMode := pmExplicit;  // owner window is set explicitly
  FProg.Position := poMainFormCenter;  // center over the main window
  FProg.ClientWidth := 440;  // window width
  FProgLbl := TLabel.Create(FProg);  // label
  FProgLbl.Parent := FProg;  // place it on the window
  FProgLbl.SetBounds(12, 12, 416, 18);  // position and size it
  FProgLbl.AutoSize := False;  // keep the size
  FProgBar := TProgressBar.Create(FProg);  // progress bar
  FProgBar.Parent := FProg;  // place it on the window
  FProgBar.SetBounds(12, 38, 416, 20);  // position and size it
  FProgBar.Min := 0;  // smallest value
  if AMax <= 0 then
    FProgBar.Style := pbstMarquee          // length not known yet (reading a folder)
  else
    FProgBar.Max := AMax;  // set the maximum
  Y := 72;  // button position without the second bar
  if TwoBars then  // second bar wanted
  begin
    FProgLbl2 := TLabel.Create(FProg);  // second label
    FProgLbl2.Parent := FProg;  // place it on the window
    FProgLbl2.SetBounds(12, 70, 416, 18);  // position and size it
    FProgLbl2.AutoSize := False;  // keep the size
    FProgLbl2.Caption := 'Rendering thumbnails: waiting';  // initial text
    FProgBar2 := TProgressBar.Create(FProg);  // second progress bar
    FProgBar2.Parent := FProg;  // place it on the window
    FProgBar2.SetBounds(12, 96, 416, 20);  // position and size it
    FProgBar2.Min := 0;  // smallest value
    FProgBar2.Max := 1;  // largest value
    Y := 130;  // button position with the second bar
  end;
  FProg.ClientHeight := Y + 38;  // window height
  B := TButton.Create(FProg);  // Cancel button
  B.Parent := FProg;  // place it on the window
  B.Caption := 'Cancel';  // button text
  B.SetBounds(348, Y, 80, 25);  // position and size it
  B.OnClick := @ProgCancelClick;  // click handler
  FProg.Show;  // show the window
  Self.Enabled := False;  // disable the main window
  Application.ProcessMessages;  // let the window update
end;

{ Closes the progress window and enables the main window. }
procedure TMainForm.HideProgress;
begin
  Self.Enabled := True;  // enable the main window
  FreeAndNil(FProg);  // free the progress window
end;

{ Copies the files to download; returns True when all were copied and nothing was canceled. }
function TMainForm.DoDownload(Silent: Boolean; Scope: TDownloadScope = dsAuto): Boolean;
var
  L: TList;  // L: files to download
  I, Done, Skipped, Failed, Problems, ExifFail: Integer;  // I: loop counter; Done: files copied; Skipped: files skipped; Failed: files that failed; Problems: problem files; ExifFail: owner field failures
  JpgFail: Integer;  // JpgFail: .jpg files that could not be made from .lrprev files ("Save both")
  JDest, JHash, JErr: string;  // JDest, JHash, JErr: destination, MD5 and error text of that .jpg
  TotalKb, DoneKb: Int64;  // TotalKb: total size; DoneKb: size copied
  It: TImageItem;  // It: current item
  Dest, Msg, Hash, Err, BDest, BHash, BErr: string;  // Dest: destination; Msg: message text; Hash: MD5 of the source; Err: error text; BDest, BHash, BErr: the same for the backup copy
  UniqueMode: Boolean;  // True when problem files are renamed instead of skipped
  R: TModalResult;  // R: answer of the question dialog
  CR: TCopyResult;  // CR: result of a copy
  Attempt, BackupFail, Verified: Integer;  // Attempt: copy attempt; BackupFail: failed backup copies; Verified: verified copies
  OldOpts: string;  // OldOpts: plug-in values before the plug-ins asked for new ones
begin
  Result := False;  // assume failure
  Done := 0; Skipped := 0; Failed := 0; Problems := 0; ExifFail := 0;  // clear the counters
  JpgFail := 0;  // no .jpg failed yet
  BackupFail := 0; Verified := 0;  // clear the counters
  UniqueMode := FS.AutoRenameClash;  // rename name clashes automatically when that option is on; otherwise skip problem files by default
  Msg := '';  // no message yet
  if FStepFails = nil then FStepFails := TStringList.Create;  // plug-in steps that fail
  FStepFails.Clear;  // none yet
  if not Silent then  // plug-ins that ask for values (for example project numbers for the folder name)
  begin
    OldOpts := FS.PluginOpts.Text + FS.DownloadDir;  // values and destination before asking
    if not AskPluginValues(FS) then Exit;  // canceled: download nothing
    if FS.PluginOpts.Text + FS.DownloadDir <> OldOpts then  // new values or destination: other folder and file names
    begin
      SaveSettingsNow;  // keep the values
      Reevaluate;  // work out the names again
    end;
  end;
  L := TList.Create;  // create the list
  try
    GetDownloadList(L, Scope);  // get the files to download
    if L.Count = 0 then  // nothing to download
    begin
      if Silent then
        // nothing to say
      else if Scope = dsSelected then  // nothing selected, or only files already downloaded
        MessageDlg(AppTitle, 'No selected files to download. Select the files to download, or click Download All.',
          mtInformation, [mbOK], 0)
      else
        MessageDlg(AppTitle, 'There are no files to download.', mtInformation, [mbOK], 0);  // tell the user
      Exit;  // nothing to do
    end;
    for I := 0 to L.Count - 1 do  // every file
      if TImageItem(L[I]).IsProblem then Inc(Problems);  // count problem files
    if (Problems > 0) and FS.AutoRenameClash then  // rename name clashes without asking
      UniqueMode := True
    else if (Problems > 0) and (not Silent) then  // ask what to do with problem files
    begin
      R := MessageDlg(AppTitle,  // ask the user
        Format('%d file(s) have a name clash with another file or an existing file.'#13#10#13#10 +
          'Yes = download them anyway, adding -1, -2 ... to the file name'#13#10 +
          'No = skip the problem files'#13#10 +
          'Cancel = do not download anything', [Problems]),
        mtWarning, [mbYes, mbNo, mbCancel], 0);
      if R = mrCancel then Exit;  // canceled by the user
      UniqueMode := R = mrYes;  // rename problem files when the user chose Yes
    end;
    if (not Silent) and FS.AddIptc and FS.PromptIptc then  // ask for the IPTC data
      if not ExecuteIptc(FS.Iptc) then Exit;  // stop when canceled

    TotalKb := 0;  // total size is zero
    for I := 0 to L.Count - 1 do Inc(TotalKb, Max(1, TImageItem(L[I]).Size div 1024));  // add the size of every file
    DoneKb := 0;  // nothing copied yet
    ShowProgress(Integer(Min(TotalKb, Int64(MaxInt div 2))), 'Downloading...');  // show the progress window
    try
      for I := 0 to L.Count - 1 do  // every file
      begin
        if FCancel then Break;  // stop when canceled
        It := TImageItem(L[I]);  // current file
        FProgBar.Position := Integer(Min(DoneKb, Int64(FProgBar.Max)));  // progress position
        FProgLbl.Caption := Format('Copying %d of %d: %s  (%s)',  // progress text
          [I + 1, L.Count, It.FileName, FormatSize(It.Size)]);
        Application.ProcessMessages;  // let the window update
        if FCancel then Break;  // stop when canceled

        if It.IsProblem and (not UniqueMode) then  // skip problem files
        begin
          Inc(Skipped);  // count the skipped file
          Continue;  // next file
        end;
        Dest := ComputeDest(FS, It, FS.SeqNext, FSession + 1);  // destination of the file
        if FileExistsUTF8(Dest) then  // destination exists
        begin
          if It.Status = isDuplicate then  // duplicate file (only listed when duplicates are not ignored)
          begin
            if FS.RenameDuplicates then  // rename duplicates
            begin
              LogThumb('duplicate ' + It.FullPath + ': ' + Dest + ' exists, renamed');  // log the decision
              Dest := UniqueName(Dest, True);  // add (1), (2) ... to the name
            end
            else
            begin
              LogThumb('duplicate ' + It.FullPath + ' skipped: ' + Dest + ' exists and "Download duplicates as (1), (2) ..." is off');  // log the reason
              Inc(Skipped);  // the name is taken: skip the duplicate
              Continue;  // next file
            end;
          end
          else if UniqueMode then  // rename problem files
            Dest := UniqueName(Dest, FS.AutoRenameClash)  // add -1, -2 ... (or (1), (2) ...) to the name
          else
          begin
            Inc(Skipped);  // count the skipped file
            Continue;  // next file
          end;
        end;
        if not ForceDirectoriesUTF8(ExtractFilePath(Dest)) then  // create the destination folder
        begin
          Msg := 'Cannot create the folder:'#13#10 + ExtractFilePath(Dest);  // message
          Inc(Failed);  // count the failure
          Break;  // stop copying
        end;
        // copy (and read back to compare checksums); one retry before giving up
        CopyAbort := False;  // clear the abort flag
        CopyPump := @CopyTick;  // let the copy keep the window alive
        Attempt := 0;  // first attempt
        repeat
          Inc(Attempt);  // count the attempt
          if FS.VerifyCopy then
            FProgLbl.Caption := Format('Copying and verifying %d of %d: %s  (%s)',  // progress text
              [I + 1, L.Count, It.FileName, FormatSize(It.Size)]);
          if LrPrevJpgOnly(FS, It) then  // a Lightroom preview downloaded as a .jpg only
            CR := SaveLrPrevJpg(It.FullPath, Dest, FS.VerifyCopy, Hash, Err)  // write its preview picture (Dest ends in .jpg)
          else
            CR := CopyFileChecked(It.FullPath, Dest, FS.VerifyCopy, Hash, Err);  // copy and verify
          if CR = crOk then Break;  // copy is good
          LogThumb('copy failed (' + IntToStr(Attempt) + '): ' + It.FullPath + ' -> ' + Dest + ': ' + Err);  // log the failure
        until (CR = crCanceled) or (Attempt >= 2);  // try twice unless canceled
        if CR = crCanceled then Break;  // canceled by the user
        if CR <> crOk then  // copy failed
        begin
          Msg := 'Could not copy:'#13#10 + It.FullPath + #13#10'to'#13#10 + Dest;  // message
          if Err <> '' then Msg := Msg + #13#10#13#10 + Err;  // add the reason
          if CR = crVerifyFailed then
            Msg := Msg + #13#10#13#10'The bad copy was deleted. The original is untouched.';  // add a note about the bad copy
          Inc(Failed);  // count the failure
          Break;  // stop copying
        end;
        if FS.VerifyCopy then Inc(Verified);  // count the verified copy
        // "Save both": a .jpg of the Lightroom preview next to the downloaded .lrprev file
        if FS.LrPrevAsJpg and FS.LrPrevKeepBoth and
           (Pos(';' + LowerCase(ExtractFileExt(It.FileName)) + ';', LrPrevExts) > 0) then
        begin
          JDest := ChangeFileExt(Dest, '.jpg');  // same name with .jpg
          if FileExistsUTF8(JDest) then JDest := UniqueName(JDest, True);  // never overwrite: add (1), (2) ...
          if SaveLrPrevJpg(It.FullPath, JDest, FS.VerifyCopy, JHash, JErr) = crOk then  // write the preview picture
          begin
            KeepFileTimes(It.FullPath, JDest, not FS.UseCaptureTime);  // the .lrprev file's creation time
            if FS.UseCaptureTime then  // same file time as the .lrprev file
              FileSetDateUTF8(JDest, FileDateFor(It.CaptureTime));  // set the file time
          end
          else
          begin
            Inc(JpgFail);  // count the failure (the .lrprev file itself was downloaded)
            LogThumb('could not save ' + JDest + ' from ' + It.FullPath + ': ' + JErr);  // log the reason
          end;
        end;
        It.NoDelete := False;  // the original may be deleted
        It.BackupPath := '';  // no backup yet
        // second copy, made from the verified download before it is changed by rotation or metadata
        if FS.BackupOn and (Trim(FS.BackupDir) <> '') then  // backup copy wanted
        begin
          BDest := BackupDestFor(FS, It, FS.SeqNext, FSession + 1, Dest);  // backup destination
          CR := crFailed;  // assume failure
          BErr := 'could not create the backup folder';  // reason if the folder cannot be created
          if ForceDirectoriesUTF8(ExtractFilePath(BDest)) then  // create the backup folder
          begin
            if FileExistsUTF8(BDest) then  // file exists in the backup folder
            begin
              // an identical file is already there (e.g. an earlier run); otherwise keep both
              if HashOfFile(BDest) = Hash then  // identical file is already there
                CR := crOk  // nothing to copy
              else
                BDest := UniqueName(BDest);  // keep both files
            end;
            if CR <> crOk then  // copy needed
            begin
              Attempt := 0;  // first attempt
              repeat
                Inc(Attempt);  // count the attempt
                FProgLbl.Caption := Format('Backup copy %d of %d: %s', [I + 1, L.Count, It.FileName]);  // progress text
                CR := CopyFileChecked(Dest, BDest, FS.VerifyCopy, BHash, BErr);  // copy and verify
                if CR = crOk then Break;  // copy is good
                LogThumb('backup copy failed (' + IntToStr(Attempt) + '): ' + BDest + ': ' + BErr);  // log the failure
              until (CR = crCanceled) or (Attempt >= 2);  // try twice unless canceled
            end;
          end;
          if CR = crCanceled then  // canceled by the user
          begin
            It.NoDelete := True;  // keep the original
            Break;  // stop copying
          end;
          if CR = crOk then  // backup is good
            It.BackupPath := BDest  // remember the backup path
          else
          begin
            Inc(BackupFail);  // count the failure
            It.NoDelete := True;       // never offer to delete an original that is not backed up
            if BackupFail = 1 then  // first failure
              Msg := 'The backup copy of this file failed:'#13#10 + It.FullPath + #13#10 + BErr;  // message
          end;
        end;
        if not PostProcess(It, Dest) then Inc(ExifFail);  // post-process the file
        It.Status := isDownloaded;  // mark the item as downloaded
        It.DestPath := Dest;  // remember the destination
        FLastFile := Dest;  // remember the last file
        FLastDir := ExtractFilePath(Dest);  // remember its folder
        Inc(FS.SeqNext);  // next sequence number
        Inc(FSession);  // next session number
        Inc(Done);  // count the file
        Inc(DoneKb, Max(1, It.Size div 1024));  // add its size
        FProgBar.Position := Integer(Min(DoneKb, Int64(FProgBar.Max)));  // progress position
      end;
    finally
      CopyPump := nil;  // stop the keep-alive
      CopyAbort := False;  // clear the abort flag
      HideProgress;  // close the progress window
    end;
  finally
    L.Free;  // free the list
  end;

  if FStepFails.Count > 0 then  // plug-in steps failed: their plug-ins were switched off
  begin
    if not Silent then
      MessageDlg(AppTitle, 'These plug-in steps failed. The plug-ins were switched off (switch them on again on the ' +
        'Plug-ins tab after fixing the cause), and these files are not offered for deletion from the source:'#13#10#13#10 +
        FStepFails.Text, mtWarning, [mbOK], 0);  // tell the user
  end;
  SaveSettingsNow;  // save the sequence number (and plug-ins switched off by a failed step)
  if Done > 0 then SaveDownloadToProfile;  // the profile in use remembers where it downloaded to, and the plug-in values
  ApplyFilter;  // refresh the grid
  if Failed > 0 then  // a copy failed
    MessageDlg(AppTitle, Msg, mtError, [mbOK], 0)  // show the message
  else
  begin
    if FCancel then  // canceled
      SetStatus(Format('Download canceled after %d file(s).', [Done]))  // status text
    else if Skipped > 0 then  // some files were skipped
      SetStatus(Format('%d file(s) downloaded, %d skipped.', [Done, Skipped]))  // status text
    else
      SetStatus(Format('%d file(s) downloaded.', [Done]));  // status text
    if Verified > 0 then  // add the verified count
      SetStatus(lblStatus.Caption + Format(' %d verified.', [Verified]));  // status text
    if ExifFail > 0 then  // owner fields failed
      SetStatus(lblStatus.Caption + Format(' Author/copyright could not be written to %d file(s).', [ExifFail]));  // status text
    if JpgFail > 0 then  // .jpg files from .lrprev files failed
      SetStatus(lblStatus.Caption + Format(' %d .jpg file(s) could not be made from .lrprev previews (see the log).', [JpgFail]));  // status text
    if BackupFail > 0 then  // backup copies failed
    begin
      SetStatus(lblStatus.Caption + Format(' %d backup copy(ies) FAILED.', [BackupFail]));  // status text
      MessageDlg(AppTitle, Format('%d file(s) could not be copied to the backup folder.'#13#10 +  // warn the user
        'They stay in the download folder, but will not be offered for deletion from the image source.'#13#10#13#10, [BackupFail]) + Msg,
        mtWarning, [mbOK], 0);
    end;
  end;
  Result := (Failed = 0) and (not FCancel);  // success when nothing failed and the user did not cancel
end;

{ True when the source file was downloaded and the copy exists. }
function TMainForm.CanDeleteSource(It: TImageItem): Boolean;
begin
  // a source file may only be removed once it has been downloaded
  // and the copy really exists in the destination
  Result := (It.Status = isDownloaded) and (not It.NoDelete) and (It.DestPath <> '') and  // downloaded, not protected and the copy exists
    FileExistsUTF8(It.DestPath);
  if Result and (FDevStage <> '') then  // from a phone or camera: the device must allow deleting it
    Result := (DeviceFileOf(It) <> nil) and DeviceFileOf(It).CanDelete;
end;

{ Deletes the downloaded source files after asking; they go to the trash when safe delete is on. }
{ Removes a folder and its subfolders when they hold no files (after the files of a scan were deleted). }
procedure RemoveEmptyFolders(const Dir: string);
var
  SR: TSearchRec;  // SR: an entry of the folder
begin
  if FindFirstUTF8(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
        RemoveEmptyFolders(IncludeTrailingPathDelimiter(Dir) + SR.Name);  // empty subfolders first
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
  RemoveDirUTF8(Dir);  // fails, and keeps the folder, when something is still in it
end;

procedure TMainForm.DeleteFiles(OnlyDownloaded, Silent: Boolean);
var
  L, E: TList;  // L: candidate files; E: files that may be deleted
  I, J, Fail, Kept: Integer;  // I: loop counter; J: file of a scan; Fail: files that failed; Kept: files that stay
  It: TImageItem;  // It: current item
  AnySel: Boolean;  // AnySel: True when the user selected something
  Msg, Where, LastWhere: string;  // Msg: message; Where: where a file went; LastWhere: last trash location
  Ok: Boolean;  // Ok: True when a file was deleted
  DF: TDeviceFile;  // DF: the device file of a staged item
  DevErr, FirstErr: string;  // DevErr: why a device file was not deleted; FirstErr: the first such reason
begin
  FirstErr := '';  // no device error yet
  LastWhere := '';  // no location yet
  L := TList.Create;  // candidate list
  E := TList.Create;  // deletable list
  try
    if OnlyDownloaded then  // only downloaded files
    begin
      for I := 0 to FItems.Count - 1 do  // every item (the files of a scan count one by one; the scan item itself is no file)
        if (ItemAt(FItems, I).Status = isDownloaded) and not ItemAt(FItems, I).IsGroup then L.Add(FItems[I]);  // downloaded file
    end
    else
    begin
      AnySel := False;  // nothing selected yet
      for I := 0 to FVisible.Count - 1 do  // look at all visible items
        if TImageItem(FVisible[I]).Selected then AnySel := True;  // selected item
      for I := 0 to FVisible.Count - 1 do  // every visible item
        if (not AnySel) or TImageItem(FVisible[I]).Selected then  // selected files, or all when nothing is selected
          if TImageItem(FVisible[I]).IsGroup then  // a scan: all its files
            for J := 0 to TImageItem(FVisible[I]).Members.Count - 1 do L.Add(TImageItem(FVisible[I]).Members[J])
          else
            L.Add(FVisible[I]);
    end;
    if L.Count = 0 then Exit;  // nothing to do

    for I := 0 to L.Count - 1 do  // every candidate
      if CanDeleteSource(TImageItem(L[I])) then E.Add(L[I]);  // keep those that may be deleted
    Kept := L.Count - E.Count;  // files that stay

    if E.Count = 0 then  // nothing can be deleted
    begin
      if not Silent then  // tell the user unless silent
        MessageDlg(AppTitle,
          'Nothing was deleted. Only files that have been downloaded and exist in ' +
          'the destination can be deleted from the image source.' +
          BoolToStr(FDevStage <> '', #13#10#13#10'Some devices (an iPhone, for example) do not allow deleting files.', ''),
          mtInformation, [mbOK], 0);
      Exit;  // nothing to do
    end;
    if not Silent then  // ask unless silent
    begin
      Msg := Format('Delete %d downloaded file(s) from the image source?'#13#10 +  // question
        'Each one has been checked to exist in the destination.', [E.Count]);
      if Kept > 0 then  // some files stay
        Msg := Msg + #13#10 + Format('%d selected file(s) have not been downloaded and will be kept.', [Kept]);  // add a note
      if FDevStage <> '' then  // a phone or camera
        Msg := Format('Delete %d downloaded file(s) from the device %s?'#13#10 +
          'Each one has been checked to exist in the destination.', [E.Count, FDevName]) +
          BoolToStr(Kept > 0, #13#10 + Format('%d selected file(s) cannot be deleted and will be kept.', [Kept]), '') +
          #13#10#13#10'Devices have no Recycle Bin: this cannot be undone.'
      else if FS.SafeDelete then  // safe delete is on
        Msg := Msg + #13#10#13#10'Safe delete is on. The files are moved to the Recycle Bin,' +  // explain the trash
          #13#10'or, on a card or other removable drive, to a hidden' +
          #13#10'trash folder (' + FS.SafeDeleteFolder + ') on the same drive.'
      else
        Msg := Msg + #13#10#13#10'This cannot be undone.';  // warn that it cannot be undone
      if MessageDlg(AppTitle, Msg, mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;  // ask the user
    end;
    Fail := 0;  // no failures yet
    for I := 0 to E.Count - 1 do  // every file to delete
    begin
      It := TImageItem(E[I]);  // current item
      if It.IsReadOnly then FileSetAttrUTF8(It.FullPath, 0);  // clear the read-only flag
      if FDevStage <> '' then  // a phone or camera: delete on the device, then the staged copy
      begin
        DF := DeviceFileOf(It);  // where it came from
        Ok := (DF <> nil) and DeleteDeviceFile(DF.Id, DevErr);  // delete on the device
        if (not Ok) and (FirstErr = '') then
          if DF = nil then FirstErr := It.FileName + ': not from this device' else FirstErr := It.FileName + ': ' + DevErr;
        if Ok then DeleteFileUTF8(It.FullPath);  // the staged copy too
        Where := '';  // no trash on a device
      end
      else if FS.SafeDelete then  // safe delete
        Ok := SafeDeleteFile(It.FullPath, FS.SafeDeleteFolder, Where)  // move to the trash
      else
      begin
        Ok := DeleteFileUTF8(It.FullPath);  // delete for good
        Where := '';  // no trash location
      end;
      if Ok then  // file deleted
      begin
        if Where <> '' then LastWhere := Where;  // remember the trash location
        if It.Group <> nil then It.Group.Members.Remove(It);  // no longer part of its scan
        FItems.Remove(It)          // the list owns and frees the item
      end
      else
        Inc(Fail);  // count the failure
    end;  // end of loop
    for I := FItems.Count - 1 downto 0 do  // a scan whose files are all deleted: its folder goes too (when empty) and its card
      if ItemAt(FItems, I).IsGroup and (ItemAt(FItems, I).Members.Count = 0) then
      begin
        RemoveEmptyFolders(ItemAt(FItems, I).FullPath);  // the scan folder and its subfolders, when nothing is left in them
        FItems.Delete(I);  // frees the scan item
      end;
    for I := 0 to FItems.Count - 1 do  // renumber the remaining items
      ItemAt(FItems, I).Index := I + 1;  // set the grid number
    RebuildDates;  // refresh the date list
    ApplyFilter;  // refresh the grid
    if (LastWhere <> '') and (Fail = 0) then  // files went to the trash
      SetStatus(Format('%d file(s) moved to %s.', [E.Count, LastWhere]));  // tell the user where
    if Fail > 0 then  // some failed
      MessageDlg(AppTitle, Format('%d file(s) could not be deleted.', [Fail]) +
        BoolToStr(FirstErr <> '', #13#10#13#10 + FirstErr, ''), mtError, [mbOK], 0);  // report them
  finally
    E.Free;  // free the deletable list
    L.Free;  // free the candidate list
  end;
end;

{ Ejects the removable drive of the source; returns True on success. }
function TMainForm.DoEject(Silent: Boolean): Boolean;
var
  Root: string;  // Root: mount point of the source
begin
  Result := False;  // assume failure
  if FSourcePath = '' then Exit;  // no source
  if FDevStage <> '' then  // a phone or camera: nothing to eject, the device is done as a source
  begin
    LeaveDevice;  // downloaded staged copies are removed
    FItems.Clear;  // empty the item list
    FVisible.Clear;  // empty the visible list
    FSourcePath := '';  // no source any more
    RebuildDates;  // clear the date list
    ApplyFilter;  // refresh the grid
    UpdateCaption;  // update the window title
    UpdateMenus;  // update the menus
    if not Silent then SetStatus('The device can be unplugged.');  // tell the user
    Exit(True);
  end;
  Root := MountPointOf(FSourcePath);  // mount point of the source
  {$IFDEF WINDOWS}
  if Root = '' then       // Windows: any drive letter may be ejected, as before
  {$ELSE}
  if (Root = '') or (not IsRemovableMount(Root)) then
  {$ENDIF}
  begin
    if not Silent then
      MessageDlg(AppTitle, 'The current source is not a removable drive.', mtInformation, [mbOK], 0);  // explain
    Exit;
  end;
  if EjectDrive(Root) then  // eject the drive
  begin
    FItems.Clear;  // empty the item list
    FVisible.Clear;  // empty the visible list
    FSourcePath := '';  // no source any more
    RebuildDates;  // clear the date list
    ApplyFilter;  // refresh the grid
    UpdateCaption;  // update the window title
    UpdateMenus;  // update the menus
    Result := True;  // success
  end
  else if not Silent then
    MessageDlg(AppTitle, 'The media could not be ejected. Close any programs using it and try again.',  // explain
      mtWarning, [mbOK], 0);
end;

{ Runs the custom command with %f and %d replaced by the last file and folder. }
procedure TMainForm.LaunchCustom;
var
  Cmd: string;  // Cmd: command line
begin
  if (not FS.CustomEnabled) or (Trim(FS.CustomCmd) = '') then Exit;  // nothing to do
  Cmd := StringReplace(FS.CustomCmd, '%f', FLastFile, [rfReplaceAll]);  // insert the last file
  Cmd := StringReplace(Cmd, '%d', FLastDir, [rfReplaceAll]);  // insert its folder
  try
    LaunchCommand(Cmd);  // start the command
  except
    on E: Exception do
      MessageDlg(AppTitle, 'Could not run the custom command:'#13#10 + E.Message, mtError, [mbOK], 0);  // tell the user
  end;
end;

{ Runs the automatic sequence: download, delete, eject, launch, exit. }
procedure TMainForm.RunAutoSequence;
begin
  if FItems.Count = 0 then Exit;  // nothing to do
  if FS.AutoMenu and FS.AutoPrompt then  // ask first when the menu option and prompt are on
    if MessageDlg(AppTitle, 'Start the automatic download sequence?', mtConfirmation,  // ask the user
         [mbYes, mbNo], 0) <> mrYes then Exit;
  if FS.AutoDownload then  // download step
    if not DoDownload(True) then Exit;     // stop on error or cancel
  if FS.AutoDelete then DeleteFiles(True, True);  // delete step
  if FS.AutoSoftEject then  // eject step
    if not DoEject(True) then Exit;  // stop when the eject failed
  if FS.AutoLaunch then LaunchCustom;  // launch step
  if FS.AutoExit then  // exit step
  begin
    FAutoClosing := True;  // hands-free: do not stop at the profile question
    Close;  // close the program
  end;
end;

{ ====================================================================== }
{ phones and cameras by USB (uDevices, docs/MTP_Plan.md)                  }
{ ====================================================================== }

{ File > Import from Device...: choose a device and folders, import them and show them. }
procedure TMainForm.ImportDeviceClick(Sender: TObject);
var
  DevName, DevId: string;  // DevName, DevId: the chosen device
  Names, Ids: TStringList;  // Names, Ids: the chosen folders
begin
  Names := TStringList.Create;
  Ids := TStringList.Create;
  try
    if ExecuteDeviceImport(DevName, DevId, Names, Ids) then  // the window
      ImportFromDevice(DevName, DevId, Names, Ids, False);  // copy and show
  finally
    Names.Free;
    Ids.Free;
  end;
end;

{ Progress while listing device files; False when canceled. }
function TMainForm.DevCountProgress(Count: Integer): Boolean;
begin
  if (FProg <> nil) and (GetTickCount64 - FLastTick > 100) then  // at most ten updates a second
  begin
    FLastTick := GetTickCount64;
    FProgLbl.Caption := Format('Listing the files on the device... %d found', [Count]);  // progress text
    Application.ProcessMessages;  // let the window update and Cancel work
  end;
  Result := not FCancel;
end;

{ Progress while copying a device file; False when canceled. }
function TMainForm.DevBytesProgress(Bytes: Int64): Boolean;
begin
  if (FProg <> nil) and (GetTickCount64 - FLastTick > 100) then  // at most ten updates a second
  begin
    FLastTick := GetTickCount64;
    FProgBar.Position := Min(FProgBar.Max, FDevDoneKb + Bytes div 1024);  // KB done in all
    Application.ProcessMessages;  // let the window update and Cancel work
  end;
  Result := not FCancel;
end;

{ Removes the files below Dir that are not in Keep (staging paths; stale copies of earlier imports). }
procedure PruneStaging(const Dir: string; Keep: TStringList);
var
  SR: TSearchRec;  // SR: an entry of the folder
begin
  if FindFirstUTF8(Dir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then PruneStaging(Dir + SR.Name + PathDelim, Keep);  // subfolder
      end
      else if Keep.IndexOf(Dir + SR.Name) < 0 then
        DeleteFileUTF8(Dir + SR.Name);  // no longer imported from the device
    until FindNextUTF8(SR) <> 0;
  finally
    FindCloseUTF8(SR);
  end;
end;

{ Copies the device folders (FolderIds, shown as FolderNames) into the device's staging folder and loads
  it as the source. Files staged before (same size and time) are not copied again; staged files no
  longer on the device are removed. False when canceled or nothing could be read. Silent: no message
  about failed files (Refresh in automation). }
function TMainForm.ImportFromDevice(const DevName, DevId: string; FolderNames, FolderIds: TStrings; Silent: Boolean): Boolean;
var
  Files: TObjectList;  // Files: the device's files (TDeviceFile)
  Keep: TStringList;  // Keep: staging paths of those files
  I, Copied, Skipped, Failed: Integer;  // I: loop counter; Copied, Skipped, Failed: counts
  F: TDeviceFile;  // F: a device file
  Stage, Err, Fails, OldLast: string;  // Stage: staging folder; Err: why a copy failed; Fails: list of failures; OldLast: last source before
  TotalKb: Int64;  // TotalKb: size of all files in KB
  ListOk: Boolean;  // ListOk: every folder could be listed
begin
  Result := False;
  Stage := StagingDir(DevName);  // CacheDir\device\<name>\
  Files := TObjectList.Create(True);  // owns the files until they move to FDevFiles
  Copied := 0; Skipped := 0; Failed := 0; Fails := '';  // nothing yet
  ListOk := True;
  try
    ShowProgress(0, 'Importing from ' + DevName, False);  // progress window
    try
      FProgLbl.Caption := 'Listing the files on the device...';  // progress text
      Application.ProcessMessages;  // let the window update
      for I := 0 to FolderIds.Count - 1 do  // every chosen folder
        if not ListDeviceFiles(FolderIds[I], FolderNames[I], Files, @DevCountProgress) then
        begin
          if FCancel then Break;  // canceled
          ListOk := False;  // this folder could not be read
          Fails := Fails + FolderNames[I] + ': cannot be read (unplugged or locked?)' + LineEnding;
        end;
      if not FCancel then
      begin
        TotalKb := 0;
        for I := 0 to Files.Count - 1 do Inc(TotalKb, Max(0, TDeviceFile(Files[I]).Size) div 1024 + 1);  // size in KB
        FProgBar.Style := pbstNormal;  // the length is known now
        FProgBar.Max := Max(1, TotalKb);
        FProgBar.Position := 0;
        FDevDoneKb := 0;
        for I := 0 to Files.Count - 1 do  // every file
        begin
          if FCancel then Break;  // canceled
          F := TDeviceFile(Files[I]);
          FProgLbl.Caption := Format('Copying %d of %d: %s', [I + 1, Files.Count, ExtractFileName(F.Rel)]);  // progress text
          Application.ProcessMessages;  // let the window update
          if StagedCopyMatches(F, Stage + F.Rel) then Inc(Skipped)  // staged before
          else if CopyDeviceFile(F, Stage + F.Rel, @DevBytesProgress, Err) then Inc(Copied)  // copied and checked
          else if not FCancel then
          begin
            Inc(Failed);
            Fails := Fails + F.Rel + ': ' + Err + LineEnding;  // remember why
          end;
          Inc(FDevDoneKb, Max(0, F.Size) div 1024 + 1);  // progress
          FProgBar.Position := Min(FProgBar.Max, FDevDoneKb);
        end;
      end;
    finally
      HideProgress;  // close the progress window
    end;
    if FCancel then  // the user stopped it
    begin
      SetStatus(Format('Import from %s canceled after %d file(s).', [DevName, Copied]));
      Exit;
    end;
    if (Files.Count = 0) and not ListOk then  // nothing could be read
    begin
      if not Silent then
        MessageDlg(AppTitle, 'Nothing could be read from ' + DevName + ':' + LineEnding + LineEnding + Fails +
          LineEnding + NoDeviceText, mtWarning, [mbOK], 0);
      Exit;
    end;
    if (FDevStage <> '') and not SameText(FDevStage, Stage) then LeaveDevice;  // another device was the source
    if ListOk then  // the staging folder mirrors the chosen folders: drop copies no longer on the device
    begin
      Keep := TStringList.Create;
      try
        Keep.Sorted := True;
        Keep.CaseSensitive := False;
        for I := 0 to Files.Count - 1 do Keep.Add(Stage + TDeviceFile(Files[I]).Rel);
        PruneStaging(Stage, Keep);
      finally
        Keep.Free;
      end;
    end;
    FDevFiles.Clear;  // the files of this import
    for I := 0 to Files.Count - 1 do FDevFiles.AddObject(TDeviceFile(Files[I]).Rel, Files[I]);
    Files.OwnsObjects := False;  // FDevFiles owns them now
    FDevName := DevName;  // the device is the source
    FDevId := DevId;
    FDevStage := Stage;
    if FDevFolderNames <> FolderNames then FDevFolderNames.Assign(FolderNames);  // for Refresh
    if FDevFolderIds <> FolderIds then FDevFolderIds.Assign(FolderIds);
    ForceDirectoriesUTF8(Stage);  // even when empty
    OldLast := FS.LastSource;  // the staging folder is no "last source" (it is not a folder the user chose)
    LoadSource(Stage);  // show the staged files like a card
    FS.LastSource := OldLast;
    SetStatus(Format('Imported from %s: %d file(s) copied, %d already there%s.',
      [DevName, Copied, Skipped, BoolToStr(Failed > 0, Format(', %d FAILED', [Failed]), '')]));
    if (Fails <> '') and not Silent then
      MessageDlg(AppTitle, 'These could not be imported from ' + DevName + ':' + LineEnding + LineEnding + Fails,
        mtWarning, [mbOK], 0);
    Result := True;
  finally
    Files.Free;
  end;
end;

{ Imports the DCIM folders of the device DevName (DevId); False when it has none or nothing was imported. }
function TMainForm.ImportDeviceDcim(const DevName, DevId: string; Silent: Boolean): Boolean;
var
  Names, Ids, DNames, DIds: TStringList;  // the device's folders; its DCIM folders
  I: Integer;  // I: loop counter
begin
  Result := False;
  Names := TStringList.Create; Ids := TStringList.Create;
  DNames := TStringList.Create; DIds := TStringList.Create;
  try
    ListDeviceFolders(DevId, Names, Ids);  // "Storage\Folder"
    for I := 0 to Names.Count - 1 do
      if SameText(Copy(Names[I], Length(Names[I]) - 4, 5), '\DCIM') then  // "Storage\DCIM"
      begin
        DNames.Add(Names[I]);
        DIds.Add(Ids[I]);
      end;
    if DIds.Count > 0 then Result := ImportFromDevice(DevName, DevId, DNames, DIds, Silent);
  finally
    Names.Free; Ids.Free; DNames.Free; DIds.Free;
  end;
end;

{ Imports the DCIM folders of the first connected device that has one; False when there is none. }
function TMainForm.ImportFirstDevice(Silent: Boolean): Boolean;
var
  Devs, DevIds: TStringList;  // Devs, DevIds: the connected devices
  D: Integer;  // D: loop counter
begin
  Result := False;
  Devs := TStringList.Create; DevIds := TStringList.Create;
  try
    ListDevices(Devs, DevIds);  // connected devices
    for D := 0 to Devs.Count - 1 do  // the first one with a DCIM folder
      if ImportDeviceDcim(Devs[D], DevIds[D], Silent) then Exit(True);
  finally
    Devs.Free; DevIds.Free;
  end;
end;

{ The device stops being the source (another source, Eject, exit). Unless Preferences > General keeps
  them, the staged copies of downloaded files are removed (the files not downloaded stay staged, so the
  next import does not copy them again). }
procedure TMainForm.LeaveDevice;
var
  I: Integer;  // I: loop counter
  It: TImageItem;  // It: an item
begin
  if FDevStage = '' then Exit;  // no device
  if not FS.KeepDeviceCopies then
  begin
    for I := 0 to FItems.Count - 1 do  // every staged file that was downloaded
    begin
      It := ItemAt(FItems, I);
      if (It.Status = isDownloaded) and (not It.IsGroup) and
         SameText(Copy(It.FullPath, 1, Length(FDevStage)), FDevStage) then
        DeleteFileUTF8(It.FullPath);  // its copy is in the destination
    end;
    RemoveEmptyFolders(FDevStage);  // folders left empty
  end;
  FDevName := ''; FDevId := ''; FDevStage := '';  // no device any more
  FDevFiles.Clear;
  FDevFolderNames.Clear;
  FDevFolderIds.Clear;
end;

{ The device file a staged item came from, or nil. }
function TMainForm.DeviceFileOf(It: TImageItem): TDeviceFile;
var
  I: Integer;  // I: index in FDevFiles
begin
  Result := nil;
  if (FDevStage = '') or not SameText(Copy(It.FullPath, 1, Length(FDevStage)), FDevStage) then Exit;  // not staged
  I := FDevFiles.IndexOf(Copy(It.FullPath, Length(FDevStage) + 1, MaxInt));  // path below the staging folder
  if I >= 0 then Result := TDeviceFile(FDevFiles.Objects[I]);
end;

{ Asks for the general job code. }
procedure TMainForm.AskJobCode;
var
  Job: string;  // Job: job code
begin
  Job := FS.JobCode;  // current job code
  if ExecuteJobCode(FS, Job, FCamera) then  // ask the user
    FS.JobCode := Job;  // store the new code
end;

{ ====================================================================== }
{ events                                                                  }
{ ====================================================================== }

{ Start-up work: profile, job code, source folder and automation. }
procedure TMainForm.StartupTimer(Sender: TObject);
var
  L: TStringList;  // L: profile names
  Choice, Job, Src: string;  // Choice: chosen profile; Job: job code; Src: source folder
  Picked, Asked: Boolean;  // Picked: source folder chosen; Asked: job code dialog shown
begin
  if SplashWaiting then  // splash still within its minimum time and not clicked
  begin
    FTimer.Interval := 50;  // look again shortly; the program keeps running meanwhile (no waiting loop)
    Exit;  // the start-up work (and its dialogs) comes after the splash
  end;
  FTimer.Enabled := False;  // run only once
  CloseSplash;                 // the main window is up
  if FPluginErr <> '' then  // a plug-in library could not be loaded
  begin
    SaveSettingsNow;  // it was switched off: keep that
    MessageDlg(AppTitle, 'These plug-ins could not be loaded and were switched off:'#13#10#13#10 + FPluginErr,
      mtWarning, [mbOK], 0);  // tell the user
    FPluginErr := '';  // reported
  end;
  FixThumbWidth;  // correct the window width
  ApplyTitleBar(Self, ThemeDark);  // the window exists now: dark title bar with the dark theme
  {$IFDEF UNIX}
  CenterOnWorkArea;  // GTK: center again now that the window has its final size
  {$ENDIF}
  if FS.SingleInstance then RegisterMainWindow(Handle);   // lets a second copy find this window
  if FS.PromptProfile then  // ask for a profile
  begin
    L := TStringList.Create;  // create the list
    try
      ListProfiles(L);  // find the profiles
      // "Default" always exists: it keeps the settings as they are (no profile file needed)
      if L.IndexOf('Default') < 0 then L.Insert(0, 'Default');  // there is always a Default profile
      if ChooseFromList('User Profiles', 'Select a profile to load:', L, Choice) and  // ask the user
         FileExistsUTF8(ProfilesDir + Choice + '.ini') then  // profile file exists
      begin
        FS.LoadProfileKeepView(ProfilesDir + Choice + '.ini');  // load the profile (theme and view stay)
        FS.PromptProfile := True;       // a profile must not switch the prompt off
        FS.ProfileName := Choice;  // the profile in use
        ReloadPlugins;  // the profile may switch other plug-ins on
        ApplyState;  // apply the settings
        SaveSettingsNow;  // remember the profile in use
      end
      else
        UseDefaultProfile;  // nothing chosen (or "Default" not saved yet): the Default profile
    finally
      L.Free;  // free the list
    end;
  end
  else if (FS.ProfileName = '') or not FileExistsUTF8(ProfilesDir + FS.ProfileName + '.ini') then
    UseDefaultProfile;  // no profile in use (or its file is gone): the Default profile
  UpdateCaption;  // the profile in use in the title bar
  Src := '';  // no source yet
  if FS.LoadLastAtStartup then Src := FS.LastSource;  // use the last source when asked
  Picked := False;  // nothing chosen yet
  Asked := False;  // nothing asked yet
  if FS.PromptJobCode then  // ask for the job code
  begin
    Job := FS.JobCode;  // current job code
    // the start-up job code window also asks for the source folder
    if ExecuteJobCodeSource(FS, Job, Src, FCamera) then  // the dialog also asks for the source folder
    begin
      FS.JobCode := Job;  // store the job code
      Asked := True;  // the dialog was shown
      Picked := Trim(Src) <> '';  // a folder was entered
    end;
  end;
  // nothing is scanned at start-up unless the user asked for it
  if Picked and DirectoryExistsUTF8(Src) then  // load the chosen folder
    LoadSource(Src)  // load it
  else if (not Asked) and FS.LoadLastAtStartup and (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then  // load the last source
    LoadSource(FS.LastSource)  // load it
  else if FS.AutoAtStartup then  // automation at start-up
    AutoDetectSource  // look for a card reader
  else if FS.LastSource <> '' then  // a last source is known
    SetStatus('Last source: ' + FS.LastSource + '   (F5 loads it, or use File > Open Source Folder)')  // tell the user how to load it
  else
    SetStatus('Choose File > Open Source Folder (Ctrl+O) to load images.');  // tell the user how to open a folder
  FS.FirstRunDone := True;  // first run is done
  if FS.AutoAtStartup then RunAutoSequence;  // run the automatic sequence
end;

{ Saves the settings when the window closes. }
procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if CloseAction = caNone then Exit;     // closing was canceled
  LeaveDevice;  // downloaded staged device files are removed
  SaveSettingsNow;  // save the settings
  PruneThumbCache;  // keep the thumbnail cache below its size limit
end;

{ Lets the user choose a source folder and loads it. On Windows the dialog also tells a phone or camera
  apart (uDevices.PickSourceFolder): choosing the device imports its DCIM folder, choosing a folder inside
  it imports that folder (the standard folder dialog would return a wrong folder for a device). }
procedure TMainForm.OpenSourceClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser (Linux)
  Start, Path, DevName, DevId, FolderName, FolderId: string;  // the first folder; what was chosen
  Names, Ids: TStringList;  // Names, Ids: the chosen device folder
begin
  Start := '';  // the first folder shown
  if (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then Start := FS.LastSource;  // last source exists
  if DevicesSupported then  // Windows
  begin
    case PickSourceFolder(Handle, 'Open Source Folder', Start, Path, DevName, DevId, FolderName, FolderId) of
      prFolder:  // a disk folder
        begin
          LoadSource(Path);  // load it
          SaveSettingsNow;  // save the settings
        end;
      prDevice:  // a phone or camera
        if FolderId = '' then  // the device or a storage: its DCIM folder
        begin
          if not ImportDeviceDcim(DevName, DevId, False) and not FCancel then
            MessageDlg(AppTitle, DevName + ' shows no DCIM folder. Choose a folder inside it, or use ' +
              'File > Import from Device...', mtInformation, [mbOK], 0);  // explain
        end
        else
        begin
          Names := TStringList.Create;
          Ids := TStringList.Create;
          try
            Names.Add(FolderName);  // "Storage\Folder"
            Ids.Add(FolderId);
            ImportFromDevice(DevName, DevId, Names, Ids, False);  // just that folder
          finally
            Names.Free;
            Ids.Free;
          end;
        end;
      prOther:  // neither
        MessageDlg(AppTitle, 'This place is not a folder on a disk or a phone or camera. Choose a folder.',
          mtInformation, [mbOK], 0);  // explain
    end;
    Exit;
  end;
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  OkFirst(D);  // Open/Save on the left on Linux too (uMsgDlg)
  try
    D.Title := 'Open Source Folder';  // window title
    D.InitialDir := Start;  // start in the last source
    if D.Execute then  // user chose a folder
    begin
      LoadSource(D.FileName);  // load it
      SaveSettingsNow;  // save the settings
    end;
  finally
    D.Free;  // free the chooser
  end;
end;

{ Fills L with the names of the saved profiles. }
procedure TMainForm.ListProfiles(L: TStrings);
var
  SR: TSearchRec;  // SR: directory entry
begin
  L.Clear;  // empty the list
  if FindFirstUTF8(ProfilesDir + '*.ini', faAnyFile, SR) = 0 then  // search for profile files
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then  // ignore folders
        L.Add(ChangeFileExt(SR.Name, ''));  // add the name without extension
    until FindNextUTF8(SR) <> 0;  // next entry
  finally
    FindCloseUTF8(SR);  // close the search
  end;
end;

{ File > User Profiles...: the window with the saved profiles and Load, Save, Save As..., New... and Delete. }
procedure TMainForm.ProfilesClick(Sender: TObject);
begin
  ExecuteProfiles(@ProfileAction, @ListProfiles, @ProfileInUse);  // the window calls back for each action
end;

{ The profile in use. }
function TMainForm.ProfileInUse: string;
begin
  Result := FS.ProfileName;  // loaded, saved or created last
end;

{ Loads the saved profile Nm and makes it the profile in use (the start-up prompt setting stays). }
procedure TMainForm.LoadProfileNamed(const Nm: string);
var
  PromptWas: Boolean;  // PromptWas: start-up prompt setting before loading
begin
  PromptWas := FS.PromptProfile;  // remember the prompt setting
  FS.LoadProfileKeepView(ProfilesDir + Nm + '.ini');  // load the profile (theme and view stay)
  FS.PromptProfile := PromptWas;      // a profile must not change the start-up prompt setting
  FS.ProfileName := Nm;  // the profile in use
  ReloadPlugins;  // the profile may switch other plug-ins on
  SaveSettingsNow;  // save the settings
  ApplyState;  // apply the settings
  Reevaluate;  // work out the names again
  UpdateCaption;  // the new profile in the title bar
end;

{ Does what the User Profiles window asks; False when it was not done. Load and New first ask about
  unsaved changes of the profile in use (AskSaveProfile); the window has already asked for names and
  confirmations. }
function TMainForm.ProfileAction(Act: TProfileAction; const Nm: string): Boolean;
begin
  Result := False;  // not done yet
  case Act of
    paLoad:
      begin
        if not FileExistsUTF8(ProfilesDir + Nm + '.ini') then Exit;  // gone meanwhile
        if not AskSaveProfile then Exit;  // canceled
        LoadProfileNamed(Nm);  // load it
        Result := True;
      end;
    paSave:
      Result := WriteProfile(Nm);  // the settings into the profile in use
    paSaveAs:
      Result := WriteProfile(Nm);  // the settings under the new name, now the profile in use
    paNew:
      begin
        if not AskSaveProfile then Exit;  // canceled
        FS.DefaultsKeepSession;  // the program's default settings (last source, job code, view stay)
        Result := WriteProfile(Nm);  // saved as the new profile, now in use
        ReloadPlugins;  // plug-ins as the defaults have them
        SaveSettingsNow;  // the settings file follows
        ApplyState;  // apply the settings
        Reevaluate;  // work out the names again
      end;
    paDelete:
      begin
        if Nm = FS.ProfileName then Exit;  // never the profile in use (the window does not offer it)
        Result := DeleteFileUTF8(ProfilesDir + Nm + '.ini');  // delete the profile file
        if not Result then
          MessageDlg(AppTitle, 'Could not delete the profile "' + Nm + '".', mtError, [mbOK], 0);  // tell the user
      end;
  end;
end;

{ Saves the settings as the profile Nm without questions and makes it the profile in use. A new file is
  written first, so an old profile is replaced completely (no left-over keys) and is not lost when writing
  fails. False (after telling the user) when it could not be saved. }
function TMainForm.WriteProfile(const Nm: string): Boolean;
var
  Fn: string;  // Fn: the profile file
begin
  Result := False;  // not saved yet
  Fn := ProfilesDir + Nm + '.ini';  // the profile file
  try
    FS.ProfileName := Nm;  // the profile in use from now on (also stored inside the profile)
    if FileExistsUTF8(Fn + '.tmp') then DeleteFileUTF8(Fn + '.tmp');  // a left-over from a failed save
    FS.SaveToFile(Fn + '.tmp');  // write the new profile
    if FileExistsUTF8(Fn) then DeleteFileUTF8(Fn);  // remove the old one
    if not RenameFileUTF8(Fn + '.tmp', Fn) then raise Exception.Create('cannot rename ' + Fn + '.tmp');  // put the new one in place
    SaveSettingsNow;  // remember the profile in use
    UpdateCaption;  // the profile in use in the title bar
    SetStatus('Profile "' + Nm + '" saved.');  // tell the user
    Result := True;  // saved
  except
    on E: Exception do
      MessageDlg(AppTitle, 'Could not save the profile:'#13#10 + E.Message, mtError, [mbOK], 0);  // tell the user
  end;
end;

{ True when the settings differ from the saved file of the profile in use. Session values (last source,
  job code, next sequence number, view options ...) do not count (uSettings.SessionKeys). }
function TMainForm.ProfileChanged: Boolean;
var
  Fn: string;  // Fn: the profile file
  P: TAppSettings;  // P: the settings as the profile file has them
begin
  Result := False;  // no profile in use: nothing to compare
  if FS.ProfileName = '' then Exit;
  Fn := ProfilesDir + FS.ProfileName + '.ini';  // its file
  if not FileExistsUTF8(Fn) then Exit;  // deleted meanwhile
  P := FS.WithProfile(Fn);  // the settings with the saved profile
  try
    Result := P.ProfileText <> FS.ProfileText;  // anything a profile keeps is different
  finally
    P.Free;  // free the copy
  end;
end;

{ When the settings were changed since the profile in use was saved, asks whether to save them to it.
  Yes saves the profile; No puts the saved profile back (the changes are dropped); Cancel returns False. }
function TMainForm.AskSaveProfile: Boolean;
var
  P: TAppSettings;  // P: the settings as the profile file has them
begin
  Result := True;  // go on
  if not ProfileChanged then Exit;  // nothing unsaved
  case MessageDlg(AppTitle, 'The settings were changed and are not saved in the profile "' + FS.ProfileName + '".' +
         #13#10#13#10'Save the changes to the profile?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Result := WriteProfile(FS.ProfileName);  // save them (stay when saving failed)
    mrNo:
      begin
        P := FS.WithProfile(ProfilesDir + FS.ProfileName + '.ini');  // the saved profile, session values kept
        try
          FS.AssignFrom(P);  // drop the changes
        finally
          P.Free;  // free the copy
        end;
        SaveSettingsNow;  // the settings file matches the profile again
      end;
  else
    Result := False;  // canceled
  end;
end;

{ Makes "Default" the profile in use: loads Default.ini, or saves the current settings as Default.ini when
  there is none yet. Used at start-up when no profile was chosen. }
procedure TMainForm.UseDefaultProfile;
var
  Fn: string;  // Fn: the Default profile file
  PromptWas: Boolean;  // PromptWas: the start-up prompt setting
begin
  Fn := ProfilesDir + 'Default.ini';  // its file
  if FileExistsUTF8(Fn) then  // saved before: load it
  begin
    PromptWas := FS.PromptProfile;  // a profile must not change the start-up prompt setting
    FS.LoadProfileKeepView(Fn);  // load the profile (theme and view stay)
    FS.PromptProfile := PromptWas;  // keep the prompt setting
    FS.ProfileName := 'Default';  // the profile in use
    ReloadPlugins;  // the profile may switch other plug-ins on
    ApplyState;  // apply the settings
    SaveSettingsNow;  // remember the profile in use
  end
  else
    WriteProfile('Default');  // the settings as they are become the Default profile
end;

{ Before the window closes: asks about profile changes that were not saved (not when the automatic
  sequence closes the program). }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FAutoClosing then Exit;  // hands-free exit: no questions
  CanClose := AskSaveProfile;  // Cancel keeps the program open
end;

{ Shows the status window with counts and settings. }
procedure TMainForm.StatusClick(Sender: TObject);
var
  I, NNew, NDown, NClash, NDup: Integer;  // I: loop counter; NNew, NDown, NClash, NDup: counts of each status
  S: string;  // S: message text
begin
  NNew := 0; NDown := 0; NClash := 0; NDup := 0;  // clear the counters
  for I := 0 to FItems.Count - 1 do  // every item
    case ItemAt(FItems, I).Status of  // by status
      isNew: Inc(NNew);  // new
      isDownloaded: Inc(NDown);  // downloaded
      isNameClash: Inc(NClash);  // name clash
      isDuplicate: Inc(NDup);  // duplicate
    end;
  if FSourcePath = '' then S := 'Source: (none)' else S := 'Source: ' + FSourcePath;  // source text
  if FDevName <> '' then S := 'Source: device ' + FDevName + ' (staging folder ' + FSourcePath + ')';  // a phone or camera
  S := AppTitle + ' ' + AppVersionString + #13#10#13#10 + S + #13#10 + Format('Files found: %d', [FItems.Count]) +  // build the message (program, source, counts)
    #13#10 + Format('  New: %d   Already downloaded: %d   Name clashes: %d   Duplicates: %d',  // counts
      [NNew, NDown, NClash, NDup]) +
    #13#10#13#10 + 'Job code: ' + FS.JobCode +  // job code
    #13#10 + 'Next sequence number: ' + IntToStr(FS.SeqNext) +  // next sequence number
    #13#10 + 'Example: ' + ExampleDest(FS, FS.DownloadDir, FS.FileNameMask, FS.JobCode) +  // example name
    #13#10#13#10 + 'SQLite library (Lightroom catalogs): ' + LrCatLibraryText +  // library for .lrprev files
    #13#10 + Format('Device staging folders: %.1f MB in %s', [StagingBytes / 1048576, CacheDir + 'device']);  // imported device files
  ShowStatus(S, SettingsFileName);  // show the dialog (the settings file is a clickable link)
end;

{ Opens the Preferences dialog (on the Plug-ins tab for File > Plug-ins) and rescans when the destination changed. }
procedure TMainForm.PrefsClick(Sender: TObject);
var
  OldDir, OldMask: string;  // OldDir, OldMask: destination before the dialog
  OldLrData: Boolean;  // OldLrData: Lightroom preview folders scanned before the dialog
begin
  OldDir := FS.DownloadDir;  // remember the folder
  OldMask := FS.FileNameMask;  // remember the file name pattern
  OldLrData := FS.ScanLrData;  // remember the Lightroom option
  if ExecutePreferences(FS, FCamera, Sender = miPlugins) then  // show the dialog
  begin
    SaveSettingsNow;  // save the settings
    ApplyState;  // apply the settings
    // a new destination folder (or file name pattern) means different files already exist there
    Screen.Cursor := crHourGlass;  // show the wait cursor
    try
      Reevaluate;  // work out the names again
    finally
      Screen.Cursor := crDefault;  // restore the cursor
    end;
    if (OldDir <> FS.DownloadDir) or (OldMask <> FS.FileNameMask) then  // destination changed
      SetStatus('Destination changed - rescanned for files already downloaded.');  // tell the user
    if (OldLrData <> FS.ScanLrData) and (FSourcePath <> '') then  // Lightroom folders now (or no longer) scanned
      LoadSource(FSourcePath);  // scan the source again
  end;
end;

{ Opens the File Types dialog and refreshes the grid. }
procedure TMainForm.FileTypesClick(Sender: TObject);
begin
  if ExecuteFileTypes(FS) then  // show the dialog
  begin
    SaveSettingsNow;  // save the settings
    ApplyFilter;  // refresh the grid
  end;
end;

{ Exports the settings to a file chosen by the user. }
procedure TMainForm.ExportClick(Sender: TObject);
var
  D: TSaveDialog;  // D: save dialog
begin
  D := TSaveDialog.Create(Self);  // create the dialog
  OkFirst(D);  // Open/Save on the left on Linux too (uMsgDlg)
  try
    D.Title := 'Export Settings';  // window title
    D.FileName := 'PhotoDownloaderSettings.ini';  // suggested name
    D.Filter := 'Settings (*.ini)|*.ini|All files|*.*';  // file types
    D.Options := D.Options + [ofOverwritePrompt];  // ask before overwriting
    if D.Execute then  // user chose a file
      try
        FS.SaveToFile(D.FileName);  // write the settings
      except
        on E: Exception do
          MessageDlg(AppTitle, 'Could not export settings:'#13#10 + E.Message, mtError, [mbOK], 0);  // tell the user
      end;
  finally
    D.Free;  // free the dialog
  end;
end;

{ Runs the automatic sequence from the menu. }
procedure TMainForm.AutoClick(Sender: TObject);
begin
  RunAutoSequence;  // run it
end;

{ Reloads the source folder (or looks for a card reader). }
procedure TMainForm.RefreshClick(Sender: TObject);
var
  Names, Ids: TStringList;  // Names, Ids: the device folders imported last
begin
  if FDevId <> '' then  // a phone or camera: import again (new pictures), then show
  begin
    Names := TStringList.Create;
    Ids := TStringList.Create;
    try
      Names.Assign(FDevFolderNames);  // copies: the import replaces the fields
      Ids.Assign(FDevFolderIds);
      ImportFromDevice(FDevName, FDevId, Names, Ids, False);
    finally
      Names.Free;
      Ids.Free;
    end;
  end
  else if FSourcePath <> '' then  // a source is loaded
    LoadSource(FSourcePath)  // reload it
  else if (FS.LastSource <> '') and DirectoryExistsUTF8(FS.LastSource) then  // a last source is known
    LoadSource(FS.LastSource)  // load it
  else
    AutoDetectSource;  // look for a card reader
end;

{ Ejects the source media. }
procedure TMainForm.EjectClick(Sender: TObject);
begin
  DoEject(False);  // eject with messages
end;

{ Closes the program. }
procedure TMainForm.ExitClick(Sender: TObject);
begin
  Close;  // close the window
end;

{ Changes the selection: 0 all, 1 downloaded, 2 read-only, 3 JPEG, 4 none, 5 invert. }
procedure TMainForm.SelectWhere(Mode: Integer);
var
  I: Integer;  // I: loop counter
  It: TImageItem;  // It: current item
begin
  for I := 0 to FVisible.Count - 1 do  // every visible item
  begin
    It := TImageItem(FVisible[I]);  // current item
    case Mode of  // by mode
      0: It.Selected := True;  // select all
      1: It.Selected := It.Status = isDownloaded;  // select downloaded files
      2: It.Selected := It.IsReadOnly;  // select read-only files
      3: It.Selected := It.IsJpeg;  // select JPEG files
      4: It.Selected := False;  // select none
      5: It.Selected := not It.Selected;  // invert the selection
    end;
  end;
  FView.SelectionChanged;  // tell the grid
end;

{ Selects all images. }
procedure TMainForm.SelAllClick(Sender: TObject);  begin SelectWhere(0); end;
{ Selects the downloaded images. }
procedure TMainForm.SelDownClick(Sender: TObject); begin SelectWhere(1); end;
{ Selects the read-only images. }
procedure TMainForm.SelROClick(Sender: TObject);   begin SelectWhere(2); end;
{ Selects the JPEG images. }
procedure TMainForm.SelJpgClick(Sender: TObject);  begin SelectWhere(3); end;
{ Clears the selection. }
procedure TMainForm.SelNoneClick(Sender: TObject); begin SelectWhere(4); end;
{ Inverts the selection. }
procedure TMainForm.InvertClick(Sender: TObject);  begin SelectWhere(5); end;

{ Opens the IPTC/XMP dialog. }
procedure TMainForm.IptcClick(Sender: TObject);
begin
  if ExecuteIptc(FS.Iptc) then SaveSettingsNow;  // show the dialog and save the settings
end;

{ Opens the job code dialog. }
procedure TMainForm.JobClick(Sender: TObject);
begin
  ChangeJobCode;  // change the job code
end;

{ Tells the user that GPS tagging is not available. }
procedure TMainForm.GpsClick(Sender: TObject);
begin
  MessageDlg('GPS settings', 'GPS track log geotagging is not available in this version.',  // show the message
    mtInformation, [mbOK], 0);
end;

{ Shows or hides downloaded files. }
procedure TMainForm.ShowDownClick(Sender: TObject);
begin
  FS.ShowDownloaded := not FS.ShowDownloaded;  // toggle the setting
  miShowDown.Checked := FS.ShowDownloaded;  // update the menu item
  ApplyFilter;  // refresh the grid
end;

{ Shows or hides duplicate files. }
procedure TMainForm.ShowDupClick(Sender: TObject);
begin
  FS.ShowDuplicates := not FS.ShowDuplicates;  // toggle the setting
  miShowDup.Checked := FS.ShowDuplicates;  // update the menu item
  ApplyFilter;  // refresh the grid
end;

{ Switches to list view. }
procedure TMainForm.ListViewClick(Sender: TObject);  begin SetViewMode(0); end;
{ Switches to small thumbnails. }
procedure TMainForm.SmallViewClick(Sender: TObject); begin SetThumbPreset(64); end;
{ Switches to large thumbnails. }
procedure TMainForm.LargeViewClick(Sender: TObject); begin SetThumbPreset(320); end;
{ Switches to thumbnails that fill the window width (at most 160 pixels). }
procedure TMainForm.FitViewClick(Sender: TObject);
begin
  FS.FitWindow := True;  // Fit to Window
  SetViewMode(1);  // cards
end;
{ Switches to medium thumbnails. }
procedure TMainForm.MediumViewClick(Sender: TObject); begin SetThumbPreset(160); end;

{ Shows or hides the date list. }
procedure TMainForm.DateSelClick(Sender: TObject);
begin
  FS.ShowDateSelector := not FS.ShowDateSelector;  // toggle the setting
  miDateSel.Checked := FS.ShowDateSelector;  // update the menu item
  pnlLeft.Visible := FS.ShowDateSelector;  // show or hide the list
  splLeft.Visible := FS.ShowDateSelector;  // show or hide the splitter
end;

{ Shows the Getting Started text. }
procedure TMainForm.HelpContentsClick(Sender: TObject);
begin
  MessageDlg('Getting Started',  // show the message
    '1. Insert a memory card, or choose File > Open Source Directory.' + #13#10 +
    '2. Enter a job code when prompted (Edit > Job code... changes it later).' + #13#10 +
    '3. Click Download. Files are copied to the folder set in File > Preferences.' + #13#10#13#10 +
    'Gray images are already downloaded.' + #13#10 + 'Red images have a name clash: another file would be written to the same name.' + #13#10 +
    'Press F1 in the Preferences dialog for the list of file name tokens.',
    mtInformation, [mbOK], 0);
end;

{ Opens the web site. }
procedure TMainForm.WebsiteClick(Sender: TObject);
begin
  if not OpenURL(WebsiteURL) then  // open the address
    MessageDlg('Visit website', 'The web browser could not be started. The address is:'#13#10 +  // tell the user if the browser failed
      WebsiteURL, mtWarning, [mbOK], 0);
end;

{ Opens the page for updates. }
procedure TMainForm.UpdatesClick(Sender: TObject);
begin
  // new versions are published as GitHub releases
  if not OpenURL(UpdatesURL) then  // open the address
    MessageDlg('Check for updates', 'The web browser could not be started. The address is:'#13#10 +  // tell the user if the browser failed
      UpdatesURL, mtWarning, [mbOK], 0);
end;

{ Opens the PayPal donation page. }
procedure TMainForm.DonatePayPalClick(Sender: TObject);
begin
  // donations are optional; the program stays free
  if not OpenURL(DonatePayPalURL) then  // open the address
    MessageDlg('Donate', 'The web browser could not be started. The address is:'#13#10 +  // tell the user if the browser failed
      DonatePayPalURL, mtWarning, [mbOK], 0);
end;

{ Opens the Venmo donation page. }
procedure TMainForm.DonateVenmoClick(Sender: TObject);
begin
  if not OpenURL(DonateVenmoURL) then  // open the address
    MessageDlg('Donate', 'The web browser could not be started. The address is:'#13#10 +  // tell the user if the browser failed
      DonateVenmoURL, mtWarning, [mbOK], 0);
end;

{ Shows the license dialog. }
procedure TMainForm.RegisterClick(Sender: TObject);
begin
  ShowRegister;  // show it
end;

{ Switches logging on or off. }
procedure TMainForm.LoggingClick(Sender: TObject);
begin
  FS.LoggingOn := not FS.LoggingOn;  // toggle the setting
  LogEnabled := FS.LoggingOn;  // apply it
  miLogging.Checked := FS.LoggingOn;  // update the menu item
  SaveSettingsNow;  // save the settings
end;

{ Saves the log file where the user chooses. }
procedure TMainForm.SaveLogClick(Sender: TObject);
var
  D: TSaveDialog;  // D: save dialog
  Src: TStringList;  // Src: lines of the log
  Outp: TStringList;  // Outp: lines of the saved file
  FN: string;  // FN: log file name
begin
  FN := ConfigDir + 'thumbnail.log';  // log file in the settings folder
  if not FileExistsUTF8(FN) then  // no log file
  begin
    MessageDlg(AppTitle, 'There is no log file yet.' + #13#10 +  // tell the user
      'Nothing has been logged, or logging is switched off (Help > Logging).',
      mtInformation, [mbOK], 0);
    Exit;  // done
  end;
  D := TSaveDialog.Create(nil);  // create the dialog
  OkFirst(D);  // Open/Save on the left on Linux too (uMsgDlg)
  try
    D.Title := 'Save log file';  // window title
    D.FileName := 'PhotoDownloader-log.txt';  // suggested name
    D.Filter := 'Text files (*.txt)|*.txt|All files|*.*';  // file types
    D.Options := D.Options + [ofOverwritePrompt];  // ask before overwriting
    if not D.Execute then Exit;  // user canceled
    Src := TStringList.Create;  // create the list
    Outp := TStringList.Create;  // create the list
    try
      try
        Src.LoadFromFile(FN);  // read the log
        Outp.Add(AppTitle + ' ' + AppVersionString);  // program and version
        Outp.Add('Saved ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));  // save time
        Outp.Add('');  // blank line
        Outp.AddStrings(Src);  // log lines
        Outp.SaveToFile(D.FileName);  // write the file
        MessageDlg(AppTitle, 'Log saved. Please email this file to the developer:'#13#10 + D.FileName,  // tell the user
          mtInformation, [mbOK], 0);
      except
        on E: Exception do
          MessageDlg(AppTitle, 'Could not save the log:'#13#10 + E.Message, mtError, [mbOK], 0);  // tell the user
      end;
    finally
      Outp.Free;  // free the list
      Src.Free;  // free the list
    end;
  finally
    D.Free;  // free the dialog
  end;
end;

{ Shows the About box. }
procedure TMainForm.AboutClick(Sender: TObject);
begin
  ShowAbout;  // show it
end;

{ Downloads the selected files. }
procedure TMainForm.DownloadClick(Sender: TObject);
begin
  DoDownload(False, dsSelected);  // download the selected files, with questions
end;

{ Downloads all shown files, whatever is selected. }
procedure TMainForm.DownloadAllClick(Sender: TObject);
begin
  DoDownload(False, dsAll);  // download all shown files, with questions
end;

{ Deletes the downloaded source files. }
procedure TMainForm.DeleteClick(Sender: TObject);
begin
  DeleteFiles(False, False);  // delete with questions
end;

{ Closes the window. }
procedure TMainForm.CloseClick(Sender: TObject);
begin
  Close;  // close it
end;

{ Runs the custom command. }
procedure TMainForm.CustomClick(Sender: TObject);
begin
  LaunchCustom;  // run it
end;

end.
