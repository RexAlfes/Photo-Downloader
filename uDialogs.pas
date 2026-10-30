unit uDialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, CheckLst, Spin, Clipbrd, LCLType, LCLIntf, uSettings, uItems, uExif, uDrives, uVersion, uSafeDel, uPlugins, uExtPlugin, uIccEmbed;

function ExecuteJobCode(S: TAppSettings; var Job: string; const CurrentCamera: string): Boolean;
{ As ExecuteJobCode, with an extra 'Source folder' line (used at start-up). Source is the
  folder to load; empty means load nothing. }
function ExecuteJobCodeSource(S: TAppSettings; var Job, Source: string; const CurrentCamera: string): Boolean;
function ExecutePreferences(S: TAppSettings; const CurrentCamera: string; PluginTab: Boolean = False): Boolean;
{ Asks every switched-on plug-in library with prompt fields for its values; False when canceled. }
function AskPluginValues(S: TAppSettings): Boolean;
function ExecuteIptc(L: TStringList): Boolean;
function ExecuteFileTypes(S: TAppSettings): Boolean;
function ChooseFromList(const ATitle, APrompt: string; Items: TStrings; out Choice: string): Boolean;
{ Asks for the name to save a user profile under; Items are the saved profiles (clicking one picks it to
  save over). Name comes in as the suggested name (the profile in use) and goes out as the chosen one. }
function AskProfileName(Items: TStrings; var Name: string): Boolean;
procedure ShowTokenHelp;
procedure ShowAbout;
procedure ShowRegister;
procedure ShowStatus(const AText, SettingsFile: string);
procedure ShowImageProperties(Item: TImageItem);

implementation

const
  TokenHelpText =  // help text shown for the file name tokens
    '{d} - date (yyyymmdd)'#13#10 +
    '{y} - 2-digit year'#13#10 +
    '{Y} - 4-digit year'#13#10 +
    '{m} - month (2 digits)'#13#10 +
    '{b} - month (abbreviated name)'#13#10 +
    '{B} - full month name'#13#10 +
    '{D} - day of month'#13#10 +
    '{a} - weekday (abbreviated)'#13#10 +
    '{A} - full weekday'#13#10 +
    '{W} - week number'#13#10 +
    '{t} - time (hhmmss)'#13#10 +
    '{H} - hour (00-23)'#13#10 +
    '{I} - hour (01-12)'#13#10 +
    '{M} - minutes'#13#10 +
    '{S} - seconds'#13#10 +
    '{q} - name of the folder the image came from'#13#10 +
    '{r} - image number from the original file name'#13#10 +
    '{o} - original file name (without extension)'#13#10 +
    '{f} - original file name prefix (letters before the number)'#13#10 +
    '{O} - owner / artist'#13#10 +
    '{i} - ISO'#13#10 +
    '{c} - camera serial number'#13#10 +
    '{T} or {T1} - camera model'#13#10 +
    '{T8}, {T9} - custom tokens defined on the Mapping tab'#13#10 +
    '{J} - Job code'#13#10 +
    '{E} - file extension in upper case (JPG)'#13#10 +
    '{e} - file extension in lower case (jpg)'#13#10 +
    '{ea} - file extension as it is'#13#10 +
    '{seq#} - download sequence number'#13#10 +
    '{n1} ... {n9} - download sequence number for this session, zero padded to 1-9 digits';

{ ---- small control factories ---- }

{ Creates a label on parent P at position (L, T). }
function MkLabel(P: TWinControl; const Cap: string; L, T: Integer): TLabel;
begin
  Result := TLabel.Create(P);  // create the label
  Result.Parent := P;  // place it on the parent
  Result.Caption := Cap;  // set the text
  Result.SetBounds(L, T, Result.Width, Result.Height);  // position it, keeping its natural size
end;

{ Creates a word-wrapped label of a fixed size. }
function MkWrap(P: TWinControl; const Cap: string; L, T, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(P);  // create the label
  Result.Parent := P;  // place it on the parent
  Result.AutoSize := False;  // keep the size given below
  Result.WordWrap := True;  // wrap long text
  Result.Caption := Cap;  // set the text
  Result.SetBounds(L, T, W, H);  // position and size it
end;

{ Creates a push button; MR is the modal result it closes the dialog with. }
function MkButton(P: TWinControl; const Cap: string; L, T, W: Integer;
  MR: TModalResult = mrNone): TButton;
begin  // create the button
  Result := TButton.Create(P);  // place it on the parent
  Result.Parent := P;  // set the text
  Result.Caption := Cap;  // position and size it
  Result.SetBounds(L, T, W, 25);  // position and size it (25 pixels high)
  Result.ModalResult := MR;  // result returned when the button is clicked
end;

{ Creates a check box with the given caption. }
function MkCheck(P: TWinControl; const Cap: string; L, T: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(P);  // create the check box
  Result.Parent := P;  // place it on the parent
  Result.Caption := Cap;  // set the text
  Result.SetBounds(L, T, 460, 22);  // position and size it
end;

{ Creates a single-line edit box. }
function MkEdit(P: TWinControl; L, T, W: Integer): TEdit;
begin
  Result := TEdit.Create(P);  // create the edit box
  Result.Parent := P;  // place it on the parent
  Result.SetBounds(L, T, W, 23);  // position and size it
end;

{ Creates an editable combo box. }
function MkCombo(P: TWinControl; L, T, W: Integer): TComboBox;
begin
  Result := TComboBox.Create(P);  // create the combo box
  Result.Parent := P;  // place it on the parent
  Result.SetBounds(L, T, W, 23);  // position and size it
  Result.Style := csDropDown;  // user may type any text
end;

{ Creates a radio button with the given caption. }
function MkRadio(P: TWinControl; const Cap: string; L, T: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(P);  // create the radio button
  Result.Parent := P;  // place it on the parent
  Result.Caption := Cap;  // set the text
  Result.SetBounds(L, T, 440, 22);  // position and size it
end;

{ Sets up the common properties of a dialog form. }
procedure InitDialog(F: TForm; const ACaption: string; W, H: Integer);
begin
  F.Caption := ACaption;  // window title
  F.BorderStyle := bsDialog;  // fixed-size dialog border
  F.Position := poMainFormCenter;  // center over the main window
  F.ClientWidth := W;  // inner width
  F.ClientHeight := H;  // inner height
end;

{ Shows the list of file name tokens. }
procedure ShowTokenHelp;
begin
  MessageDlg('Directory and filename tokens', TokenHelpText, mtInformation, [mbOK], 0);  // show the help text
end;

type
  TAboutForm = class(TForm)  // About dialog with the program icon
  private
    FIcon: TIcon;  // FIcon: copy of the program icon, set to the 96-pixel image
    FBox: TPaintBox;  // FBox: draws the icon
    procedure BoxPaint(Sender: TObject);  // draws the icon without scaling
  public
    constructor CreateAbout(AOwner: TComponent);  // builds the dialog
    destructor Destroy; override;  // frees the icon copy
  end;

{ Builds the About dialog: program icon on the left, name, description and license note on the right. }
constructor TAboutForm.CreateAbout(AOwner: TComponent);
var
  Lb: TLabel;  // Lb: description text
  Sz: TSize;  // Sz: wanted icon size
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  InitDialog(Self, 'About ' + AppTitle, 470, 250);  // set the common dialog properties
  FIcon := TIcon.Create;  // create the icon copy
  try
    if not Application.Icon.Empty then  // the application icon is loaded
      FIcon.Assign(Application.Icon)  // copy it (all of its sizes)
    else
      FIcon.LoadFromResourceName(HInstance, 'MAINICON');  // otherwise read it from the program resource
    Sz.cx := 96;  // wanted width
    Sz.cy := 96;  // wanted height
    FIcon.Current := FIcon.GetBestIndexForSize(Sz);  // use the 96-pixel image so nothing is scaled
  except
    FreeAndNil(FIcon);  // no icon available: the dialog is shown without it
  end;
  FBox := TPaintBox.Create(Self);  // create the drawing area
  FBox.Parent := Self;  // place it on the form
  FBox.SetBounds(16, 16, 96, 96);  // position and size it
  FBox.OnPaint := @BoxPaint;  // draw the icon
  Lb := MkWrap(Self, AppTitle + ' ' + AppVersionString + #13#10#13#10 +  // program name and version
    'Downloads images from a card reader or folder. Tokens such as date, ' +  // description of the program
    'camera, job code, original name and file extension build both the ' +  // description of the program
    'folder structure and the file names, so images are renamed and ' +  // description of the program
    'organized in one step.' + #13#10#13#10 +  // description of the program
    'Licensed under the GNU General Public License (see Help > Register).' + #13#10 +  // license note
    WebsiteURL + #13#10 +  // web address
    'Built with Lazarus / Free Pascal.', 128, 16, 326, 180);  // build information (position and size)
  Lb.Font.Style := [];  // normal text
  MkButton(Self, 'OK', 374, 210, 80, mrOK).Default := True;  // OK button, also the default button
end;

{ Frees the icon copy. }
destructor TAboutForm.Destroy;
begin
  FIcon.Free;  // free the icon (may be nil)
  inherited Destroy;  // run the inherited destructor
end;

{ Draws the icon at its own size, so it stays sharp. }
procedure TAboutForm.BoxPaint(Sender: TObject);
begin
  if FIcon <> nil then  // an icon is available
    FBox.Canvas.Draw(0, 0, FIcon);  // draw it unscaled
end;

{ Shows the About box. }
procedure ShowAbout;
var
  F: TAboutForm;  // F: the dialog
begin
  F := TAboutForm.CreateAbout(Application);  // create the dialog
  try
    F.ShowModal;  // show it and wait
  finally
    F.Free;  // free the dialog
  end;
end;

const
  LicenseText =  // license text shown in the Register dialog
    AppTitle + #13#10 +
    'Copyright (C) 2026 The Photo Downloader authors'#13#10#13#10 +
    'This program is free software: you can redistribute it and/or modify ' +
    'it under the terms of the GNU General Public License as published by ' +
    'the Free Software Foundation, either version 3 of the License, or ' +
    '(at your option) any later version.'#13#10#13#10 +
    'This program is distributed in the hope that it will be useful, ' +
    'but WITHOUT ANY WARRANTY; without even the implied warranty of ' +
    'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the ' +
    'GNU General Public License for more details.'#13#10#13#10 +
    'You should have received a copy of the GNU General Public License ' +
    'along with this program. If not, see <https://www.gnu.org/licenses/>.';

type
  { TPropsForm - read-only list of everything known about one image }  // dialog that lists the properties of one image
  TPropsForm = class(TForm)
  private
    LV: TListView;  // list of properties
    FText: string;  // same text as plain text for the clipboard
    procedure AddRow(const K, V: string);  // adds one row to the list and to the text
    procedure CopyClick(Sender: TObject);  // copies the text to the clipboard
  public
    constructor CreateProps(AOwner: TComponent; Item: TImageItem);  // builds the dialog for one image
  end;

  TRegisterForm = class(TForm)  // dialog that shows the license
  private
    procedure LicenseClick(Sender: TObject);  // opens the full license in the browser
  public
    constructor CreateReg(AOwner: TComponent);  // builds the license dialog
  end;

  TStatusForm = class(TForm)  // status dialog with a clickable settings file location
  private
    FFolder: string;  // FFolder: folder that contains the settings file
    procedure LinkClick(Sender: TObject);  // opens the settings folder
  public
    constructor CreateStatus(AOwner: TComponent; const AText, SettingsFile: string);  // builds the dialog
  end;

{ Builds the Register dialog with the license text. }
constructor TRegisterForm.CreateReg(AOwner: TComponent);
var
  M: TMemo;  // M: license text box
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  InitDialog(Self, 'Register', 520, 400);  // set the common dialog properties
  MkLabel(Self, AppTitle + ' ' + AppVersionString, 12, 12);  // program name and version
  MkWrap(Self, 'No registration or license key is needed. This software is free ' +  // explanation text
    'software released under the GNU General Public License:', 12, 36, 496, 34);  // explanation text (position and size)
  M := TMemo.Create(Self);  // create the memo
  M.Parent := Self;  // place it on the form
  M.SetBounds(12, 76, 496, 270);  // position and size it
  M.ReadOnly := True;  // user cannot edit the license
  M.ScrollBars := ssVertical;  // vertical scroll bar
  M.WordWrap := True;  // wrap long lines
  M.Text := LicenseText;  // show the license
  MkButton(Self, 'View full license online', 12, 360, 170).OnClick := @LicenseClick;  // button that opens the license on the web
  MkButton(Self, 'OK', 428, 360, 80, mrOK).Default := True;  // OK button, also the default button
end;

{ Opens the full license text in the web browser. }
procedure TRegisterForm.LicenseClick(Sender: TObject);
begin
  OpenURL('https://www.gnu.org/licenses/gpl-3.0.html');
end;

{ Adds one property row to the list and to the clipboard text. }
procedure TPropsForm.AddRow(const K, V: string);
var
  LI: TListItem;  // LI: new list row
begin
  LI := LV.Items.Add;  // add a row
  LI.Caption := K;  // property name
  LI.SubItems.Add(V);  // property value
  FText := FText + K + ': ' + V + LineEnding;  // append a line to the plain text
end;

{ Copies the properties to the clipboard. }
procedure TPropsForm.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := FText;  // copy the text
end;

{ Builds the Properties dialog for one image. }
constructor TPropsForm.CreateProps(AOwner: TComponent; Item: TImageItem);
var
  W, H: Integer;  // W, H: picture size in pixels
  Ext, Dims: string;  // Ext: file extension; Dims: size text
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  InitDialog(Self, 'Properties - ' + Item.FileName, 620, 480);  // set the common dialog properties
  LV := TListView.Create(Self);  // create the list
  LV.Parent := Self;  // place it on the form
  LV.SetBounds(10, 10, 600, 424);  // position and size it
  LV.ViewStyle := vsReport;  // show columns
  LV.ReadOnly := True;  // user cannot edit the list
  LV.RowSelect := True;  // select whole rows
  with LV.Columns.Add do  // first column
  begin
    Caption := 'Property';
    Width := 140;  // column title
  end;  // column width
  with LV.Columns.Add do  // second column
  begin
    Caption := 'Value';
    Width := 440;  // column title
  end;  // column width

  Ext := LowerCase(ExtractFileExt(Item.FileName));  // file extension in lower case
  Dims := 'not read';  // size text when the file cannot be read
  W := 0;  // no width yet
  H := 0;  // no height yet
  if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') then  // only JPEG files are measured
    if ReadJpegDims(Item.FullPath, W, H) then  // read the pixel size from the file
      Dims := Format('%d x %d pixels', [W, H]);  // format the size text

  AddRow('File name', Item.FileName);  // file name
  if Item.CatalogName <> '' then AddRow('Lightroom photo', Item.CatalogName);  // .lrprev: the photo in the Lightroom catalog
  AddRow('Folder', Item.SourceDir);  // folder
  AddRow('Type', UpperCase(Copy(Ext, 2, 10)) + ' file');  // file type
  AddRow('Size', FormatSize(Item.Size) + '  (' + FormatFloat('#,##0', Item.Size) + ' bytes)');  // size in readable and exact form
  AddRow('Dimensions', Dims);  // picture size
  AddRow('Date modified', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.FileTime));  // file date
  AddRow('Date taken', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.CaptureTime));  // capture date
  AddRow('Camera maker', Item.Make);  // camera maker
  AddRow('Camera model', Item.Camera);  // camera model
  AddRow('Serial number', Item.Serial);  // camera serial number
  AddRow('Author / owner', Item.Owner);  // author or owner
  if Item.ISO > 0 then AddRow('ISO', IntToStr(Item.ISO)) else AddRow('ISO', '');  // ISO value, blank when unknown
  AddRow('Image number', IntToStr(Item.Index));  // image number
  if Item.ClashInfo <> '' then AddRow('Status', Item.StatusText + ' - ' + Item.ClashInfo)  // status with the name clash reason
  else AddRow('Status', Item.StatusText);  // status text
  AddRow('New name', Item.DestPath);  // new file name

  MkButton(Self, 'Copy', 10, 444, 80).OnClick := @CopyClick;  // button that copies the text
  MkButton(Self, 'Close', 530, 444, 80, mrOK).Default := True;  // close button
end;

{ Shows the Properties dialog of an image. }
procedure ShowImageProperties(Item: TImageItem);
var
  F: TPropsForm;  // F: the dialog
begin
  if Item = nil then Exit;  // nothing to show
  F := TPropsForm.CreateProps(Application, Item);  // create the dialog
  try
    F.ShowModal;  // show it and wait
  finally
    F.Free;  // free the dialog
  end;
end;

{ Builds the status dialog; the settings file path is a link that opens its folder. }
constructor TStatusForm.CreateStatus(AOwner: TComponent; const AText, SettingsFile: string);
var
  Lines, TextH: Integer;  // Lines: number of text lines; TextH: height of the text area
  Lk: TLabel;  // Lk: the clickable settings file label
  I: Integer;  // I: character counter
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  FFolder := ExtractFilePath(SettingsFile);  // folder of the settings file
  Lines := 1;  // count the lines of the text
  for I := 1 to Length(AText) do  // every character
    if AText[I] = #10 then Inc(Lines);  // a line break starts another line
  TextH := Lines * 17 + 4;  // height of the text area
  InitDialog(Self, 'Status', 520, TextH + 12 + 20 + 40 + 50);  // set the common dialog properties
  MkWrap(Self, AText, 12, 12, 496, TextH);  // status text
  MkLabel(Self, 'Settings file (click to open its folder):', 12, TextH + 20);  // prompt
  Lk := MkWrap(Self, SettingsFile, 12, TextH + 40, 496, 36);  // settings file path
  Lk.Font.Color := clBlue;  // link color
  Lk.Font.Style := [fsUnderline];  // link underline
  Lk.Cursor := crHandPoint;  // hand cursor over the link
  Lk.Hint := 'Open the folder that contains the settings file';  // tooltip
  Lk.ShowHint := True;  // show the tooltip
  Lk.OnClick := @LinkClick;  // open the folder when clicked
  MkButton(Self, 'OK', 428, TextH + 82, 80, mrOK).Default := True;  // OK button, also the default button
end;

{ Opens the folder that contains the settings file. }
procedure TStatusForm.LinkClick(Sender: TObject);
begin
  if not OpenDocument(FFolder) then  // open the folder in the file manager
    MessageDlg(AppTitle, 'Could not open ' + FFolder, mtWarning, [mbOK], 0);  // tell the user
end;

{ Shows the status dialog. }
procedure ShowStatus(const AText, SettingsFile: string);
var
  F: TStatusForm;  // F: the dialog
begin
  F := TStatusForm.CreateStatus(Application, AText, SettingsFile);  // create the dialog
  try
    F.ShowModal;  // show it and wait
  finally
    F.Free;  // free the dialog
  end;
end;

{ Shows the Register dialog. }
procedure ShowRegister;
var
  F: TRegisterForm;  // F: the dialog
begin
  F := TRegisterForm.CreateReg(Application);  // create the dialog
  try
    F.ShowModal;  // show it and wait
  finally
    F.Free;  // free the dialog
  end;
end;

{ ====================================================================== }
{ Job code dialog                                                         }
{ ====================================================================== }

type
  { Dialog that asks for the job code (and optionally the source folder). }
  TJobForm = class(TForm)
  private
    FS: TAppSettings;  // program settings
    FCamera: string;  // camera name for the example
    cbJob: TComboBox;  // job code box
    edExample, edSource: TEdit;  // example name box and source folder box
    procedure UpdateExample(Sender: TObject);  // refreshes the example name
    procedure DeleteClick(Sender: TObject);  // removes the job code from the history
    procedure PrefsClick(Sender: TObject);  // opens the Preferences dialog
    procedure SourceBrowseClick(Sender: TObject);  // asks for the source folder
  public
    constructor CreateJob(AOwner: TComponent; AS_: TAppSettings; const AJob, ACamera: string;  // builds the dialog
      AskSource: Boolean = False; const ASource: string = '');
  end;

{ Builds the Job Code dialog. }
constructor TJobForm.CreateJob(AOwner: TComponent; AS_: TAppSettings; const AJob, ACamera: string;
  AskSource: Boolean; const ASource: string);
var
  BY: Integer;  // BY: vertical position of the buttons
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  FS := AS_;  // keep the settings
  FCamera := ACamera;  // keep the camera name
  BY := 148;  // buttons sit below the example line
  if AskSource then BY := 214;  // make room for the source folder line
  InitDialog(Self, 'Job Code', 388, BY + 42);  // set the common dialog properties
  MkLabel(Self, 'Please enter the job code:', 10, 14);  // prompt
  cbJob := MkCombo(Self, 10, 34, 296);  // job code box
  cbJob.Items.Assign(FS.JobHistory);  // fill with the history
  cbJob.Text := AJob;  // show the current job code
  cbJob.OnChange := @UpdateExample;  // update the example when the text changes
  MkButton(Self, 'Delete', 316, 33, 60).OnClick := @DeleteClick;  // button that deletes the entry from the history
  MkLabel(Self, 'Example image name:', 10, 72);  // prompt
  edExample := MkEdit(Self, 10, 92, 366);  // example name box
  edExample.ReadOnly := True;  // user cannot edit the example
  if AskSource then
  begin
    MkLabel(Self, 'Source folder (leave empty to choose later):', 10, 130);  // prompt
    edSource := MkEdit(Self, 10, 150, 330);  // source folder box
    edSource.Text := ASource;  // show the current source folder
    MkButton(Self, '...', 348, 149, 28).OnClick := @SourceBrowseClick;  // button that opens the folder chooser
  end;
  MkButton(Self, 'Preferences...', 10, BY, 90).OnClick := @PrefsClick;  // button that opens the Preferences dialog
  MkButton(Self, 'OK', 206, BY, 80, mrOK).Default := True;  // OK button, also the default button
  MkButton(Self, 'Cancel', 296, BY, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
  ActiveControl := cbJob;  // start typing in the job code box
  UpdateExample(nil);  // show the first example
end;

{ Shows an example file name built from the current settings. }
procedure TJobForm.UpdateExample(Sender: TObject);
begin
  edExample.Text := ExampleDest(FS, FS.DownloadDir, FS.FileNameMask, Trim(cbJob.Text));  // build the example name
end;

{ Removes the selected job code from the history. }
procedure TJobForm.DeleteClick(Sender: TObject);
var
  I: Integer;  // I: index of the entry
begin
  I := FS.JobHistory.IndexOf(cbJob.Text);  // find it in the history
  if I >= 0 then FS.JobHistory.Delete(I);  // remove it from the history
  I := cbJob.Items.IndexOf(cbJob.Text);  // find it in the list
  if I >= 0 then cbJob.Items.Delete(I);  // remove it from the list
  cbJob.Text := '';  // clear the box
  UpdateExample(nil);  // refresh the example
end;

{ Opens the Preferences dialog and refreshes the example afterwards. }
procedure TJobForm.PrefsClick(Sender: TObject);
begin
  ExecutePreferences(FS, FCamera);  // show the Preferences dialog
  UpdateExample(nil);  // refresh the example
end;

{ Lets the user choose the source folder. }
procedure TJobForm.SourceBrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser
begin
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  try
    D.Title := 'Select source folder';  // window title
    if (edSource.Text <> '') and DirectoryExists(edSource.Text) then D.InitialDir := edSource.Text;  // start in the current folder when it exists
    if D.Execute then edSource.Text := D.FileName;  // take the chosen folder
  finally
    D.Free;  // free the chooser
  end;
end;

function RunJobDialog(S: TAppSettings; var Job, Source: string; const CurrentCamera: string;
  Ask: Boolean): Boolean; forward;

{ Asks for the job code only; returns True when the user clicked OK. }
function ExecuteJobCode(S: TAppSettings; var Job: string; const CurrentCamera: string): Boolean;
var
  Dummy: string;  // Dummy: unused source folder
begin
  Dummy := '';  // no source folder
  Result := RunJobDialog(S, Job, Dummy, CurrentCamera, False);  // run the dialog without the source folder line
end;

{ Asks for the job code and the source folder; returns True when the user clicked OK. }
function ExecuteJobCodeSource(S: TAppSettings; var Job, Source: string; const CurrentCamera: string): Boolean;
begin
  Result := RunJobDialog(S, Job, Source, CurrentCamera, True);  // run the dialog with the source folder line
end;

{ Shows the Job Code dialog and stores the result in the settings. }
function RunJobDialog(S: TAppSettings; var Job, Source: string; const CurrentCamera: string;
  Ask: Boolean): Boolean;
var
  F: TJobForm;  // F: the dialog
  V: string;  // V: trimmed job code
  I: Integer;  // I: history index
begin
  F := TJobForm.CreateJob(Application, S, Job, CurrentCamera, Ask, Source);  // create the dialog
  try
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then
    begin
      V := Trim(F.cbJob.Text);      // may be blank: the job code is then left out of names
      Job := V;  // return the job code
      if Ask then Source := Trim(F.edSource.Text);  // return the source folder
      I := S.JobHistory.IndexOf(V);  // find the code in the history
      if I >= 0 then S.JobHistory.Delete(I);  // remove the old position
      if (V <> '') and (V <> '{Job Name}') then S.JobHistory.Insert(0, V);  // put it at the top of the history
      while S.JobHistory.Count > 30 do S.JobHistory.Delete(S.JobHistory.Count - 1);  // keep at most 30 entries
    end;
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Generic list chooser (user profiles)                                    }
{ ====================================================================== }

type
  { Helper of the list chooser: a double click chooses the entry. }
  TChooseHelper = class
    Form: TForm;  // the dialog
    List: TListBox;  // the choices
    procedure ListDblClick(Sender: TObject);  // closes the dialog with OK
  end;

{ A double click on an entry chooses it (same as OK). }
procedure TChooseHelper.ListDblClick(Sender: TObject);
begin
  if List.ItemIndex >= 0 then Form.ModalResult := mrOK;  // choose the clicked entry
end;

{ Shows a list of choices (user profiles); returns True and the chosen entry when the user clicked OK
  or double-clicked an entry. }
function ChooseFromList(const ATitle, APrompt: string; Items: TStrings; out Choice: string): Boolean;
var
  F: TForm;  // F: the dialog
  LB: TListBox;  // LB: list of choices
  H: TChooseHelper;  // H: event helper
begin
  Choice := '';  // nothing chosen yet
  F := TForm.CreateNew(Application);  // create the form
  H := TChooseHelper.Create;  // create the helper
  try
    InitDialog(F, ATitle, 340, 290);  // set the common dialog properties
    MkLabel(F, APrompt, 10, 10);  // prompt
    LB := TListBox.Create(F);  // create the list
    LB.Parent := F;  // place it on the form
    LB.SetBounds(10, 32, 320, 210);  // position and size it
    LB.Items.Assign(Items);  // fill with the choices
    if LB.Items.Count > 0 then LB.ItemIndex := 0;  // select the first entry
    H.Form := F;  // the dialog the helper closes
    H.List := LB;  // the list it watches
    LB.OnDblClick := @H.ListDblClick;  // a double click chooses the entry
    MkButton(F, 'OK', 160, 254, 80, mrOK).Default := True;  // OK button, also the default button
    MkButton(F, 'Cancel', 250, 254, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
    Result := (F.ShowModal = mrOK) and (LB.ItemIndex >= 0);  // OK with an entry selected
    if Result then Choice := LB.Items[LB.ItemIndex];  // return the chosen entry
  finally
    H.Free;  // free the helper
    F.Free;  // free the dialog
  end;
end;

type
  { Helper of the Save User Profile dialog: a click in the list puts the name into the box. }
  TProfileNameHelper = class
    List: TListBox;  // saved profiles
    Edit: TEdit;  // name to save under
    Form: TForm;  // the dialog
    procedure ListClick(Sender: TObject);  // copies the chosen profile into the box
    procedure ListDblClick(Sender: TObject);  // picks the profile and saves
  end;

{ Copies the chosen profile name into the name box. }
procedure TProfileNameHelper.ListClick(Sender: TObject);
begin
  if List.ItemIndex >= 0 then Edit.Text := List.Items[List.ItemIndex];  // save over this profile
end;

{ Picks the double-clicked profile and closes the dialog with Save. }
procedure TProfileNameHelper.ListDblClick(Sender: TObject);
begin
  ListClick(Sender);  // copy the name
  if List.ItemIndex >= 0 then Form.ModalResult := mrOK;  // save
end;

{ Asks for the name to save a user profile under: a list of the saved profiles and a name box that
  starts with the profile in use. Double-clicking a profile saves over it. }
function AskProfileName(Items: TStrings; var Name: string): Boolean;
var
  F: TForm;  // F: the dialog
  H: TProfileNameHelper;  // H: event helper
begin
  F := TForm.CreateNew(Application);  // create the form
  H := TProfileNameHelper.Create;  // create the helper
  H.Form := F;  // the dialog it closes
  try
    InitDialog(F, 'Save User Profile', 340, 330);  // set the common dialog properties
    MkLabel(F, 'Saved profiles (click one to save over it):', 10, 10);  // prompt for the list
    H.List := TListBox.Create(F);  // create the list
    H.List.Parent := F;  // place it on the form
    H.List.SetBounds(10, 32, 320, 200);  // position and size it
    H.List.Items.Assign(Items);  // the saved profiles
    H.List.ItemIndex := H.List.Items.IndexOf(Name);  // highlight the profile in use
    MkLabel(F, 'Profile name:', 10, 244);  // prompt for the name
    H.Edit := MkEdit(F, 10, 264, 320);  // name box
    H.Edit.Text := Name;  // the profile in use (or empty)
    H.List.OnClick := @H.ListClick;  // a click picks the profile
    H.List.OnDblClick := @H.ListDblClick;  // a double click saves over it
    MkButton(F, 'Save', 160, 296, 80, mrOK).Default := True;  // Save button, also the default button
    MkButton(F, 'Cancel', 250, 296, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
    F.ActiveControl := H.Edit;  // typing goes into the name box
    H.Edit.SelectAll;  // a new name replaces the suggestion
    Result := F.ShowModal = mrOK;  // True when the user clicked Save
    if Result then Name := Trim(H.Edit.Text);  // return the name
  finally
    H.Free;  // free the helper
    F.Free;  // free the dialog
  end;
end;

{ ====================================================================== }
{ File type filter                                                        }
{ ====================================================================== }

type
  { Helper that holds the check list of the File Types dialog and its button handlers. }
  TTypesHelper = class
    List: TCheckListBox;  // list of file types with check boxes
    procedure AllClick(Sender: TObject);  // checks every type
    procedure NoneClick(Sender: TObject);  // clears every type
    procedure DefaultClick(Sender: TObject);  // sets every type to the application default
  end;

{ Checks every file type. }
procedure TTypesHelper.AllClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to List.Items.Count - 1 do List.Checked[I] := True;  // check each entry
end;

{ Clears every file type. }
procedure TTypesHelper.NoneClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to List.Items.Count - 1 do List.Checked[I] := False;  // uncheck each entry
end;

{ Sets every file type to the application default. }
procedure TTypesHelper.DefaultClick(Sender: TObject);
var
  I: Integer;  // I: loop counter
begin
  for I := 0 to List.Items.Count - 1 do List.Checked[I] := FileTypeDefaultOn(I);  // default for each entry
end;

{ Shows the File Types dialog and stores the selection in the settings. }
function ExecuteFileTypes(S: TAppSettings): Boolean;
var
  F: TForm;  // F: the dialog
  H: TTypesHelper;  // H: handler object for the list
  B: TButton;  // B: button being created
  I, RowH, Y: Integer;  // I: loop counter; RowH: height of one list row; Y: top of the buttons
begin
  F := TForm.CreateNew(Application);  // create the form
  H := TTypesHelper.Create;  // create the helper
  try
    InitDialog(F, 'File Types', 360, 440);  // set the common dialog properties
    MkLabel(F, 'Show these file types:', 10, 10);  // prompt
    H.List := TCheckListBox.Create(F);  // create the list
    H.List.Parent := F;  // place it on the form
    H.List.SetBounds(10, 32, 340, 330);  // position and size it
    for I := 0 to FileTypeCount - 1 do  // every known file type
    begin
      H.List.Items.Add(FileTypeNames[I]);  // add its name
      H.List.Checked[I] := S.TypeOn[I];  // check it when it is enabled
    end;
    // make the list tall enough to show every type without scrolling: rows are taller on Linux
    // and with larger fonts, so one row is measured once the list exists
    H.List.HandleNeeded;  // create the list so a row can be measured
    RowH := H.List.ItemRect(0).Bottom - H.List.ItemRect(0).Top;  // height of one row
    if (RowH < 12) or (RowH > 48) then RowH := 18;  // implausible measurement: use a usual row height
    H.List.Height := FileTypeCount * RowH + (H.List.Height - H.List.ClientHeight) + 4;  // every row plus the border
    Y := H.List.Top + H.List.Height + 10;  // buttons below the list
    F.ClientHeight := Y + 78;  // room for the two button rows
    B := MkButton(F, 'Select all', 10, Y, 100);  // Select all button
    B.OnClick := @H.AllClick;  // connect its handler
    B := MkButton(F, 'Clear all', 120, Y, 100);  // Clear all button
    B.OnClick := @H.NoneClick;  // connect its handler
    B := MkButton(F, 'Default', 230, Y, 100);  // Default button
    B.OnClick := @H.DefaultClick;  // connect its handler
    MkButton(F, 'OK', 180, Y + 34, 80, mrOK).Default := True;  // OK button, also the default button
    MkButton(F, 'Cancel', 270, Y + 34, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then
      for I := 0 to FileTypeCount - 1 do S.TypeOn[I] := H.List.Checked[I];  // store the selection
  finally
    H.Free;  // free the helper
    F.Free;  // free the dialog
  end;
end;

{ ====================================================================== }
{ IPTC / XMP dialog                                                       }
{ ====================================================================== }

{ Shows the IPTC/XMP dialog; L holds the values as name=value lines. }
function ExecuteIptc(L: TStringList): Boolean;
const
  Keys: array[0..8] of string =  // names of the fields
    ('Creator', 'Copyright', 'Credit', 'Source', 'Title', 'Description', 'City', 'Country', 'Keywords');
var
  F: TForm;  // F: the dialog
  Ed: array[0..8] of TEdit;  // Ed: edit boxes, one per field
  I: Integer;  // I: loop counter
begin
  F := TForm.CreateNew(Application);  // create the form
  try
    InitDialog(F, 'IPTC/XMP data', 420, 340);  // set the common dialog properties
    for I := 0 to High(Keys) do  // every field
    begin
      MkLabel(F, Keys[I] + ':', 10, 14 + I * 30 + 3);  // field label
      Ed[I] := MkEdit(F, 100, 14 + I * 30, 306);  // edit box for the field
      Ed[I].Text := L.Values[Keys[I]];  // show the current value
    end;
    MkLabel(F, 'Keywords are separated by commas.', 100, 14 + 9 * 30 - 4);  // hint for the keywords field
    MkButton(F, 'OK', 236, 304, 80, mrOK).Default := True;  // OK button, also the default button
    MkButton(F, 'Cancel', 326, 304, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then
      for I := 0 to High(Keys) do  // every field
        L.Values[Keys[I]] := Trim(Ed[I].Text);  // store the trimmed value
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Edit camera mapping                                                     }
{ ====================================================================== }

{ Shows the Edit mapping dialog for one camera; T8 and T9 are the custom token values. }
function EditMapping(const Cam: string; var T8, T9: string): Boolean;
var
  F: TForm;  // F: the dialog
  E8, E9: TEdit;  // E8, E9: edit boxes for the two tokens
begin
  F := TForm.CreateNew(Application);  // create the form
  try
    InitDialog(F, 'Edit mapping', 380, 150);  // set the common dialog properties
    MkLabel(F, 'Camera: ' + Cam, 10, 12);  // camera name
    MkLabel(F, '{T8} =', 10, 46);  // label of the first token
    E8 := MkEdit(F, 70, 42, 300);  // edit box for the first token
    E8.Text := T8;  // show the current value
    MkLabel(F, '{T9} =', 10, 78);  // label of the second token
    E9 := MkEdit(F, 70, 74, 300);  // edit box for the second token
    E9.Text := T9;  // show the current value
    MkButton(F, 'OK', 200, 114, 80, mrOK).Default := True;  // OK button, also the default button
    MkButton(F, 'Cancel', 290, 114, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then
    begin
      T8 := E8.Text;  // return the first token
      T9 := E9.Text;  // return the second token
    end;
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Plug-in prompt window                                                   }
{ ====================================================================== }

{ The fixed start of a download folder template: the folders before the first token. }
function DestRootOf(const DirMask: string): string;
var
  I: Integer;  // I: position of the first token
begin
  Result := DirMask;  // the whole template
  I := Pos('{', Result);  // first token
  if I > 0 then Result := ExtractFilePath(Copy(Result, 1, I - 1));  // the folders before it
end;

type
  { Window that asks for the values of a plug-in library. It is drawn from the library's field list;
    the library checks the values (pd_check) and returns a preview, an error text and values to set. }
  TPluginPromptForm = class(TForm)
  private
    FPlugin: TLibPlugin;  // the plug-in
    FCtrls: array of TWinControl;  // one control per field (TComboBox or TEdit)
    FUpdating: Boolean;  // True while the program changes the controls
    FChanged: string;  // key of the field changed last
    FNormal: string;  // normalized values from the last check (Value.<key>= lines)
    FDestDir: string;  // download folder template (changed by "Destination folder...")
    lblDest: TLabel;  // shows the download folder template
    lblPreview, lblError: TLabel;  // preview and error text
    BtnOK: TButton;  // OK button (only enabled when the values are valid)
    function FieldValue(I: Integer): string;  // value of one field
    procedure SetFieldValue(I: Integer; const V: string);  // shows a value in one field
    procedure ApplyCheck(const Extra: string);  // lets the plug-in check the values and shows the result
    procedure FieldChange(Sender: TObject);  // a field was changed
    procedure FolderClick(Sender: TObject);  // chooses the destination folder to download to
    procedure ApplyFolderFields;  // adds or removes the folder tokens of check fields at the end of the download path
    function DestTemplate: string;  // the plug-in's suggested folders, with this system's separators
    function UsesLayout(const Rest: string): Boolean;  // True when the token part keeps the plug-in's main folder token
  public
    constructor CreatePrompt(AOwner: TComponent; P: TLibPlugin; const Values, DestDir: string);  // builds the window
    property DestDir: string read FDestDir;  // the download folder template after the window closed
    function Values: string;  // the values as key=value lines (normalized by the plug-in)
  end;

{ Builds the window: logo header, accent bar, one row per field, preview, error and buttons.
  The window is as wide as the longest label and the controls need (at least 600 pixels). }
constructor TPluginPromptForm.CreatePrompt(AOwner: TComponent; P: TLibPlugin; const Values, DestDir: string);
const
  CtlW = 320;  // width of the controls
var
  Head: TPanel;  // Head: white header with the logo
  Bar: TPanel;  // Bar: accent color bar under the header
  Img: TImage;  // Img: the logo
  Png: TPortableNetworkGraphic;  // Png: the logo picture
  Lab: TLabel;  // Lab: a field label
  I, J, Y, HeadH, LabW, CtlX, W: Integer;  // I, J: loop counters; Y: row position; HeadH: header height; LabW: widest label; CtlX: left edge of the controls; W: window width
  Cb: TComboBox;  // Cb: a list field
  V, Fnt, Acc: string;  // V: stored value; Fnt: font name; Acc: accent color (hex RRGGBB)
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  FPlugin := P;  // remember the plug-in
  FDestDir := DestDir;  // the download folder template
  Head := nil;  // no header yet
  Bar := nil;  // no bar yet
  Fnt := P.Info.Values['FontName'];  // font asked for by the plug-in
  if (Fnt <> '') and (Screen.Fonts.IndexOf(Fnt) >= 0) then Font.Name := Fnt;  // use it when it is installed
  HeadH := 0;  // no header yet
  W := 600;  // smallest window width
  if P.Logo <> nil then  // the plug-in has a logo
  begin
    Head := TPanel.Create(Self);  // create the header
    Head.Parent := Self;  // place it on the form
    Head.BevelOuter := bvNone;  // flat
    Head.Color := clWhite;  // logos go on a plain white background
    Head.ParentBackground := False;  // keep the white color
    Png := TPortableNetworkGraphic.Create;  // create the picture
    try
      P.Logo.Position := 0;  // read from the start
      Png.LoadFromStream(P.Logo);  // load the PNG
      Img := TImage.Create(Self);  // create the image control
      Img.Parent := Head;  // place it on the header
      Img.Picture.Assign(Png);  // show the logo at its own size (never stretched)
      Img.SetBounds(18, 18, Png.Width, Png.Height);  // 18 px clear space around it
      HeadH := Png.Height + 36;  // header height with the clear space
      W := Max(W, Png.Width + 36);  // room for the logo
    except
      HeadH := 0;  // a broken logo is left out
    end;
    Png.Free;  // free the picture
    Head.Visible := HeadH > 0;  // hide it without a logo
  end;
  Acc := P.Info.Values['AccentColor'];  // accent color as RRGGBB
  if Length(Acc) = 6 then  // a color is given
  begin
    Bar := TPanel.Create(Self);  // create the bar
    Bar.Parent := Self;  // place it on the form
    Bar.BevelOuter := bvNone;  // flat
    Bar.ParentBackground := False;  // keep the color
    Bar.Color := RGBToColor(StrToIntDef('$' + Copy(Acc, 1, 2), 0), StrToIntDef('$' + Copy(Acc, 3, 2), 0),
      StrToIntDef('$' + Copy(Acc, 5, 2), 0));  // RRGGBB to a color
    Inc(HeadH, 6);  // rows start below the bar
  end;
  // labels first, so the controls can start right of the widest one (measured in the window's font)
  Y := HeadH + 14;  // first row
  LabW := 0;  // widest label so far
  Canvas.Font := Font;  // measure in the window's font
  for I := 0 to High(P.Fields) do  // every field (a check box carries its own text)
    if P.Fields[I].Kind <> 'check' then LabW := Max(LabW, Canvas.TextWidth(P.Fields[I].Caption + ':'));  // width of its label
  CtlX := 12 + LabW + 8;  // controls start here
  for I := 0 to High(P.Fields) do  // labels right-aligned, ending next to their control
  begin
    if P.Fields[I].Kind = 'check' then Continue;  // a check box carries its own text
    Lab := MkLabel(Self, P.Fields[I].Caption + ':', 12, Y + I * 32 + 3);  // label
    Lab.AutoSize := False;  // keep the width set below
    Lab.Alignment := taRightJustify;  // text against the right edge
    Lab.SetBounds(12, Y + I * 32 + 3, LabW, Lab.Height);  // same right edge for every label
  end;
  W := Max(W, CtlX + CtlW + 14);  // window width
  SetLength(FCtrls, Length(P.Fields));  // one control per field
  for I := 0 to High(P.Fields) do  // every field
  begin
    if P.Fields[I].Kind = 'check' then  // on or off
    begin
      FCtrls[I] := MkCheck(Self, P.Fields[I].Caption, CtlX, Y + 2);  // check box with its text
      FCtrls[I].Width := CtlW;  // as wide as the other controls
      TCheckBox(FCtrls[I]).OnClick := @FieldChange;  // react to every change
    end
    else if P.Fields[I].Kind = 'text' then  // free text
    begin
      FCtrls[I] := MkEdit(Self, CtlX, Y, CtlW);  // edit box
      if P.Fields[I].Upper then TEdit(FCtrls[I]).CharCase := ecUppercase;  // capitals only
      TEdit(FCtrls[I]).OnChange := @FieldChange;  // check on every change
    end
    else
    begin
      Cb := MkCombo(Self, CtlX, Y, CtlW);  // list box
      if P.Fields[I].Kind = 'choice' then Cb.Style := csDropDownList;  // only the listed values
      if P.Fields[I].Upper then Cb.CharCase := ecUppercase;  // capitals only
      Cb.DropDownCount := 20;  // show many entries
      for J := 0 to High(P.Fields[I].Labels) do Cb.Items.Add(P.Fields[I].Labels[J]);  // the entries
      Cb.OnChange := @FieldChange;  // check on every change
      FCtrls[I] := Cb;  // remember it
    end;
    FCtrls[I].Tag := I;  // field index
    V := LineValue(Values, P.Fields[I].Key);  // stored value
    if V = '' then V := P.Fields[I].Default;  // or the default
    FUpdating := True;  // no checks while filling
    SetFieldValue(I, V);  // show it
    FUpdating := False;  // react to changes again
    Inc(Y, 32);  // next row
  end;
  if P.Info.Values['Note'] <> '' then  // a reminder from the plug-in
  begin
    Lab := MkWrap(Self, P.Info.Values['Note'], 12, Y + 4, W - 24, 48);  // the reminder under the fields
    Lab.Alignment := taCenter;  // centered
    Lab.Font.Color := clRed;  // in red, so it is noticed
    Inc(Y, 54);  // room for it
  end;
  if Head <> nil then Head.SetBounds(0, 0, W, HeadH - Ord(Bar <> nil) * 6);  // header over the full width
  if Bar <> nil then Bar.SetBounds(0, HeadH - 6, W, 6);  // bar over the full width, under the header
  lblPreview := MkLabel(Self, '', 12, Y + 6);  // preview of the result
  lblPreview.Font.Style := [fsBold];  // bold
  lblError := MkWrap(Self, '', 12, Y + 28, W - 24, 36);  // error text
  lblError.Font.Color := clRed;  // red
  Inc(Y, 72);  // room for preview and error
  if P.Info.Values['DestFolder'] = '1' then  // the plug-in lets the user choose the destination here
  begin
    lblDest := MkWrap(Self, '', 12, Y, W - 24, 36);  // the download folder template
    lblDest.Caption := 'Download to: ' + FDestDir;  // show it
    Inc(Y, 40);  // room for it
    MkButton(Self, 'Destination folder...', 12, Y, 150).OnClick := @FolderClick;  // choose the destination
  end;
  BtnOK := MkButton(Self, 'OK', W - 184, Y, 80, mrOK);  // OK button
  BtnOK.Default := True;  // reacts to Enter
  MkButton(Self, 'Cancel', W - 94, Y, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
  InitDialog(Self, P.Info.Values['Title'], W, Y + 40);  // size and title
  if Caption = '' then Caption := P.DisplayName;  // title fallback
  if P.Info.Values['Version'] <> '' then Caption := Caption + ' - version ' + P.Info.Values['Version'];  // version in the title bar
  if (Head <> nil) and (P.Info.Values['Version'] <> '') then  // and at the top right of the header
  begin
    Lab := MkLabel(Head, 'Version ' + P.Info.Values['Version'], 0, 0);  // version text
    Lab.Font.Color := clGray;  // quiet
    Lab.SetBounds(W - Canvas.TextWidth(Lab.Caption) - 18, 18, Lab.Width, Lab.Height);  // top right, inside the clear space
  end;
  // a download path without the plug-in's layout (for example only ...\{UAS.Media}\) gets it back
  if (P.Info.Values['DestFolder'] = '1') and (FDestDir <> '') and
     not UsesLayout(Copy(FDestDir, Length(DestRootOf(FDestDir)) + 1, MaxInt)) then
    FDestDir := IncludeTrailingPathDelimiter(DestRootOf(FDestDir)) + DestTemplate;  // destination + plug-in folders
  ApplyFolderFields;  // the download path follows the check boxes
  ApplyCheck('');  // first check: preview and error
end;

{ Check fields with folder tokens: removes those tokens from the end of the download path and adds the
  first one again while the box is checked (for example "Organize files by type" adds the folder token UAS.Media at the end). }
procedure TPluginPromptForm.ApplyFolderFields;
var
  I: Integer;  // I: field index
  S, T: string;  // S: download path without the closing separator; T: one folder token
  Toks: TStringArray;  // Toks: the folder tokens of a field
  Found: Boolean;  // Found: a token was removed in this round
begin
  for I := 0 to High(FCtrls) do  // every field
  begin
    if not (FCtrls[I] is TCheckBox) or (FPlugin.Fields[I].FolderTokens = '') then Continue;  // not a folder check box
    Toks := FPlugin.Fields[I].FolderTokens.Split([';']);  // its tokens
    S := FDestDir;  // the download path
    while (S <> '') and (S[Length(S)] in ['\', '/']) do Delete(S, Length(S), 1);  // without the closing separator
    repeat
      Found := False;  // nothing removed yet
      for T in Toks do  // each token (case matters: {E} and {e} differ)
        if (T <> '') and (Length(S) > Length(T) + 3) and
           (Copy(S, Length(S) - Length(T) - 2, Length(T) + 3) = PathDelim + '{' + T + '}') then
        begin
          SetLength(S, Length(S) - Length(T) - 3);  // remove the last folder
          Found := True;  // look again
        end;
    until not Found;
    if TCheckBox(FCtrls[I]).Checked and (Length(Toks) > 0) then
      S := S + PathDelim + '{' + Toks[0] + '}';  // one folder per type
    FDestDir := IncludeTrailingPathDelimiter(S);  // the new download path
  end;
  if lblDest <> nil then lblDest.Caption := 'Download to: ' + FDestDir;  // show it
end;

{ Value of one field: the listed value of the chosen entry, or the typed text. }
function TPluginPromptForm.FieldValue(I: Integer): string;
var
  Cb: TComboBox;  // Cb: the list box
begin
  if FCtrls[I] is TCheckBox then Exit(IntToStr(Ord(TCheckBox(FCtrls[I]).Checked)));  // 1 = checked, 0 = not
  if FCtrls[I] is TEdit then Exit(TEdit(FCtrls[I]).Text);  // typed text
  Cb := TComboBox(FCtrls[I]);  // list box
  if (Cb.ItemIndex >= 0) and (Cb.Text = Cb.Items[Cb.ItemIndex]) then  // an entry of the list
    Result := FPlugin.Fields[I].Values[Cb.ItemIndex]  // its value
  else
    Result := Cb.Text;  // typed text (combo fields)
end;

{ Shows a value in one field: selects the entry with that value, or shows the text. }
procedure TPluginPromptForm.SetFieldValue(I: Integer; const V: string);
var
  J: Integer;  // J: entry index
  Cb: TComboBox;  // Cb: the list box
begin
  if FCtrls[I] is TCheckBox then  // on or off
  begin
    TCheckBox(FCtrls[I]).Checked := V = '1';  // 1 = checked
    Exit;
  end;
  if FCtrls[I] is TEdit then  // free text
  begin
    TEdit(FCtrls[I]).Text := V;  // show it
    Exit;
  end;
  Cb := TComboBox(FCtrls[I]);  // list box
  for J := 0 to High(FPlugin.Fields[I].Values) do  // look for the value
    if SameText(FPlugin.Fields[I].Values[J], V) then
    begin
      Cb.ItemIndex := J;  // select it
      Exit;
    end;
  Cb.ItemIndex := -1;  // not listed
  if Cb.Style <> csDropDownList then Cb.Text := V;  // combo fields show the text
end;

{ The field values as key=value lines. }
function TPluginPromptForm.Values: string;
var
  I: Integer;  // I: field index
  V: string;  // V: value
begin
  Result := '';  // nothing yet
  for I := 0 to High(FCtrls) do  // every field
  begin
    V := LineValue(FNormal, 'Value.' + FPlugin.Fields[I].Key);  // the plug-in's normalized value
    if V = '' then V := FieldValue(I);  // or the value as entered
    Result := Result + FPlugin.Fields[I].Key + '=' + V + LineEnding;  // add the line
  end;
end;

{ Lets the plug-in check the values; shows the preview and error and applies Set.<key>= lines. }
procedure TPluginPromptForm.ApplyCheck(const Extra: string);
var
  I: Integer;  // I: field index
  Cur, Res, V: string;  // Cur: current values; Res: result lines; V: a value to set
begin
  Cur := '';  // nothing yet
  for I := 0 to High(FCtrls) do Cur := Cur + FPlugin.Fields[I].Key + '=' + FieldValue(I) + LineEnding;  // current values
  Cur := Cur + '_changed=' + FChanged + LineEnding + Extra;  // which field changed, and extra lines
  Res := FPlugin.Check(Cur);  // ask the plug-in
  FUpdating := True;  // no checks while setting values
  try
    for I := 0 to High(FCtrls) do  // values the plug-in sets (for example the district of a county)
    begin
      V := LineValue(Res, 'Set.' + FPlugin.Fields[I].Key);  // value to set
      if V <> '' then SetFieldValue(I, V);  // show it
    end;
  finally
    FUpdating := False;  // react to changes again
  end;
  FNormal := Res;  // keep the normalized values
  lblPreview.Caption := LineValue(Res, 'Preview');  // preview of the result
  lblError.Caption := LineValue(Res, 'Error');  // error text
  BtnOK.Enabled := lblError.Caption = '';  // OK only for valid values
  for I := 0 to High(FCtrls) do  // fields the plug-in marks as wrong (Invalid.<key>=1): light red with dark red text
    if (FCtrls[I] is TEdit) or (FCtrls[I] is TComboBox) then
      if LineValue(Res, 'Invalid.' + FPlugin.Fields[I].Key) = '1' then
      begin
        FCtrls[I].Color := RGBToColor(255, 214, 214);  // light red background
        FCtrls[I].Font.Color := RGBToColor(160, 0, 0);  // dark red text (also seen where a widgetset ignores the background)
      end
      else
      begin
        FCtrls[I].Color := clDefault;  // normal background
        FCtrls[I].Font.Color := clDefault;  // normal text
      end;
end;

{ A field was changed: check again. }
procedure TPluginPromptForm.FieldChange(Sender: TObject);
begin
  if FUpdating then Exit;  // change made by the program
  FChanged := FPlugin.Fields[TWinControl(Sender).Tag].Key;  // which field
  if Sender is TCheckBox then ApplyFolderFields;  // a check box can change the download path
  ApplyCheck('');  // check the values
end;

{ The plug-in's suggested folders below the destination (DestTemplate), with this system's separators. }
function TPluginPromptForm.DestTemplate: string;
begin
  Result := StringReplace(StringReplace(FPlugin.Info.Values['DestTemplate'], '\', PathDelim, [rfReplaceAll]),
    '/', PathDelim, [rfReplaceAll]);  // both separators to this system's one
end;

{ True when the token part of a download path keeps the plug-in's layout: it holds the first token of
  DestTemplate (for example the project folder token UAS). A path that only holds a type folder such as
  the token UAS.Media does not count, so the plug-in's layout is used again. }
function TPluginPromptForm.UsesLayout(const Rest: string): Boolean;
var
  T: string;  // T: the main token of DestTemplate, with braces
  I, J: Integer;  // I, J: positions of its braces
begin
  T := DestTemplate;  // the suggested folders
  I := Pos('{', T);  // first token
  J := Pos('}', T);  // its end
  if (I = 0) or (J < I) then Exit(True);  // no token to look for: keep the user's layout
  T := LowerCase(Copy(T, I, J - I + 1));  // for example {uas}
  Result := Pos(T, LowerCase(Rest)) > 0;  // the layout holds it
end;

{ Chooses the destination folder to download to. The download folder template becomes the chosen
  folder plus the token part of the current template when that uses the plug-in's tokens, otherwise
  plus the plug-in's suggested folder template (DestTemplate). }
procedure TPluginPromptForm.FolderClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser
  Root, Rest: string;  // Root: current destination folder; Rest: token part of the template
begin
  Root := DestRootOf(FDestDir);  // current destination folder
  Rest := Copy(FDestDir, Length(Root) + 1, MaxInt);  // folders built from tokens
  if not UsesLayout(Rest) then Rest := DestTemplate;  // use the folder template the plug-in suggests
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  try
    D.Title := 'Choose the destination folder to download to';  // window title
    if (Root <> '') and DirectoryExists(Root) then D.InitialDir := Root;  // start in the current destination
    if D.Execute then  // a folder was chosen
    begin
      FDestDir := IncludeTrailingPathDelimiter(D.FileName) + Rest;  // the new download folder template
      ApplyFolderFields;  // the check boxes decide the last folders (shows the result too)
    end;
  finally
    D.Free;  // free the chooser
  end;
end;

{ Shows the prompt window of one plug-in; on OK, Values (key=value lines) and DestDir (the download
  folder template, which "Destination folder..." can change) are updated. }
function ExecutePluginPrompt(P: TLibPlugin; var Values, DestDir: string): Boolean;
var
  F: TPluginPromptForm;  // F: the window
begin
  F := TPluginPromptForm.CreatePrompt(Application, P, Values, DestDir);  // build the window
  try
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then
    begin
      Values := F.Values;  // return the values
      DestDir := F.DestDir;  // and the download folder template
    end;
  finally
    F.Free;  // free the window
  end;
end;

{ Asks every switched-on plug-in with prompt fields for its values (before a download);
  False when the user canceled. The values are stored in S.PluginOpts, a new destination in S.DownloadDir. }
function AskPluginValues(S: TAppSettings): Boolean;
var
  L: TList;  // L: plug-ins with prompt fields
  I: Integer;  // I: list index
  P: TLibPlugin;  // P: one plug-in
  V, D: string;  // V: its values; D: download folder template
begin
  Result := True;  // nothing canceled yet
  L := PromptPlugins(S);  // plug-ins that ask for values
  try
    for I := 0 to L.Count - 1 do  // every one of them
    begin
      P := TLibPlugin(L[I]);  // the plug-in
      V := PluginValues(S.PluginOpts, P.Key);  // stored values
      D := S.DownloadDir;  // current download folder template
      if not ExecutePluginPrompt(P, V, D) then Exit(False);  // canceled
      SetPluginValues(S.PluginOpts, P.Key, V);  // store the new values
      S.DownloadDir := D;  // and the destination
    end;
  finally
    L.Free;  // free the list
  end;
end;

{ ====================================================================== }
{ JPEG auto profile setup                                                 }
{ ====================================================================== }

type
  { Setup of the built-in plug-in "JPEG auto profile": one ICC profile per camera model and a default.
    The choices are key=value lines: Default=<profile file>, Replace=0/1, Cam.<camera model>=<profile file>. }
  TJpegProfileForm = class(TForm)
  private
    FCams: TStringList;  // camera model=profile file
    FCamera: string;  // camera of the picture shown in the main window (suggested when adding)
    lbCams: TListBox;  // the list of cameras
    edDefault: TEdit;  // default profile
    chkReplace: TCheckBox;  // replace a profile the camera embedded
    procedure FillList;  // shows FCams in the list
    function PickProfile(const Start: string; out FileName: string): Boolean;  // chooses a profile file
    procedure AddClick(Sender: TObject);  // adds a camera
    procedure EditClick(Sender: TObject);  // chooses another profile for the selected camera
    procedure RemoveClick(Sender: TObject);  // removes the selected camera
    procedure DefaultClick(Sender: TObject);  // chooses the default profile
  public
    constructor CreateSetup(AOwner: TComponent; const Opts, Camera: string);  // builds the window
    destructor Destroy; override;  // frees the list
    function Opts: string;  // the choices as key=value lines
  end;

{ Builds the window and fills it from the stored choices. }
constructor TJpegProfileForm.CreateSetup(AOwner: TComponent; const Opts, Camera: string);
var
  L: TStringList;  // L: the stored choices
  I: Integer;  // I: line index
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  InitDialog(Self, 'JPEG auto profile', 560, 380);  // set the common dialog properties
  FCamera := Camera;  // suggested camera
  FCams := TStringList.Create;  // camera=profile lines
  L := TStringList.Create;  // the stored choices
  try
    L.Text := Opts;  // split into lines
    for I := 0 to L.Count - 1 do
      if Copy(L.Names[I], 1, 4) = 'Cam.' then FCams.Add(Copy(L.Names[I], 5, MaxInt) + '=' + L.ValueFromIndex[I]);  // one camera
    MkLabel(Self, 'ICC profile for each camera model (exactly as the camera writes it into the EXIF data):', 10, 10);  // label
    lbCams := TListBox.Create(Self);  // the camera list
    lbCams.Parent := Self;  // place it on the form
    lbCams.SetBounds(10, 32, 430, 180);  // position and size it
    lbCams.OnDblClick := @EditClick;  // a double click chooses another profile
    MkButton(Self, 'Add...', 450, 32, 100).OnClick := @AddClick;  // add a camera
    MkButton(Self, 'Profile...', 450, 64, 100).OnClick := @EditClick;  // another profile for a camera
    MkButton(Self, 'Remove', 450, 96, 100).OnClick := @RemoveClick;  // remove a camera
    MkLabel(Self, 'Default profile for all other cameras (empty = none):', 10, 224);  // label
    edDefault := MkEdit(Self, 10, 244, 430);  // default profile
    edDefault.Text := L.Values['Default'];  // stored default
    MkButton(Self, '...', 450, 243, 30).OnClick := @DefaultClick;  // choose the default profile
    chkReplace := MkCheck(Self, 'Replace a profile the camera already embedded in the JPEG', 10, 282);  // replace option
    chkReplace.Checked := L.Values['Replace'] = '1';  // stored choice
    MkWrap(Self, 'The profile is added to the downloaded copy without recompressing the picture; the backup copy and the original are not changed.',
      10, 306, 540, 34);  // note
  finally
    L.Free;  // free the lines
  end;
  FillList;  // show the cameras
  MkButton(Self, 'OK', 380, 344, 80, mrOK).Default := True;  // OK button, also the default button
  MkButton(Self, 'Cancel', 470, 344, 80, mrCancel).Cancel := True;  // Cancel button, also reacts to Esc
end;

{ Frees the camera list. }
destructor TJpegProfileForm.Destroy;
begin
  FCams.Free;  // free the list
  inherited Destroy;  // run the inherited destructor
end;

{ Shows the cameras with their profile files. }
procedure TJpegProfileForm.FillList;
var
  I, Sel: Integer;  // I: line index; Sel: selected line
begin
  Sel := lbCams.ItemIndex;  // keep the selection
  lbCams.Items.Clear;  // empty the list
  for I := 0 to FCams.Count - 1 do
    lbCams.Items.Add(FCams.Names[I] + '  ->  ' + ExtractFileName(FCams.ValueFromIndex[I]));  // camera -> profile
  if Sel >= lbCams.Items.Count then Sel := lbCams.Items.Count - 1;  // the list got shorter
  lbCams.ItemIndex := Sel;  // select again
end;

{ Chooses an ICC profile file and checks that it is one. }
function TJpegProfileForm.PickProfile(const Start: string; out FileName: string): Boolean;
var
  OD: TOpenDialog;  // OD: file chooser
begin
  Result := False;  // nothing chosen yet
  FileName := '';  // no file yet
  OD := TOpenDialog.Create(Self);  // create the chooser
  try
    OD.Title := 'Choose an ICC color profile';  // window title
    OD.Filter := 'ICC profiles (*.icc;*.icm)|*.icc;*.icm;*.ICC;*.ICM|All files|*.*';  // profile files
    if Start <> '' then OD.InitialDir := ExtractFilePath(Start)  // start where the current one is
    {$IFDEF WINDOWS}
    else OD.InitialDir := GetEnvironmentVariable('SystemRoot') + '\System32\spool\drivers\color'  // the Windows profiles
    {$ELSE}
    else if DirectoryExists('/usr/share/color/icc') then OD.InitialDir := '/usr/share/color/icc'  // the usual Linux place
    {$ENDIF};
    if not OD.Execute then Exit;  // canceled
    if not IsIccProfile(OD.FileName) then  // not a profile
    begin
      MessageDlg('JPEG auto profile', 'This file is not an ICC color profile:'#13#10 + OD.FileName, mtError, [mbOK], 0);  // tell the user
      Exit;
    end;
    FileName := OD.FileName;  // the profile
    Result := True;  // chosen
  finally
    OD.Free;  // free the chooser
  end;
end;

{ Adds a camera: asks for its model name (the one in the main window is suggested), then for the profile. }
procedure TJpegProfileForm.AddClick(Sender: TObject);
var
  Cam, Fn: string;  // Cam: camera model; Fn: profile file
begin
  Cam := FCamera;  // suggest the camera of the pictures shown
  if not InputQuery('JPEG auto profile', 'Camera model (as in the EXIF data, for example NIKON D700):', Cam) then Exit;  // ask
  Cam := Trim(Cam);  // no blanks around it
  if (Cam = '') or (Pos('=', Cam) > 0) then Exit;  // no usable name
  if not PickProfile('', Fn) then Exit;  // choose the profile
  FCams.Values[Cam] := Fn;  // add or replace the camera
  FillList;  // show it
end;

{ Chooses another profile for the selected camera. }
procedure TJpegProfileForm.EditClick(Sender: TObject);
var
  Fn: string;  // Fn: profile file
begin
  if lbCams.ItemIndex < 0 then Exit;  // nothing selected
  if not PickProfile(FCams.ValueFromIndex[lbCams.ItemIndex], Fn) then Exit;  // choose the profile
  FCams.ValueFromIndex[lbCams.ItemIndex] := Fn;  // store it
  FillList;  // show it
end;

{ Removes the selected camera. }
procedure TJpegProfileForm.RemoveClick(Sender: TObject);
begin
  if lbCams.ItemIndex < 0 then Exit;  // nothing selected
  FCams.Delete(lbCams.ItemIndex);  // remove it
  FillList;  // show the rest
end;

{ Chooses the default profile. }
procedure TJpegProfileForm.DefaultClick(Sender: TObject);
var
  Fn: string;  // Fn: profile file
begin
  if PickProfile(edDefault.Text, Fn) then edDefault.Text := Fn;  // store it
end;

{ The choices as key=value lines. }
function TJpegProfileForm.Opts: string;
var
  I: Integer;  // I: camera index
begin
  Result := 'Default=' + Trim(edDefault.Text) + LineEnding +  // default profile
    'Replace=' + IntToStr(Ord(chkReplace.Checked)) + LineEnding;  // replace option
  for I := 0 to FCams.Count - 1 do
    Result := Result + 'Cam.' + FCams.Names[I] + '=' + FCams.ValueFromIndex[I] + LineEnding;  // one camera
end;

{ Shows the JPEG auto profile setup; Opts (key=value lines) is updated on OK. }
function ExecuteJpegProfileSetup(var Opts: string; const Camera: string): Boolean;
var
  F: TJpegProfileForm;  // F: the window
begin
  F := TJpegProfileForm.CreateSetup(Application, Opts, Camera);  // build the window
  try
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then Opts := F.Opts;  // return the choices
  finally
    F.Free;  // free the window
  end;
end;

{ ====================================================================== }
{ Preferences dialog                                                      }
{ ====================================================================== }

type
  { The Preferences dialog with its tabs. }
  TPrefsForm = class(TForm)
  private
    FS: TAppSettings;  // program settings
    FCamera: string;  // camera name for the example
    FMaps, FPlugins, FPluginOpts: TStringList;  // FMaps: camera mappings; FPlugins: plug-in list; FPluginOpts: plug-in options
    FResetSeq, FUpdating: Boolean;  // FResetSeq: sequence number reset requested; FUpdating: dialog is being filled
    PC: TPageControl;  // tab control
    // Download Path
    cbDir, cbFile, cbJob: TComboBox;  // download folder, file name and job code boxes
    chkPromptJob: TCheckBox;  // prompt for the job code every time
    chkVerify, chkBackup, chkSafeDel: TCheckBox;  // verify copies, make a backup copy, safe deletion
    edTrash: TEdit;  // folder for the trash
    lblTrash: TLabel;  // label of the trash folder box
    edBackup: TEdit;  // backup folder box
    btnBackupBrowse: TButton;  // button that browses for the backup folder
    seqStart: TSpinEdit;  // first sequence number
    edExample: TEdit;  // example file name
    // General
    rbAuto, rbCamera, rbCard: TRadioButton;  // image source choices
    edLetters: TEdit;  // drive letters box
    chkPTP, chkReadOnly, chkPreserveRO, chkProfile, chkAutoRename, chkRenameDup, chkIgnoreDup, chkIgnoreSize, chkRotate, chkJpe, chkLrJpg, chkLrBoth,  // general options (first part)
    chkLowerName, chkLowerExt, chkStamp, chkSaveJobs, chkExifTxt, chkEject, chkWholeDisk, chkLrData,  // general options (second part)
    chkIptc, chkPromptIptc, chkIIM, chkNef, chkExifOwner, chkLoadLast, chkSingle, chkWinSafe: TCheckBox;  // general options (third part)
    lblLetters: TLabel;  // label of the drive letters box
    edAuthor, edCopyright: TEdit;  // author and copyright boxes
    // Automation
    chkAutoStart, chkAutoMenu, chkAutoPrompt, chkADownload, chkADelete, chkAEject,  // automation options (first part)
    chkALaunch, chkAExit: TCheckBox;  // automation options (second part)
    grpActions: TGroupBox;  // group of automatic actions
    // Custom button
    chkCustom: TCheckBox;  // custom button on or off
    edCaption, edCmd: TEdit;  // button caption and command boxes
    btnCmd: TButton;  // button that browses for the command
    // Mapping
    lbMaps: TListBox;  // list of camera mappings
    chkSerial, chkPromptCam: TCheckBox;  // mapping options
    edCurCam: TEdit;  // current camera box
    // Plug-ins
    lbPlugins: TListBox;  // list of plug-ins
    chkPlugin: TCheckBox;  // plug-in on or off
    lblPluginInfo: TLabel;  // plug-in information label
    imgPluginLogo: TImage;  // logo of a plug-in library
    procedure BuildPathTab(TS: TTabSheet);  // builds the Download Path tab
    procedure BuildGeneralTab(TS: TTabSheet);  // builds the General tab
    procedure BuildFileTab(TS: TTabSheet);  // builds the File Handling tab
    procedure DupChange(Sender: TObject);  // keeps the duplicate options exclusive
    procedure LrChange(Sender: TObject);  // enables "keep the .lrprev file as well" when .jpg is chosen
    procedure BuildAutomationTab(TS: TTabSheet);  // builds the Automation tab
    procedure BuildCustomTab(TS: TTabSheet);  // builds the Custom button tab
    procedure BuildMappingTab(TS: TTabSheet);  // builds the Mapping tab
    procedure BuildPluginTab(TS: TTabSheet);  // builds the Plug-ins tab
    procedure LoadValues;  // fills the controls from the settings
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);  // handles F1
    procedure ExampleChange(Sender: TObject);  // refreshes the example name
    procedure BrowseClick(Sender: TObject);  // asks for the download folder
    procedure BackupBrowseClick(Sender: TObject);  // asks for the backup folder
    procedure BackupChange(Sender: TObject);  // enables the backup controls
    procedure ResetClick(Sender: TObject);  // asks to reset the sequence number
    procedure TokensClick(Sender: TObject);  // shows the token list
    procedure LocateClick(Sender: TObject);  // locates the card reader
    procedure GeneralChange(Sender: TObject);  // updates controls after a General option changed
    procedure AutoChange(Sender: TObject);  // updates controls after an Automation option changed
    procedure SafeDelChange(Sender: TObject);  // updates controls after the safe deletion option changed
    procedure CustomChange(Sender: TObject);  // updates controls after the custom button option changed
    procedure CmdBrowseClick(Sender: TObject);  // asks for the command of the custom button
    procedure RefreshMaps(Sel: Integer);  // refreshes the mapping list
    procedure AddCamera(const CamName: string);  // adds a camera to the mappings
    procedure MapAddCameraClick(Sender: TObject);  // adds the current camera
    procedure MapAddClick(Sender: TObject);  // adds a new mapping
    procedure MapDeleteClick(Sender: TObject);  // deletes a mapping
    procedure MapEditClick(Sender: TObject);  // edits a mapping
    procedure RefreshPlugins(Sel: Integer);  // refreshes the plug-in list
    procedure PluginSelect(Sender: TObject);  // shows the information of the selected plug-in
    procedure PluginToggle(Sender: TObject);  // turns the selected plug-in on or off
    procedure PluginUpClick(Sender: TObject);  // moves the plug-in up
    procedure PluginDownClick(Sender: TObject);  // moves the plug-in down
    procedure PluginSetupClick(Sender: TObject);  // opens the setup of the plug-in
  public
    constructor CreatePrefs(AOwner: TComponent; AS_: TAppSettings; const ACamera: string);  // builds the dialog
    destructor Destroy; override;  // frees the lists
    procedure Store;  // stores the values in the settings
  end;

{$IFDEF UNIX}
const
  TabPad = 15;  // Linux: pixels GTK adds around each tab heading; lower it if the Preferences dialog is too wide, raise it if scroll arrows appear
{$ENDIF}

{ Builds the Preferences dialog with all its tabs. }
constructor TPrefsForm.CreatePrefs(AOwner: TComponent; AS_: TAppSettings; const ACamera: string);
var
  BtnOK, BtnCancel: TButton;  // BtnOK, BtnCancel: dialog buttons
  Extra: Integer;  // Extra: pixels the dialog is widened by (Linux: so that all tab headings fit on one row)
  {$IFDEF UNIX}
  Bmp: TBitmap;  // Bmp: bitmap whose canvas measures the heading texts
  NeedW, I: Integer;  // NeedW: width all headings need; I: loop counter
  {$ENDIF}
begin
  inherited CreateNew(AOwner);  // create the form without a resource file
  Extra := 0;  // no extra width yet
  FS := AS_;  // keep the settings
  FCamera := ACamera;  // keep the camera name
  FMaps := TStringList.Create;  // list of mappings
  FPlugins := TStringList.Create;  // list of plug-ins
  FPluginOpts := TStringList.Create;  // list of plug-in options
  InitDialog(Self, 'Preferences', 520, 722);  // set the common dialog properties
  KeyPreview := True;  // let the form see keys first
  OnKeyDown := @FormKeyDown;  // handle the F1 key
  PC := TPageControl.Create(Self);  // create the tab control
  PC.Parent := Self;  // place it on the form
  PC.SetBounds(8, 8, 504, 666);  // position and size it
  PC.MultiLine := True;  // wrap the tab headings when they do not fit on one row
  BuildPathTab(PC.AddTabSheet);  // build the first tab
  PC.Pages[0].Caption := 'Download Path';  // tab title
  BuildGeneralTab(PC.AddTabSheet);  // build the second tab
  PC.Pages[1].Caption := 'General';  // tab title
  BuildFileTab(PC.AddTabSheet);  // build the File Handling tab
  PC.Pages[2].Caption := 'File Handling';  // tab title
  BuildAutomationTab(PC.AddTabSheet);  // build the third tab
  PC.Pages[3].Caption := 'Automation';  // tab title
  BuildMappingTab(PC.AddTabSheet);  // build the fourth tab
  PC.Pages[4].Caption := 'Mapping';  // tab title
  BuildCustomTab(PC.AddTabSheet);  // build the fifth tab
  PC.Pages[5].Caption := 'Custom Button';  // tab title
  BuildPluginTab(PC.AddTabSheet);  // build the sixth tab
  PC.Pages[6].Caption := 'Plug-ins';  // tab title
  {$IFDEF UNIX}
  // GTK cannot wrap tab headings onto a second row (it shows scroll arrows instead), so the
  // dialog is widened until all headings fit on one row
  Bmp := TBitmap.Create;  // bitmap used only to measure text
  try
    Bmp.Canvas.Font.Assign(Font);  // the dialog font
    NeedW := 16;  // room for the edges
    for I := 0 to PC.PageCount - 1 do  // every tab
      Inc(NeedW, Bmp.Canvas.TextWidth(PC.Pages[I].Caption) + TabPad);  // heading text plus the padding GTK adds
  finally
    Bmp.Free;  // free the bitmap
  end;
  if NeedW > PC.Width then  // the headings do not fit yet
  begin
    Extra := Min(NeedW - PC.Width, Max(0, Screen.Width - 40 - ClientWidth));  // widen, but stay on the screen
    ClientWidth := ClientWidth + Extra;  // wider dialog
    PC.Width := PC.Width + Extra;  // wider tab control
  end;
  {$ENDIF}
  BtnOK := MkButton(Self, 'OK', 340 + Extra, 684, 80, mrOK);  // OK button
  BtnOK.Default := True;  // OK is the default button
  BtnCancel := MkButton(Self, 'Cancel', 430 + Extra, 684, 80, mrCancel);  // Cancel button
  BtnCancel.Cancel := True;  // Cancel reacts to Esc
  LoadValues;  // fill the controls from the settings
end;

{ Frees the lists owned by the dialog. }
destructor TPrefsForm.Destroy;
begin
  FMaps.Free;  // free the mappings
  FPlugins.Free;  // free the plug-in list
  FPluginOpts.Free;  // free the plug-in options
  inherited Destroy;  // run the inherited destructor
end;

{ Shows the token list when F1 is pressed. }
procedure TPrefsForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F1) and (Shift = []) then  // F1 without modifier keys
  begin
    ShowTokenHelp;  // show the token list
    Key := 0;  // key has been handled
  end;
end;

{ ---- Download Path ---- }

{ Builds the Download Path tab. }
procedure TPrefsForm.BuildPathTab(TS: TTabSheet);
const
  Col1 = '{d} - date'#13#10'{y} - 2-digit year'#13#10'{Y} - 4-digit year'#13#10 +  // token help, first column
         '{m} - month'#13#10'{b} - month (abbr.)'#13#10'{B} - full month'#13#10 +
         '{D} - day of month'#13#10'{a} - weekday';
  Col2 = '{A} - full weekday'#13#10'{W} - week'#13#10'{t} - time'#13#10'{H} - hour'#13#10 +  // token help, second column
         '{I} - hour (01-12)'#13#10'{M} - minutes'#13#10'{S} - seconds'#13#10'{q} - folder';
  Col3 = '{r} - image'#13#10'{o} - orig'#13#10'{f} - filename prefix'#13#10'{O} - owner'#13#10 +  // token help, third column
         '{i} - ISO'#13#10'{c} - camera serial'#13#10'{T} - camera'#13#10'{J} - Job code';
begin
  MkLabel(TS, 'Download directory:', 8, 6);  // label
  cbDir := MkCombo(TS, 8, 26, 436);  // download folder box
  cbDir.Items.Add(IncludeTrailingPathDelimiter(GetUserDir) + 'Pictures' + PathDelim +  // first suggested folder pattern
    'Photo Downloader' + PathDelim + '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim);
  cbDir.Items.Add(IncludeTrailingPathDelimiter(GetUserDir) + 'Pictures' + PathDelim +  // second suggested folder pattern
    '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim);
  cbDir.OnChange := @ExampleChange;  // update the example when the text changes
  MkButton(TS, '...', 452, 25, 28).OnClick := @BrowseClick;  // button that browses for the folder

  MkLabel(TS, 'Filename:', 8, 62);  // label
  cbFile := MkCombo(TS, 66, 58, 414);  // file name box
  cbFile.Items.Add('{o}');  // suggested pattern: original name
  cbFile.Items.Add('{Y}{m}{D}-{t}-{o}');  // suggested pattern: date, time and original name
  cbFile.Items.Add('RA{Y}{m}{D}-{r}');  // suggested pattern: prefix and number
  cbFile.OnChange := @ExampleChange;  // update the example when the text changes

  MkLabel(TS, 'Job code {J}:', 8, 94);  // label
  cbJob := MkCombo(TS, 90, 90, 390);  // job code box
  cbJob.Items.Add('{Job Name}');  // placeholder job code
  cbJob.OnChange := @ExampleChange;  // update the example when the text changes

  chkPromptJob := MkCheck(TS, 'Prompt for Job code every time Downloader is run', 8, 120);  // prompt for the job code check box
  MkLabel(TS, 'Sequence number starting', 8, 152);  // label
  seqStart := TSpinEdit.Create(TS);  // create the sequence number box
  seqStart.Parent := TS;  // place it on the tab
  seqStart.SetBounds(170, 148, 80, 23);  // position and size it
  seqStart.MinValue := 0;  // smallest value
  seqStart.MaxValue := 999999999;  // largest value
  MkButton(TS, 'Reset', 262, 147, 70).OnClick := @ResetClick;  // button that resets the sequence number

  MkLabel(TS, 'Directory and filename tokens (press F1 for a complete list):', 8, 184);  // label
  MkWrap(TS, Col1, 8, 204, 150, 150);  // token help, first column
  MkWrap(TS, Col2, 168, 204, 150, 150);  // token help, second column
  MkWrap(TS, Col3, 330, 204, 150, 150);  // token help, third column
  MkLabel(TS, '{seq#} - download sequence', 8, 358);  // token label
  MkLabel(TS, '{E} {e} {ea} - extension (upper, lower, as is)', 200, 358);  // token label
  MkLabel(TS, '{n4} - download sequence number (this session)', 8, 376);  // token label
  MkButton(TS, 'Show tokens...', 380, 380, 100).OnClick := @TokensClick;  // button that shows all tokens

  MkLabel(TS, 'Example image', 8, 416);  // label
  edExample := MkEdit(TS, 8, 436, 472);  // example box
  edExample.ReadOnly := True;  // user cannot edit the example

  chkVerify := MkCheck(TS, 'Verify every copy (read it back and compare checksums)', 8, 476);  // verify copies check box
  chkBackup := MkCheck(TS, 'Also save a second copy to a backup folder', 8, 504);  // backup copy check box
  chkBackup.OnClick := @BackupChange;  // enable the backup controls when changed
  MkLabel(TS, 'Backup directory (same patterns as above):', 26, 532);  // label
  edBackup := MkEdit(TS, 26, 552, 418);  // backup folder box
  btnBackupBrowse := MkButton(TS, '...', 452, 551, 28);  // button that browses for the backup folder
  btnBackupBrowse.OnClick := @BackupBrowseClick;  // connect its handler
  MkLabel(TS, 'The backup is made from the verified download, before rotation or metadata changes.', 26, 580);  // note about the backup
end;

{ Enables the backup folder controls only when the backup is turned on. }
procedure TPrefsForm.BackupChange(Sender: TObject);
begin
  edBackup.Enabled := chkBackup.Checked;  // enable the folder box
  btnBackupBrowse.Enabled := chkBackup.Checked;  // enable the browse button
end;

{ Lets the user choose the backup folder. }
procedure TPrefsForm.BackupBrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser
begin
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  try
    D.Title := 'Select backup directory';  // window title
    if D.Execute then  // when the user chose a folder
      edBackup.Text := IncludeTrailingPathDelimiter(D.FileName) +  // build the pattern from the chosen folder
        '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim;  // year and date subfolders
  finally
    D.Free;  // free the chooser
  end;
end;

{ Updates the example file name from the current boxes. }
procedure TPrefsForm.ExampleChange(Sender: TObject);
begin
  if FUpdating then Exit;  // ignore changes while the dialog is being filled
  edExample.Text := ExampleDest(FS, cbDir.Text, cbFile.Text, cbJob.Text);  // build the example name
end;

{ Lets the user choose the download folder. }
procedure TPrefsForm.BrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;  // D: folder chooser
begin
  D := TSelectDirectoryDialog.Create(Self);  // create the chooser
  try
    D.Title := 'Select download directory';  // window title
    if D.Execute then  // when the user chose a folder
      cbDir.Text := IncludeTrailingPathDelimiter(D.FileName) +  // build the pattern from the chosen folder
        '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim;  // year and date subfolders
  finally
    D.Free;  // free the chooser
  end;
end;

{ Remembers that the sequence number is to be reset and tells the user. }
procedure TPrefsForm.ResetClick(Sender: TObject);
begin
  FResetSeq := True;  // reset when OK is pressed
  ShowMessage('The sequence number will be reset to ' + IntToStr(seqStart.Value) +  // tell the user the new number
    ' when you press OK.');
end;

{ Shows the token list. }
procedure TPrefsForm.TokensClick(Sender: TObject);
begin
  ShowTokenHelp;  // show the token help
end;

{ ---- General ---- }

{ Builds the General tab. }
procedure TPrefsForm.BuildGeneralTab(TS: TTabSheet);
var
  G: TGroupBox;  // G: group box for the image source
  Y: Integer;  // Y: vertical position of the next control
begin
  G := TGroupBox.Create(TS);  // create the group box
  G.Parent := TS;  // place it on the tab
  G.Caption := 'Image source';  // group title
  G.SetBounds(6, 2, 482, 150);  // position and size it
  rbAuto := MkRadio(G, 'Auto-detect camera or card reader (used by Refresh and automation)', 10, 2);  // automatic detection choice
  rbCamera := MkRadio(G, 'Camera (connected by USB)', 10, 26);  // camera choice
  rbCard := MkRadio(G, 'Card reader or external storage device', 10, 50);  // card reader choice
  lblLetters := MkLabel(G, 'Drive letter or letters:', 34, 84);  // label of the drive letters box
  edLetters := MkEdit(G, 170, 80, 110);  // drive letters box
  {$IFNDEF WINDOWS}
  lblLetters.Visible := False;       // Linux has no drive letters: removable drives are found from the mount list
  edLetters.Visible := False;
  {$ENDIF}
  MkButton(G, 'Locate card reader', 300, 78, 150).OnClick := @LocateClick;  // button that locates the card reader
  chkPTP := MkCheck(G, 'Disable PTP downloads', 10, 108);  // PTP option

  Y := 156;  // start below the group box
  chkLoadLast := MkCheck(TS, 'Load the last used source folder at startup (otherwise nothing is scanned)', 8, Y);  // load last source option
  Inc(Y, 21);  // next row
  chkProfile := MkCheck(TS, 'Prompt for user profile at startup', 8, Y);  // profile prompt option
  Inc(Y, 21);  // next row
  chkSaveJobs := MkCheck(TS, 'Save date based job codes for next time Photo Downloader is run', 8, Y);  // date based job codes option
  Inc(Y, 21);  // next row
  chkEject := MkCheck(TS, 'Automatically ''eject'' card reader media when disconnecting', 8, Y);  // eject option
  Inc(Y, 21);  // next row
  chkWholeDisk := MkCheck(TS, 'Scan whole disk for known image types', 8, Y);  // whole disk option
  Inc(Y, 21);  // next row
  chkLrData := MkCheck(TS, 'Scan Lightroom preview folders (.lrdata) for .lrprev files', 8, Y);  // Lightroom folders option
  Inc(Y, 21);  // next row
  chkIptc := MkCheck(TS, 'Add IPTC/XMP data to downloaded images', 8, Y);  // IPTC option
  Inc(Y, 21);  // next row
  chkPromptIptc := MkCheck(TS, 'Prompt for IPTC/XMP data every time Photo Downloader is run', 28, Y);  // prompt for IPTC option
  Inc(Y, 21);  // next row
  chkIIM := MkCheck(TS, 'Also write legacy IPTC IIM data to downloaded images', 28, Y);  // legacy IIM option
  Inc(Y, 21);  // next row
  chkNef := MkCheck(TS, 'Enable writing of legacy IPTC IIM data to Nikon NEF raw files', 28, Y);  // NEF option
  Inc(Y, 28);  // next row with a gap
  chkExifOwner := MkCheck(TS, 'Add author and copyright to EXIF of downloaded JPEGs (only where empty)', 8, Y);  // EXIF owner option
  Inc(Y, 26);  // next row
  MkLabel(TS, 'Author:', 28, Y + 3);  // label
  edAuthor := MkEdit(TS, 100, Y, 380);  // author box
  Inc(Y, 28);  // next row
  MkLabel(TS, 'Copyright:', 28, Y + 3);  // label
  edCopyright := MkEdit(TS, 100, Y, 380);  // copyright box
  Inc(Y, 32);  // next row
  chkSingle := MkCheck(TS, 'Run only one copy of Photo Downloader at a time (applies at next start)', 8, Y);  // single instance option (Windows only)
  {$IFNDEF WINDOWS}
  chkSingle.Visible := False;        // single instance is not available on Linux yet
  {$ENDIF}

  chkIptc.OnClick := @GeneralChange;  // update the controls when the option changes
  chkExifOwner.OnClick := @GeneralChange;  // update the controls when the option changes
  rbAuto.OnClick := @GeneralChange;  // update the controls when the choice changes
  rbCamera.OnClick := @GeneralChange;  // update the controls when the choice changes
  rbCard.OnClick := @GeneralChange;  // update the controls when the choice changes
end;

{ Builds the File Handling tab (how downloaded files are named, copied and treated). }
procedure TPrefsForm.BuildFileTab(TS: TTabSheet);
var
  Y: Integer;  // Y: vertical position of the next control

  { Creates a check box in the single column and moves Y to the next row. }
  function Row(const Cap: string): TCheckBox;
  begin
    Result := MkCheck(TS, Cap, 8, Y);  // check box in the column
    Result.Width := 470;  // full width of the tab
    Inc(Y, 24);  // next row
  end;

begin
  Y := 10;  // first row
  chkReadOnly := Row('Save files as read-only');  // read-only option
  chkPreserveRO := Row('Preserve read-only status');  // preserve read-only option
  chkAutoRename := Row('Rename name clashes as (1), (2) ...');  // rename name clashes option
  chkIgnoreDup := Row('Ignore duplicate files on download');  // skip duplicates option
  chkRenameDup := Row('Download duplicates as (1), (2) ...');  // download duplicates renamed option
  chkIgnoreSize := Row('Ignore file size check to allow for images modified after downloading');  // ignore size option
  chkRotate := Row('Auto-rotate JPEGs after downloading (lossless rotation)');  // auto-rotate option
  chkJpe := Row('Rename files with .jpe extension to .jpg when downloading');  // rename .jpe option
  chkLrJpg := Row('Save Lightroom previews (.lrprev) as .jpg when downloading');  // .lrprev as .jpg option
  chkLrBoth := Row('Save both: keep the .lrprev file as well as the .jpg');  // keep both option
  chkLrBoth.Left := 28;  // indented: belongs to the option above
  chkLrBoth.Width := 450;  // rest of the tab width
  chkLrJpg.OnClick := @LrChange;  // the second option needs the first
  chkLowerName := Row('Convert filename to lower case');  // lower case name option
  chkLowerExt := Row('Lower case file extensions');  // lower case extension option
  chkStamp := Row('Use image capture time for file timestamp');  // capture time option
  chkExifTxt := Row('Generate text file containing EXIF shooting data');  // EXIF text file option
  chkWinSafe := Row('Windows-safe file names (replace characters such as : ? * " < > |)');  // Windows-safe names option (Linux only)
  {$IFDEF WINDOWS}
  chkWinSafe.Visible := False;       // Windows always applies these rules
  {$ENDIF}
  chkIgnoreDup.OnClick := @DupChange;  // keep the two duplicate options exclusive
  chkRenameDup.OnClick := @DupChange;  // keep the two duplicate options exclusive
end;

{ Enables "Save both" only while "Save Lightroom previews as .jpg" is checked. }
procedure TPrefsForm.LrChange(Sender: TObject);
begin
  chkLrBoth.Enabled := chkLrJpg.Checked;  // keeping both only makes sense when a .jpg is made
end;

{ Keeps "Ignore duplicate files" and "Download duplicates as (1), (2)" from being checked together. }
procedure TPrefsForm.DupChange(Sender: TObject);
begin
  if Sender = chkIgnoreDup then  // the ignore option was clicked
  begin
    if chkIgnoreDup.Checked then chkRenameDup.Checked := False;  // ignoring excludes renaming
  end
  else if Sender = chkRenameDup then  // the rename option was clicked
  begin
    if chkRenameDup.Checked then chkIgnoreDup.Checked := False;  // renaming excludes ignoring
  end;
end;

{ Enables the controls that depend on other General options. }
procedure TPrefsForm.GeneralChange(Sender: TObject);
begin
  chkPromptIptc.Enabled := chkIptc.Checked;  // prompt option needs IPTC
  chkIIM.Enabled := chkIptc.Checked;  // IIM option needs IPTC
  chkNef.Enabled := chkIptc.Checked;  // NEF option needs IPTC
  edAuthor.Enabled := chkExifOwner.Checked;  // author box needs the EXIF owner option
  edCopyright.Enabled := chkExifOwner.Checked;  // copyright box needs the EXIF owner option
  edLetters.Enabled := rbCard.Checked;  // drive letters need the card reader choice
end;

{ Finds removable drives and shows them (Windows: fills the drive letters box). }
procedure TPrefsForm.LocateClick(Sender: TObject);
var
  L: TStringList;  // L: removable drives found
  I: Integer;  // I: loop counter
  Letters: string;  // Letters: drive letters or the list text
begin
  L := TStringList.Create;  // create the list
  try
    ListRemovableDrives(L);  // find the removable drives
    if L.Count = 0 then  // none found
      ShowMessage('No card reader or removable drive was found.')  // tell the user
    else
    begin
      {$IFDEF WINDOWS}
      Letters := '';  // start with no letters
      for I := 0 to L.Count - 1 do  // every drive
        Letters := Letters + Copy(L[I], 1, 1);  // take the drive letter
      edLetters.Text := Letters;  // show the letters
      {$ELSE}
      // Linux has no drive letters: list the mounted removable drives that were found
      Letters := '';  // start with no text
      for I := 0 to L.Count - 1 do  // every drive
        Letters := Letters + #13#10 + L[I];  // add one drive per line
      ShowMessage('Removable drives found:' + Letters);  // show the drives
      {$ENDIF}
      rbCard.Checked := True;  // switch to the card reader choice
    end;
  finally
    L.Free;  // free the list
  end;
end;

{ ---- Automation ---- }

{ Builds the Automation tab. }
procedure TPrefsForm.BuildAutomationTab(TS: TTabSheet);
begin
  MkWrap(TS, 'Use the settings below to enable automatic downloading of images when ' +  // explanation text
    'Downloader is run. Select "Prompt before starting auto sequence" if you want to be ' +
    'able to choose whether automation should run.'#13#10 +
    'The automation sequence will stop if there are any errors or an operation is canceled.',
    8, 8, 480, 90);  // position and size
  chkAutoStart := MkCheck(TS, 'Enable Automation at startup', 66, 104);  // startup option
  chkAutoMenu := MkCheck(TS, 'Enable Automation menu option and keyboard shortcut', 66, 128);  // menu option
  chkAutoPrompt := MkCheck(TS, 'Prompt before starting auto sequence', 66, 152);  // prompt option
  grpActions := TGroupBox.Create(TS);  // create the group box
  grpActions.Parent := TS;  // place it on the tab
  grpActions.Caption := 'Actions';  // group title
  grpActions.SetBounds(44, 186, 420, 180);  // position and size it
  chkADownload := MkCheck(grpActions, 'Download files when application is started', 28, 6);  // download action
  chkADelete := MkCheck(grpActions, 'Delete files from CF card after downloading', 28, 32);  // delete action
  chkAEject := MkCheck(grpActions, '''Soft eject'' card reader media', 28, 58);  // eject action
  chkALaunch := MkCheck(grpActions, 'Launch app associated with custom button', 28, 84);  // launch action
  chkAExit := MkCheck(grpActions, 'Exit Downloader', 28, 110);  // exit action
  chkSafeDel := MkCheck(TS, 'Safe delete (Recycle Bin, or a hidden trash folder on cards)', 44, 376);  // safe delete option
  chkSafeDel.Width := 420;  // make room for the long text
  chkSafeDel.OnClick := @SafeDelChange;  // update the controls when the option changes
  lblTrash := MkLabel(TS, 'Trash folder name on cards:', 64, 404);  // label
  edTrash := MkEdit(TS, 220, 400, 180);  // trash folder name box
  chkAutoStart.OnClick := @AutoChange;  // update the controls when the option changes
  chkAutoMenu.OnClick := @AutoChange;  // update the controls when the option changes
end;

{ Enables the trash folder controls only when safe delete is on. }
procedure TPrefsForm.SafeDelChange(Sender: TObject);
begin
  edTrash.Enabled := chkSafeDel.Checked;  // enable the folder name box
  lblTrash.Enabled := chkSafeDel.Checked;  // enable its label
end;

{ Enables the automation controls that depend on other options. }
procedure TPrefsForm.AutoChange(Sender: TObject);
begin
  chkAutoPrompt.Enabled := chkAutoMenu.Checked;  // prompt needs the menu option
  grpActions.Enabled := chkAutoStart.Checked or chkAutoMenu.Checked;  // actions need startup or menu automation
  chkADownload.Enabled := grpActions.Enabled;  // enable the download action
  chkADelete.Enabled := grpActions.Enabled;  // enable the delete action
  chkAEject.Enabled := grpActions.Enabled;  // enable the eject action
  chkALaunch.Enabled := grpActions.Enabled;  // enable the launch action
  chkAExit.Enabled := grpActions.Enabled;  // enable the exit action
end;

{ ---- Custom button ---- }

{ Builds the Custom button tab. }
procedure TPrefsForm.BuildCustomTab(TS: TTabSheet);
var
  G: TGroupBox;  // G: group box for the custom button
begin
  G := TGroupBox.Create(TS);  // create the group box
  G.Parent := TS;  // place it on the tab
  G.Caption := 'Custom button';  // group title
  G.SetBounds(16, 24, 458, 160);  // position and size it
  chkCustom := MkCheck(G, 'Enable custom button', 10, 6);  // enable option
  MkLabel(G, 'Button caption:', 10, 40);  // label
  edCaption := MkEdit(G, 110, 36, 150);  // caption box
  MkLabel(G, 'Command line (use %f for file and %d for directory):', 10, 68);  // label
  edCmd := MkEdit(G, 10, 88, 392);  // command line box
  btnCmd := MkButton(G, '...', 410, 87, 28);  // button that browses for the command
  btnCmd.OnClick := @CmdBrowseClick;  // connect its handler
  MkWrap(TS, 'Select "Enable custom button" to add a custom button to Downloader. The ' +  // explanation text
    'custom button can be used to launch the application of your choice. Pressing the ' +
    'custom button after downloading your files will run the command line, with %f replaced ' +
    'by the last downloaded file and %d by the folder containing the downloaded files.',
    8, 204, 480, 120);  // position and size
  chkCustom.OnClick := @CustomChange;  // update the controls when the option changes
end;

{ Enables the custom button controls only when the button is on. }
procedure TPrefsForm.CustomChange(Sender: TObject);
begin
  edCaption.Enabled := chkCustom.Checked;  // enable the caption box
  edCmd.Enabled := chkCustom.Checked;  // enable the command box
  btnCmd.Enabled := chkCustom.Checked;  // enable the browse button
end;

{ Lets the user choose the program for the custom button. }
procedure TPrefsForm.CmdBrowseClick(Sender: TObject);
var
  D: TOpenDialog;  // D: file chooser
begin
  D := TOpenDialog.Create(Self);  // create the chooser
  try
    if D.Execute then edCmd.Text := '"' + D.FileName + '" "%f"';  // build the command line from the chosen program
  finally
    D.Free;  // free the chooser
  end;
end;

{ ---- Mapping ---- }

{ Builds the Mapping tab. }
procedure TPrefsForm.BuildMappingTab(TS: TTabSheet);
begin
  MkLabel(TS, 'Current camera model mappings for the {T8} and {T9} tokens:', 8, 6);  // label
  lbMaps := TListBox.Create(TS);  // create the list
  lbMaps.Parent := TS;  // place it on the tab
  lbMaps.SetBounds(8, 26, 478, 250);  // position and size it
  MkWrap(TS, 'Add camera models by clicking on the "Add camera..." button.', 8, 288, 340, 34);  // hint text
  MkButton(TS, 'Add camera...', 366, 286, 120).OnClick := @MapAddCameraClick;  // button that adds a camera from a picture
  chkSerial := MkCheck(TS, 'Identify camera using serial number, owner string or user comment', 8, 326);  // serial number option
  MkLabel(TS, 'Current camera:', 8, 358);  // label
  edCurCam := MkEdit(TS, 100, 354, 290);  // current camera box
  edCurCam.ReadOnly := False;  // user may edit the name
  MkButton(TS, 'Add', 400, 353, 86).OnClick := @MapAddClick;  // button that adds the current camera
  chkPromptCam := MkCheck(TS, 'Prompt for camera mappings when a new camera is detected', 8, 386);  // prompt option
  MkWrap(TS, 'Remove entries from the list by selecting them and pressing the "Delete" button.',  // hint text
    8, 418, 340, 34);
  MkButton(TS, 'Delete', 366, 416, 120).OnClick := @MapDeleteClick;  // button that deletes a mapping
  MkWrap(TS, 'Click on the "Edit..." button to edit the value of the {T8} and {T9} tokens for ' +  // hint text
    'the selected camera.', 8, 458, 340, 34);
  MkButton(TS, 'Edit...', 366, 456, 120).OnClick := @MapEditClick;  // button that edits a mapping
end;

{ Fills the mapping list from the stored mappings and selects entry Sel. }
procedure TPrefsForm.RefreshMaps(Sel: Integer);
var
  I: Integer;  // I: loop counter
  N, A, B: string;  // N: camera name; A, B: values of the two tokens
begin
  lbMaps.Items.BeginUpdate;  // stop redrawing while filling
  try
    lbMaps.Items.Clear;  // clear the list
    for I := 0 to FMaps.Count - 1 do  // every mapping
    begin
      MapSplit(FMaps[I], N, A, B);  // split the entry
      if I = 0 then N := 'Default mapping';  // first entry is the default
      lbMaps.Items.Add(N + ' -> {T8}=' + A + ' | {T9}=' + B);  // add the line to the list
    end;
  finally
    lbMaps.Items.EndUpdate;  // redraw the list
  end;
  if (Sel >= 0) and (Sel < lbMaps.Items.Count) then lbMaps.ItemIndex := Sel;  // select the entry
end;

{ Adds a camera model to the mappings unless it is there already. }
procedure TPrefsForm.AddCamera(const CamName: string);
var
  I: Integer;  // I: loop counter
  N, A, B: string;  // N: camera name; A, B: values of the two tokens
begin
  if Trim(CamName) = '' then Exit;  // ignore empty names
  for I := 1 to FMaps.Count - 1 do  // check the existing cameras
  begin
    MapSplit(FMaps[I], N, A, B);  // split the entry
    if SameText(N, CamName) then  // already known
    begin
      RefreshMaps(I);  // just select it
      Exit;
    end;
  end;
  FMaps.Add(MapJoin(Trim(CamName), '{T1}', '{T1}'));  // add the camera with the default tokens
  RefreshMaps(FMaps.Count - 1);  // select the new entry
end;

{ Reads the camera model from a chosen picture and adds it. }
procedure TPrefsForm.MapAddCameraClick(Sender: TObject);
var
  D: TOpenDialog;  // D: file chooser
  Info: TExifInfo;  // Info: EXIF data of the picture
begin
  D := TOpenDialog.Create(Self);  // create the chooser
  try
    D.Title := 'Select an image from the camera';  // window title
    D.Filter := 'Images|*.jpg;*.jpeg;*.nef;*.cr2;*.dng;*.arw;*.tif;*.tiff|All files|*.*';  // file types shown
    if D.Execute then
    begin
      if ReadExifFromFile(D.FileName, Info) and (Info.Model <> '') then  // read the camera model
        AddCamera(Info.Model)  // add the camera
      else
        ShowMessage('No camera model could be read from that file.');  // tell the user
    end;
  finally
    D.Free;  // free the chooser
  end;
end;

{ Adds the camera named in the current camera box. }
procedure TPrefsForm.MapAddClick(Sender: TObject);
begin
  AddCamera(edCurCam.Text);  // add the camera
end;

{ Deletes the selected mapping (the default mapping cannot be deleted). }
procedure TPrefsForm.MapDeleteClick(Sender: TObject);
var
  I: Integer;  // I: selected entry
begin
  I := lbMaps.ItemIndex;  // selected entry
  if I <= 0 then  // nothing selected or the default entry
  begin
    if I = 0 then ShowMessage('The default mapping cannot be deleted.');  // explain why the default stays
    Exit;
  end;
  FMaps.Delete(I);  // remove the entry
  RefreshMaps(Min(I, FMaps.Count - 1));  // select a neighbor
end;

{ Edits the token values of the selected mapping. }
procedure TPrefsForm.MapEditClick(Sender: TObject);
var
  I: Integer;  // I: selected entry
  N, A, B: string;  // N: camera name; A, B: values of the two tokens
begin
  I := lbMaps.ItemIndex;  // selected entry
  if I < 0 then Exit;  // nothing selected
  MapSplit(FMaps[I], N, A, B);  // split the entry
  if I = 0 then N := 'Default';  // show the default entry under its own name
  if EditMapping(N, A, B) then  // let the user edit the tokens
  begin
    FMaps[I] := MapJoin(N, A, B);  // store the new values
    RefreshMaps(I);  // redraw the list
  end;
end;

{ ---- Plug-ins ---- }

{ Builds the Plug-ins tab. }
procedure TPrefsForm.BuildPluginTab(TS: TTabSheet);
begin
  lbPlugins := TListBox.Create(TS);  // create the list
  lbPlugins.Parent := TS;  // place it on the tab
  lbPlugins.SetBounds(8, 8, 380, 200);  // position and size it
  lbPlugins.OnClick := @PluginSelect;  // show the information when an entry is selected
  MkButton(TS, 'Up', 404, 8, 80).OnClick := @PluginUpClick;  // move up button
  MkButton(TS, 'Down', 404, 40, 80).OnClick := @PluginDownClick;  // move down button
  chkPlugin := MkCheck(TS, 'Enable plug-in', 8, 220);  // enable option
  chkPlugin.Width := 130;  // make room for the setup button
  chkPlugin.OnClick := @PluginToggle;  // toggle the plug-in when changed
  MkButton(TS, 'Setup...', 150, 218, 100).OnClick := @PluginSetupClick;  // setup button
  lblPluginInfo := MkWrap(TS, '', 8, 258, 478, 96);  // information label
  imgPluginLogo := TImage.Create(TS);  // logo of a plug-in library
  imgPluginLogo.Parent := TS;  // place it on the tab
  imgPluginLogo.SetBounds(8, 362, 300, 80);  // below the information
end;

{ Fills the plug-in list and selects entry Sel. }
procedure TPrefsForm.RefreshPlugins(Sel: Integer);
var
  I: Integer;  // I: loop counter
begin
  lbPlugins.Items.Clear;  // clear the list
  for I := 0 to FPlugins.Count - 1 do  // every plug-in
    if FindLibPlugin(FPlugins.Names[I]) <> nil then  // a plug-in library: show its own name
    begin
      if FPlugins.ValueFromIndex[I] = '1' then
        lbPlugins.Items.Add(FindLibPlugin(FPlugins.Names[I]).DisplayName + ' - enabled')  // add the name with its state
      else
        lbPlugins.Items.Add(FindLibPlugin(FPlugins.Names[I]).DisplayName + ' - disabled');  // add the name with its state
    end
    else if FindExtPlugin(FPlugins.Names[I]) <> nil then  // an external-program plug-in: show its own name
    begin
      if FPlugins.ValueFromIndex[I] = '1' then
        lbPlugins.Items.Add(FindExtPlugin(FPlugins.Names[I]).Name + ' (program) - enabled')  // add the name with its state
      else
        lbPlugins.Items.Add(FindExtPlugin(FPlugins.Names[I]).Name + ' (program) - disabled');  // add the name with its state
    end
    else if FPlugins.ValueFromIndex[I] = '1' then  // enabled plug-in
      lbPlugins.Items.Add(FPlugins.Names[I] + ' - enabled')  // add the name with its state
    else
      lbPlugins.Items.Add(FPlugins.Names[I] + ' - disabled');  // add the name with its state
  if (Sel >= 0) and (Sel < lbPlugins.Items.Count) then lbPlugins.ItemIndex := Sel;  // select the entry
  PluginSelect(nil);  // show its information
end;

{ Shows the information of the selected plug-in. }
procedure TPrefsForm.PluginSelect(Sender: TObject);
var
  I: Integer;  // I: selected entry
  Nm, Info: string;  // Nm: plug-in name; Info: information text
  P: TLibPlugin;  // P: the plug-in library (nil for a built-in plug-in)
  X: TExtPlugin;  // X: the external-program plug-in (nil for others)
  Png: TPortableNetworkGraphic;  // Png: logo of the library
  Prog: string;  // Prog: program of an external-program plug-in
begin
  I := lbPlugins.ItemIndex;  // selected entry
  FUpdating := True;  // do not react to the check box change
  try
    imgPluginLogo.Picture.Clear;  // no logo yet
    if I < 0 then
    begin
      chkPlugin.Checked := False;  // no entry selected
      lblPluginInfo.Caption := '';  // clear the information
      Exit;
    end;
    Nm := FPlugins.Names[I];  // plug-in name
    chkPlugin.Checked := FPlugins.ValueFromIndex[I] = '1';  // enabled state
    P := FindLibPlugin(Nm);  // plug-in library with this key
    if P <> nil then  // a plug-in library
    begin
      Info := P.Description;  // its own description
      if P.Loaded and (P.Logo <> nil) and chkPlugin.Checked then  // the logo is shown when the plug-in is on
      begin
        Png := TPortableNetworkGraphic.Create;  // create the picture
        try
          P.Logo.Position := 0;  // read from the start
          Png.LoadFromStream(P.Logo);  // load the PNG
          imgPluginLogo.Picture.Assign(Png);  // show it at its own size
        except
          imgPluginLogo.Picture.Clear;  // a broken logo is left out
        end;
        Png.Free;  // free the picture
      end;
    end
    else if FindExtPlugin(Nm) <> nil then  // an external-program plug-in
    begin
      X := FindExtPlugin(Nm);  // the plug-in
      Prog := X.ProgramPath(PluginValues(FPluginOpts, Nm));  // its program
      if Prog = '' then Prog := X.ProgramSetting(PluginValues(FPluginOpts, Nm)) + '  (NOT FOUND: install it, or choose it with Setup...)';  // missing
      Info := X.Description + #13#10 + 'Program: ' + Prog + #13#10 +
        'Runs on: ' + StringReplace(Trim(StringReplace(X.FileTypes, ';', ' ', [rfReplaceAll])), ' ', ', ', [rfReplaceAll]) +
        '. File: ' + X.FileName;  // what it does and with what
      if X.FileTypes = '' then Info := StringReplace(Info, 'Runs on: .', 'Runs on: every file.', []);  // no type list
      if not X.Available then Info := 'Not available on this system.'#13#10 + Info;  // for example a Windows-only program
    end
    else if Nm = 'JPEG auto profile' then  // text for each known plug-in
      Info := 'Embeds an ICC color profile into each downloaded JPEG, without recompressing it.'#13#10 +
              'Choose one profile per camera model and a default with Setup...; JPEGs that already' +
              ' carry a profile are left alone unless "Replace" is ticked.'
    else if Nm = 'Directory Maker' then
      Info := 'Creates extra sub-folders (for example Edit and Web) next to the download folder.'
    else if Nm = 'JPEG resolution' then
      Info := 'Resizes JPEGs while downloading.'#13#10 + '(Not yet implemented in this build.)'
    else
      Info := 'Plug-in library "' + Nm + '": its file was not found in the plugins folder.';  // not installed (any more)
    lblPluginInfo.Caption := Info;  // show the information
  finally
    FUpdating := False;  // react to changes again
  end;
end;

{ Turns the selected plug-in on or off; a plug-in library is loaded (after a confirmation) when switched on. }
procedure TPrefsForm.PluginToggle(Sender: TObject);
var
  I: Integer;  // I: selected entry
  P: TLibPlugin;  // P: the plug-in library (nil for a built-in plug-in)
  X: TExtPlugin;  // X: the external-program plug-in (nil for others)
  Err, Prog: string;  // Err: why a library cannot be loaded; Prog: program of an external-program plug-in
begin
  if FUpdating then Exit;  // ignore changes made by the program
  I := lbPlugins.ItemIndex;  // selected entry
  if I < 0 then Exit;  // nothing selected
  X := FindExtPlugin(FPlugins.Names[I]);  // external-program plug-in (nil for others)
  if chkPlugin.Checked and (X <> nil) and (FPlugins.ValueFromIndex[I] <> '1') then  // a program plug-in is switched on
  begin
    Prog := X.ProgramPath(PluginValues(FPluginOpts, X.Key));  // its program
    if not X.Available then
      Err := 'This plug-in is not available on this system.'
    else if Prog = '' then
      Err := 'The program was not found:'#13#10 + X.ProgramSetting(PluginValues(FPluginOpts, X.Key)) + #13#10#13#10 +
        'Install it, or choose where it is with Setup...'
    else
      Err := '';  // ready
    if Err <> '' then
    begin
      MessageDlg('Plug-in', Err, mtError, [mbOK], 0);  // tell why
      RefreshPlugins(I);  // put the check box back
      Exit;
    end;
    // a program runs with the user's rights: start it only after the user agreed
    if MessageDlg('Plug-in', 'Switching this plug-in on runs this program after each matching download:'#13#10#13#10 +
      Prog + #13#10 + X.Args + #13#10#13#10 + 'Only switch it on when you trust the program.',
      mtConfirmation, [mbOK, mbCancel], 0) <> mrOK then
    begin
      RefreshPlugins(I);  // put the check box back
      Exit;
    end;
  end;
  P := FindLibPlugin(FPlugins.Names[I]);  // plug-in library (nil for a built-in plug-in)
  if chkPlugin.Checked and (P <> nil) and (FPlugins.ValueFromIndex[I] <> '1') then  // a library is switched on
  begin
    // a library runs with the user's rights: load it only after the user agreed
    if MessageDlg('Plug-in library',
      'Switching this plug-in on loads and runs the program library'#13#10#13#10 + P.FileName + #13#10#13#10 +
      'Only switch it on when you trust where it came from.', mtConfirmation, [mbOK, mbCancel], 0) <> mrOK then
    begin
      RefreshPlugins(I);  // put the check box back
      Exit;
    end;
    if not P.Load(Err) then  // it cannot be used
    begin
      MessageDlg('Plug-in library', 'The plug-in cannot be used: ' + Err + '.'#13#10 + P.FileName, mtError, [mbOK], 0);
      RefreshPlugins(I);  // put the check box back
      Exit;
    end;
  end;
  if chkPlugin.Checked then  // check box is on
    FPlugins[I] := FPlugins.Names[I] + '=1'  // store enabled
  else
    FPlugins[I] := FPlugins.Names[I] + '=0';  // store disabled
  RefreshPlugins(I);  // redraw the list
end;

{ Moves the selected plug-in one place up. }
procedure TPrefsForm.PluginUpClick(Sender: TObject);
var
  I: Integer;  // I: selected entry
begin
  I := lbPlugins.ItemIndex;  // selected entry
  if I > 0 then  // not already first
  begin
    FPlugins.Exchange(I, I - 1);  // swap with the previous entry
    RefreshPlugins(I - 1);  // redraw the list
  end;
end;

{ Moves the selected plug-in one place down. }
procedure TPrefsForm.PluginDownClick(Sender: TObject);
var
  I: Integer;  // I: selected entry
begin
  I := lbPlugins.ItemIndex;  // selected entry
  if (I >= 0) and (I < FPlugins.Count - 1) then  // not already last
  begin
    FPlugins.Exchange(I, I + 1);  // swap with the next entry
    RefreshPlugins(I + 1);  // redraw the list
  end;
end;

{ Opens the setup of the selected plug-in. }
procedure TPrefsForm.PluginSetupClick(Sender: TObject);
var
  I: Integer;  // I: selected entry
  Nm, V, D: string;  // Nm: plug-in name; V: option value; D: download folder template
  P: TLibPlugin;  // P: the plug-in library (nil for a built-in plug-in)
  X: TExtPlugin;  // X: the external-program plug-in (nil for others)
  OD: TOpenDialog;  // OD: chooser for the program
begin
  I := lbPlugins.ItemIndex;  // selected entry
  if I < 0 then Exit;  // nothing selected
  Nm := FPlugins.Names[I];  // plug-in name
  X := FindExtPlugin(Nm);  // external-program plug-in with this key
  if X <> nil then  // choose the program it runs
  begin
    OD := TOpenDialog.Create(Self);  // create the chooser
    try
      OD.Title := 'Program for ' + X.Name;  // window title
      {$IFDEF WINDOWS}
      OD.Filter := 'Programs (*.exe)|*.exe|All files|*.*';  // programs
      {$ENDIF}
      V := X.ProgramPath(PluginValues(FPluginOpts, Nm));  // the program now
      if V <> '' then OD.InitialDir := ExtractFilePath(V);  // start where it is
      if OD.Execute then  // a program was chosen
        SetPluginValues(FPluginOpts, Nm, 'Program=' + OD.FileName);  // store it
    finally
      OD.Free;  // free the chooser
    end;
    PluginSelect(nil);  // show the new program
    Exit;
  end;
  if Nm = 'JPEG auto profile' then  // one profile per camera
  begin
    V := PluginValues(FPluginOpts, Nm);  // stored choices
    if ExecuteJpegProfileSetup(V, FCamera) then SetPluginValues(FPluginOpts, Nm, V);  // ask and store
    Exit;
  end;
  P := FindLibPlugin(Nm);  // plug-in library with this key
  if P <> nil then  // a plug-in library: its prompt window
  begin
    if not P.Loaded then
      ShowMessage('Switch the plug-in on first; it is loaded then.')  // fields are known only after loading
    else if Length(P.Fields) = 0 then
      ShowMessage('The "' + P.DisplayName + '" plug-in has no options.')  // nothing to set
    else
    begin
      V := PluginValues(FPluginOpts, Nm);  // stored values
      D := cbDir.Text;  // download folder template on the Download Path tab
      if ExecutePluginPrompt(P, V, D) then  // ask
      begin
        SetPluginValues(FPluginOpts, Nm, V);  // store the values
        cbDir.Text := D;  // a new destination goes to the Download Path tab (and its example)
      end;
    end;
  end
  else if Nm = 'Directory Maker' then
  begin
    V := FPluginOpts.Values['Directory Maker'];  // current option value
    if InputQuery('Directory Maker', 'Folders to create (comma separated):', V) then  // ask for the folders
      FPluginOpts.Values['Directory Maker'] := V;  // store the new value
  end
  else
    ShowMessage('The "' + Nm + '" plug-in has no options in this build.');  // plug-in without options
end;

{ ---- load / store ---- }

{ Fills the dialog controls from the settings. }
procedure TPrefsForm.LoadValues;
begin
  FUpdating := True;  // do not react to changes while filling
  try
    cbDir.Text := FS.DownloadDir;  // download folder
    cbFile.Text := FS.FileNameMask;  // file name pattern
    cbJob.Text := FS.JobCode;  // job code
    chkPromptJob.Checked := FS.PromptJobCode;  // prompt for the job code
    chkVerify.Checked := FS.VerifyCopy;  // verify copies
    chkBackup.Checked := FS.BackupOn;  // backup on or off
    edBackup.Text := FS.BackupDir;  // backup folder
    BackupChange(nil);  // enable or disable the backup controls
    seqStart.Value := FS.SeqStart;  // first sequence number

    rbAuto.Checked := FS.SourceMode = smAuto;  // automatic source
    rbCamera.Checked := FS.SourceMode = smCamera;  // camera source
    rbCard.Checked := FS.SourceMode = smCardReader;  // card reader source
    edLetters.Text := FS.DriveLetters;  // drive letters
    chkPTP.Checked := FS.DisablePTP;  // disable PTP
    chkReadOnly.Checked := FS.SaveReadOnly;  // save files as read-only
    chkPreserveRO.Checked := FS.PreserveReadOnly;  // preserve read-only status
    chkProfile.Checked := FS.PromptProfile;  // prompt for the profile
    chkIgnoreSize.Checked := FS.IgnoreSizeCheck;  // ignore the size check
    chkAutoRename.Checked := FS.AutoRenameClash;  // rename name clashes automatically
    chkIgnoreDup.Checked := FS.IgnoreDuplicates;  // skip duplicate files
    chkRenameDup.Checked := FS.RenameDuplicates;  // download duplicates renamed
    chkRotate.Checked := FS.AutoRotate;  // auto-rotate JPEGs
    chkJpe.Checked := FS.RenameJpe;  // rename .jpe files
    chkLrJpg.Checked := FS.LrPrevAsJpg;  // .lrprev files as .jpg
    chkLrBoth.Checked := FS.LrPrevKeepBoth;  // keep the .lrprev file as well
    LrChange(nil);  // enable the second option to match
    chkLowerName.Checked := FS.LowerName;  // lower case names
    chkLowerExt.Checked := FS.LowerExt;  // lower case extensions
    chkStamp.Checked := FS.UseCaptureTime;  // use the capture time
    chkSaveJobs.Checked := FS.SaveDateJobCodes;  // save date based job codes
    chkExifTxt.Checked := FS.WriteExifText;  // write the EXIF text file
    chkEject.Checked := FS.AutoEject;  // eject automatically
    chkWholeDisk.Checked := FS.ScanWholeDisk;  // scan the whole disk
    chkLrData.Checked := FS.ScanLrData;  // scan Lightroom preview folders
    chkIptc.Checked := FS.AddIptc;  // add IPTC data
    chkPromptIptc.Checked := FS.PromptIptc;  // prompt for IPTC data
    chkIIM.Checked := FS.WriteIptcIIM;  // write legacy IIM data
    chkNef.Checked := FS.WriteIptcNef;  // write IIM data to NEF files
    chkExifOwner.Checked := FS.WriteExifOwner;  // write EXIF owner data
    chkLoadLast.Checked := FS.LoadLastAtStartup;  // load the last folder at start-up
    chkSingle.Checked := FS.SingleInstance;  // single instance
    chkWinSafe.Checked := FS.WinSafeNames;  // Windows-safe names
    edAuthor.Text := FS.ExifAuthor;  // EXIF author
    edCopyright.Text := FS.ExifCopyright;  // EXIF copyright

    chkAutoStart.Checked := FS.AutoAtStartup;  // automation at start-up
    chkAutoMenu.Checked := FS.AutoMenu;  // automation menu
    chkAutoPrompt.Checked := FS.AutoPrompt;  // automation prompt
    chkADownload.Checked := FS.AutoDownload;  // automatic download
    chkADelete.Checked := FS.AutoDelete;  // automatic delete
    chkSafeDel.Checked := FS.SafeDelete;  // safe delete
    edTrash.Text := FS.SafeDeleteFolder;  // trash folder name
    chkAEject.Checked := FS.AutoSoftEject;  // automatic soft eject
    chkALaunch.Checked := FS.AutoLaunch;  // automatic launch
    chkAExit.Checked := FS.AutoExit;  // automatic exit

    chkCustom.Checked := FS.CustomEnabled;  // custom button on or off
    edCaption.Text := FS.CustomCaption;  // custom button caption
    edCmd.Text := FS.CustomCmd;  // custom button command

    FMaps.Assign(FS.Mappings);  // copy the camera mappings
    chkSerial.Checked := FS.IdentifyBySerial;  // identify cameras by serial number
    chkPromptCam.Checked := FS.PromptNewCamera;  // prompt for new cameras
    edCurCam.Text := FCamera;  // current camera
    FPlugins.Assign(FS.Plugins);  // copy the plug-in list
    FPluginOpts.Assign(FS.PluginOpts);  // copy the plug-in options
  finally
    FUpdating := False;  // react to changes again
  end;
  GeneralChange(nil);  // update the dependent controls
  AutoChange(nil);  // update the dependent controls
  SafeDelChange(nil);  // update the dependent controls
  CustomChange(nil);  // update the dependent controls
  RefreshMaps(0);  // fill the mapping list
  RefreshPlugins(0);  // fill the plug-in list
  ExampleChange(nil);  // show the example name
end;

{ Writes the dialog values back to the settings. }
procedure TPrefsForm.Store;
begin
  FS.DownloadDir := Trim(cbDir.Text);  // download folder
  FS.FileNameMask := Trim(cbFile.Text);  // file name pattern
  FS.JobCode := Trim(cbJob.Text);        // may be blank
  FS.PromptJobCode := chkPromptJob.Checked;  // prompt for the job code
  FS.VerifyCopy := chkVerify.Checked;  // verify copies
  FS.BackupOn := chkBackup.Checked and (Trim(edBackup.Text) <> '');  // backup needs a folder
  FS.BackupDir := Trim(edBackup.Text);  // backup folder
  FS.SeqStart := seqStart.Value;  // first sequence number
  if FResetSeq then FS.SeqNext := FS.SeqStart;  // apply the sequence number reset

  if rbCamera.Checked then FS.SourceMode := smCamera  // camera source
  else if rbCard.Checked then FS.SourceMode := smCardReader  // card reader source
  else FS.SourceMode := smAuto;  // automatic source
  FS.DriveLetters := Trim(edLetters.Text);  // drive letters
  FS.DisablePTP := chkPTP.Checked;  // disable PTP
  FS.SaveReadOnly := chkReadOnly.Checked;  // save files as read-only
  FS.PreserveReadOnly := chkPreserveRO.Checked;  // preserve read-only status
  FS.PromptProfile := chkProfile.Checked;  // prompt for the profile
  FS.IgnoreSizeCheck := chkIgnoreSize.Checked;  // ignore the size check
  FS.AutoRenameClash := chkAutoRename.Checked;  // rename name clashes automatically
  FS.IgnoreDuplicates := chkIgnoreDup.Checked;  // skip duplicate files
  FS.RenameDuplicates := chkRenameDup.Checked;  // download duplicates renamed
  FS.AutoRotate := chkRotate.Checked;  // auto-rotate JPEGs
  FS.RenameJpe := chkJpe.Checked;  // rename .jpe files
  FS.LrPrevAsJpg := chkLrJpg.Checked;  // .lrprev files as .jpg
  FS.LrPrevKeepBoth := chkLrBoth.Checked;  // keep the .lrprev file as well
  FS.LowerName := chkLowerName.Checked;  // lower case names
  FS.LowerExt := chkLowerExt.Checked;  // lower case extensions
  FS.UseCaptureTime := chkStamp.Checked;  // use the capture time
  FS.SaveDateJobCodes := chkSaveJobs.Checked;  // save date based job codes
  FS.WriteExifText := chkExifTxt.Checked;  // write the EXIF text file
  FS.AutoEject := chkEject.Checked;  // eject automatically
  FS.ScanWholeDisk := chkWholeDisk.Checked;  // scan the whole disk
  FS.ScanLrData := chkLrData.Checked;  // scan Lightroom preview folders
  FS.AddIptc := chkIptc.Checked;  // add IPTC data
  FS.PromptIptc := chkPromptIptc.Checked;  // prompt for IPTC data
  FS.WriteIptcIIM := chkIIM.Checked;  // write legacy IIM data
  FS.WriteIptcNef := chkNef.Checked;  // write IIM data to NEF files
  FS.WriteExifOwner := chkExifOwner.Checked;  // write EXIF owner data
  FS.LoadLastAtStartup := chkLoadLast.Checked;  // load the last folder at start-up
  FS.SingleInstance := chkSingle.Checked;  // single instance
  FS.WinSafeNames := chkWinSafe.Checked;  // Windows-safe names
  {$IFDEF WINDOWS}WinSafeNamesOn := True;{$ELSE}WinSafeNamesOn := FS.WinSafeNames;{$ENDIF}
  FS.ExifAuthor := Trim(edAuthor.Text);  // EXIF author
  FS.ExifCopyright := Trim(edCopyright.Text);  // EXIF copyright

  FS.AutoAtStartup := chkAutoStart.Checked;  // automation at start-up
  FS.AutoMenu := chkAutoMenu.Checked;  // automation menu
  FS.AutoPrompt := chkAutoPrompt.Checked;  // automation prompt
  FS.AutoDownload := chkADownload.Checked;  // automatic download
  FS.AutoDelete := chkADelete.Checked;  // automatic delete
  FS.SafeDelete := chkSafeDel.Checked;  // safe delete
  FS.SafeDeleteFolder := CleanTrashName(edTrash.Text);  // trash folder name
  FS.AutoSoftEject := chkAEject.Checked;  // automatic soft eject
  FS.AutoLaunch := chkALaunch.Checked;  // automatic launch
  FS.AutoExit := chkAExit.Checked;  // automatic exit

  FS.CustomEnabled := chkCustom.Checked;  // custom button on or off
  FS.CustomCaption := edCaption.Text;  // custom button caption
  FS.CustomCmd := edCmd.Text;  // custom button command

  FS.Mappings.Assign(FMaps);  // copy the camera mappings back
  FS.IdentifyBySerial := chkSerial.Checked;  // identify cameras by serial number
  FS.PromptNewCamera := chkPromptCam.Checked;  // prompt for new cameras
  FS.Plugins.Assign(FPlugins);  // copy the plug-in list back
  FS.PluginOpts.Assign(FPluginOpts);  // copy the plug-in options back
end;

{ Shows the Preferences dialog; the settings change only when the user clicked OK. }
{ Shows the Preferences dialog; PluginTab opens it on the Plug-ins tab (File > Plug-ins). }
function ExecutePreferences(S: TAppSettings; const CurrentCamera: string; PluginTab: Boolean = False): Boolean;
var
  F: TPrefsForm;  // F: the dialog
begin
  F := TPrefsForm.CreatePrefs(Application, S, CurrentCamera);  // create the dialog
  try
    if PluginTab then F.PC.PageIndex := F.PC.PageCount - 1;  // the Plug-ins tab is the last one
    Result := F.ShowModal = mrOK;  // True when the user clicked OK
    if Result then F.Store;  // store the values
  finally
    F.Free;  // free the dialog
  end;
end;

end.
