unit uDialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, LCLType, LCLIntf, uSettings, uItems, uExif, uDrives, uVersion;

function ExecuteJobCode(S: TAppSettings; var Job: string; const CurrentCamera: string): Boolean;
function ExecutePreferences(S: TAppSettings; const CurrentCamera: string): Boolean;
function ExecuteIptc(L: TStringList): Boolean;
function ChooseFromList(const ATitle, APrompt: string; Items: TStrings; out Choice: string): Boolean;
procedure ShowTokenHelp;
procedure ShowAbout;
procedure ShowRegister;

implementation

const
  TokenHelpText =
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
    '{seq#} - download sequence number'#13#10 +
    '{n1} ... {n9} - download sequence number for this session, zero padded to 1-9 digits';

{ ---- small control factories ---- }

function MkLabel(P: TWinControl; const Cap: string; L, T: Integer): TLabel;
begin
  Result := TLabel.Create(P);
  Result.Parent := P;
  Result.Caption := Cap;
  Result.SetBounds(L, T, Result.Width, Result.Height);
end;

function MkWrap(P: TWinControl; const Cap: string; L, T, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(P);
  Result.Parent := P;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Caption := Cap;
  Result.SetBounds(L, T, W, H);
end;

function MkButton(P: TWinControl; const Cap: string; L, T, W: Integer;
  MR: TModalResult = mrNone): TButton;
begin
  Result := TButton.Create(P);
  Result.Parent := P;
  Result.Caption := Cap;
  Result.SetBounds(L, T, W, 25);
  Result.ModalResult := MR;
end;

function MkCheck(P: TWinControl; const Cap: string; L, T: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(P);
  Result.Parent := P;
  Result.Caption := Cap;
  Result.SetBounds(L, T, 460, 22);
end;

function MkEdit(P: TWinControl; L, T, W: Integer): TEdit;
begin
  Result := TEdit.Create(P);
  Result.Parent := P;
  Result.SetBounds(L, T, W, 23);
end;

function MkCombo(P: TWinControl; L, T, W: Integer): TComboBox;
begin
  Result := TComboBox.Create(P);
  Result.Parent := P;
  Result.SetBounds(L, T, W, 23);
  Result.Style := csDropDown;
end;

function MkRadio(P: TWinControl; const Cap: string; L, T: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(P);
  Result.Parent := P;
  Result.Caption := Cap;
  Result.SetBounds(L, T, 440, 22);
end;

procedure InitDialog(F: TForm; const ACaption: string; W, H: Integer);
begin
  F.Caption := ACaption;
  F.BorderStyle := bsDialog;
  F.Position := poMainFormCenter;
  F.ClientWidth := W;
  F.ClientHeight := H;
end;

procedure ShowTokenHelp;
begin
  MessageDlg('Directory and filename tokens', TokenHelpText, mtInformation, [mbOK], 0);
end;

procedure ShowAbout;
begin
  MessageDlg('About ' + AppTitle,
    AppTitle + ' ' + AppVersionString + #13#10#13#10 +
    'Downloads images from a card reader or folder, renames them using' + #13#10 +
    'tokens, and organises them into job-code folders.' + #13#10#13#10 +
    'Licensed under the GNU General Public License (see Help > Register).' + #13#10 +
    'Built with Lazarus / Free Pascal.', mtInformation, [mbOK], 0);
end;

const
  LicenseText =
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
  TRegisterForm = class(TForm)
  private
    procedure LicenseClick(Sender: TObject);
  public
    constructor CreateReg(AOwner: TComponent);
  end;

constructor TRegisterForm.CreateReg(AOwner: TComponent);
var
  M: TMemo;
begin
  inherited CreateNew(AOwner);
  InitDialog(Self, 'Register', 520, 400);
  MkLabel(Self, AppTitle + ' ' + AppVersionString, 12, 12);
  MkWrap(Self, 'No registration or licence key is needed. This software is free ' +
    'software released under the GNU General Public License:', 12, 36, 496, 34);
  M := TMemo.Create(Self);
  M.Parent := Self;
  M.SetBounds(12, 76, 496, 270);
  M.ReadOnly := True;
  M.ScrollBars := ssVertical;
  M.WordWrap := True;
  M.Text := LicenseText;
  MkButton(Self, 'View full license online', 12, 360, 170).OnClick := @LicenseClick;
  MkButton(Self, 'OK', 428, 360, 80, mrOK).Default := True;
end;

procedure TRegisterForm.LicenseClick(Sender: TObject);
begin
  OpenURL('https://www.gnu.org/licenses/gpl-3.0.html');
end;

procedure ShowRegister;
var
  F: TRegisterForm;
begin
  F := TRegisterForm.CreateReg(Application);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Job code dialog                                                         }
{ ====================================================================== }

type
  TJobForm = class(TForm)
  private
    FS: TAppSettings;
    FCamera: string;
    cbJob: TComboBox;
    edExample: TEdit;
    procedure UpdateExample(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure PrefsClick(Sender: TObject);
  public
    constructor CreateJob(AOwner: TComponent; AS_: TAppSettings; const AJob, ACamera: string);
  end;

constructor TJobForm.CreateJob(AOwner: TComponent; AS_: TAppSettings; const AJob, ACamera: string);
begin
  inherited CreateNew(AOwner);
  FS := AS_;
  FCamera := ACamera;
  InitDialog(Self, 'Job Code', 388, 190);
  MkLabel(Self, 'Please enter the job code:', 10, 14);
  cbJob := MkCombo(Self, 10, 34, 296);
  cbJob.Items.Assign(FS.JobHistory);
  cbJob.Text := AJob;
  cbJob.OnChange := @UpdateExample;
  MkButton(Self, 'Delete', 316, 33, 60).OnClick := @DeleteClick;
  MkLabel(Self, 'Example image name:', 10, 72);
  edExample := MkEdit(Self, 10, 92, 366);
  edExample.ReadOnly := True;
  MkButton(Self, 'Preferences...', 10, 148, 90).OnClick := @PrefsClick;
  MkButton(Self, 'OK', 206, 148, 80, mrOK).Default := True;
  MkButton(Self, 'Cancel', 296, 148, 80, mrCancel).Cancel := True;
  ActiveControl := cbJob;
  UpdateExample(nil);
end;

procedure TJobForm.UpdateExample(Sender: TObject);
begin
  edExample.Text := ExampleDest(FS, FS.DownloadDir, FS.FileNameMask, Trim(cbJob.Text));
end;

procedure TJobForm.DeleteClick(Sender: TObject);
var
  I: Integer;
begin
  I := FS.JobHistory.IndexOf(cbJob.Text);
  if I >= 0 then FS.JobHistory.Delete(I);
  I := cbJob.Items.IndexOf(cbJob.Text);
  if I >= 0 then cbJob.Items.Delete(I);
  cbJob.Text := '';
  UpdateExample(nil);
end;

procedure TJobForm.PrefsClick(Sender: TObject);
begin
  ExecutePreferences(FS, FCamera);
  UpdateExample(nil);
end;

function ExecuteJobCode(S: TAppSettings; var Job: string; const CurrentCamera: string): Boolean;
var
  F: TJobForm;
  V: string;
  I: Integer;
begin
  F := TJobForm.CreateJob(Application, S, Job, CurrentCamera);
  try
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      V := Trim(F.cbJob.Text);
      if V = '' then V := '{Job Name}';
      Job := V;
      I := S.JobHistory.IndexOf(V);
      if I >= 0 then S.JobHistory.Delete(I);
      if V <> '{Job Name}' then S.JobHistory.Insert(0, V);
      while S.JobHistory.Count > 30 do S.JobHistory.Delete(S.JobHistory.Count - 1);
    end;
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Generic list chooser (user profiles)                                    }
{ ====================================================================== }

function ChooseFromList(const ATitle, APrompt: string; Items: TStrings; out Choice: string): Boolean;
var
  F: TForm;
  LB: TListBox;
begin
  Choice := '';
  F := TForm.CreateNew(Application);
  try
    InitDialog(F, ATitle, 340, 290);
    MkLabel(F, APrompt, 10, 10);
    LB := TListBox.Create(F);
    LB.Parent := F;
    LB.SetBounds(10, 32, 320, 210);
    LB.Items.Assign(Items);
    if LB.Items.Count > 0 then LB.ItemIndex := 0;
    MkButton(F, 'OK', 160, 254, 80, mrOK).Default := True;
    MkButton(F, 'Cancel', 250, 254, 80, mrCancel).Cancel := True;
    Result := (F.ShowModal = mrOK) and (LB.ItemIndex >= 0);
    if Result then Choice := LB.Items[LB.ItemIndex];
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ IPTC / XMP dialog                                                       }
{ ====================================================================== }

function ExecuteIptc(L: TStringList): Boolean;
const
  Keys: array[0..8] of string =
    ('Creator', 'Copyright', 'Credit', 'Source', 'Title', 'Description', 'City', 'Country', 'Keywords');
var
  F: TForm;
  Ed: array[0..8] of TEdit;
  I: Integer;
begin
  F := TForm.CreateNew(Application);
  try
    InitDialog(F, 'IPTC/XMP data', 420, 340);
    for I := 0 to High(Keys) do
    begin
      MkLabel(F, Keys[I] + ':', 10, 14 + I * 30 + 3);
      Ed[I] := MkEdit(F, 100, 14 + I * 30, 306);
      Ed[I].Text := L.Values[Keys[I]];
    end;
    MkLabel(F, 'Keywords are separated by commas.', 100, 14 + 9 * 30 - 4);
    MkButton(F, 'OK', 236, 304, 80, mrOK).Default := True;
    MkButton(F, 'Cancel', 326, 304, 80, mrCancel).Cancel := True;
    Result := F.ShowModal = mrOK;
    if Result then
      for I := 0 to High(Keys) do
        L.Values[Keys[I]] := Trim(Ed[I].Text);
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Edit camera mapping                                                     }
{ ====================================================================== }

function EditMapping(const Cam: string; var T8, T9: string): Boolean;
var
  F: TForm;
  E8, E9: TEdit;
begin
  F := TForm.CreateNew(Application);
  try
    InitDialog(F, 'Edit mapping', 380, 150);
    MkLabel(F, 'Camera: ' + Cam, 10, 12);
    MkLabel(F, '{T8} =', 10, 46);
    E8 := MkEdit(F, 70, 42, 300);
    E8.Text := T8;
    MkLabel(F, '{T9} =', 10, 78);
    E9 := MkEdit(F, 70, 74, 300);
    E9.Text := T9;
    MkButton(F, 'OK', 200, 114, 80, mrOK).Default := True;
    MkButton(F, 'Cancel', 290, 114, 80, mrCancel).Cancel := True;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      T8 := E8.Text;
      T9 := E9.Text;
    end;
  finally
    F.Free;
  end;
end;

{ ====================================================================== }
{ Preferences dialog                                                      }
{ ====================================================================== }

type
  TPrefsForm = class(TForm)
  private
    FS: TAppSettings;
    FCamera: string;
    FMaps, FPlugins, FPluginOpts: TStringList;
    FResetSeq, FUpdating: Boolean;
    PC: TPageControl;
    // Download Path
    cbDir, cbFile, cbJob: TComboBox;
    chkPromptJob: TCheckBox;
    seqStart: TSpinEdit;
    edExample: TEdit;
    // General
    rbAuto, rbCamera, rbCard: TRadioButton;
    edLetters: TEdit;
    chkPTP, chkReadOnly, chkPreserveRO, chkProfile, chkIgnoreSize, chkRotate, chkJpe,
    chkLowerName, chkLowerExt, chkStamp, chkSaveJobs, chkExifTxt, chkEject, chkWholeDisk,
    chkIptc, chkPromptIptc, chkIIM, chkNef, chkExifOwner, chkLoadLast: TCheckBox;
    edAuthor, edCopyright: TEdit;
    // Automation
    chkAutoStart, chkAutoMenu, chkAutoPrompt, chkADownload, chkADelete, chkAEject,
    chkALaunch, chkAExit: TCheckBox;
    grpActions: TGroupBox;
    // Custom button
    chkCustom, chkBreeze: TCheckBox;
    edCaption, edCmd: TEdit;
    btnCmd: TButton;
    // Mapping
    lbMaps: TListBox;
    chkSerial, chkPromptCam: TCheckBox;
    edCurCam: TEdit;
    // Plug-ins
    lbPlugins: TListBox;
    chkPlugin: TCheckBox;
    lblPluginInfo: TLabel;
    procedure BuildPathTab(TS: TTabSheet);
    procedure BuildGeneralTab(TS: TTabSheet);
    procedure BuildAutomationTab(TS: TTabSheet);
    procedure BuildCustomTab(TS: TTabSheet);
    procedure BuildMappingTab(TS: TTabSheet);
    procedure BuildPluginTab(TS: TTabSheet);
    procedure LoadValues;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ExampleChange(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure TokensClick(Sender: TObject);
    procedure LocateClick(Sender: TObject);
    procedure GeneralChange(Sender: TObject);
    procedure AutoChange(Sender: TObject);
    procedure CustomChange(Sender: TObject);
    procedure CmdBrowseClick(Sender: TObject);
    procedure RefreshMaps(Sel: Integer);
    procedure AddCamera(const CamName: string);
    procedure MapAddCameraClick(Sender: TObject);
    procedure MapAddClick(Sender: TObject);
    procedure MapDeleteClick(Sender: TObject);
    procedure MapEditClick(Sender: TObject);
    procedure RefreshPlugins(Sel: Integer);
    procedure PluginSelect(Sender: TObject);
    procedure PluginToggle(Sender: TObject);
    procedure PluginUpClick(Sender: TObject);
    procedure PluginDownClick(Sender: TObject);
    procedure PluginSetupClick(Sender: TObject);
  public
    constructor CreatePrefs(AOwner: TComponent; AS_: TAppSettings; const ACamera: string);
    destructor Destroy; override;
    procedure Store;
  end;

constructor TPrefsForm.CreatePrefs(AOwner: TComponent; AS_: TAppSettings; const ACamera: string);
var
  BtnOK, BtnCancel: TButton;
begin
  inherited CreateNew(AOwner);
  FS := AS_;
  FCamera := ACamera;
  FMaps := TStringList.Create;
  FPlugins := TStringList.Create;
  FPluginOpts := TStringList.Create;
  InitDialog(Self, 'Preferences', 520, 660);
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  PC := TPageControl.Create(Self);
  PC.Parent := Self;
  PC.SetBounds(8, 8, 504, 604);
  BuildPathTab(PC.AddTabSheet);
  PC.Pages[0].Caption := 'Download Path';
  BuildGeneralTab(PC.AddTabSheet);
  PC.Pages[1].Caption := 'General';
  BuildAutomationTab(PC.AddTabSheet);
  PC.Pages[2].Caption := 'Automation';
  BuildCustomTab(PC.AddTabSheet);
  PC.Pages[3].Caption := 'Custom button';
  BuildMappingTab(PC.AddTabSheet);
  PC.Pages[4].Caption := 'Mapping';
  BuildPluginTab(PC.AddTabSheet);
  PC.Pages[5].Caption := 'Plug-ins';
  BtnOK := MkButton(Self, 'OK', 340, 622, 80, mrOK);
  BtnOK.Default := True;
  BtnCancel := MkButton(Self, 'Cancel', 430, 622, 80, mrCancel);
  BtnCancel.Cancel := True;
  LoadValues;
end;

destructor TPrefsForm.Destroy;
begin
  FMaps.Free;
  FPlugins.Free;
  FPluginOpts.Free;
  inherited Destroy;
end;

procedure TPrefsForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F1) and (Shift = []) then
  begin
    ShowTokenHelp;
    Key := 0;
  end;
end;

{ ---- Download Path ---- }

procedure TPrefsForm.BuildPathTab(TS: TTabSheet);
const
  Col1 = '{d} - date'#13#10'{y} - 2-digit year'#13#10'{Y} - 4-digit year'#13#10 +
         '{m} - month'#13#10'{b} - month (abbr.)'#13#10'{B} - full month'#13#10 +
         '{D} - day of month'#13#10'{a} - weekday';
  Col2 = '{A} - full weekday'#13#10'{W} - week'#13#10'{t} - time'#13#10'{H} - hour'#13#10 +
         '{I} - hour (01-12)'#13#10'{M} - minutes'#13#10'{S} - seconds'#13#10'{q} - folder';
  Col3 = '{r} - image'#13#10'{o} - orig'#13#10'{f} - filename prefix'#13#10'{O} - owner'#13#10 +
         '{i} - ISO'#13#10'{c} - camera serial'#13#10'{T} - camera'#13#10'{J} - Job code';
begin
  MkLabel(TS, 'Download directory:', 8, 6);
  cbDir := MkCombo(TS, 8, 26, 436);
  cbDir.Items.Add('N:\photos\{Y}\{Y}-{m}-{D}-{J}\Master\');
  cbDir.Items.Add('D:\Photos\{Y}\{Y}-{m}-{D}-{J}\');
  cbDir.OnChange := @ExampleChange;
  MkButton(TS, '...', 452, 25, 28).OnClick := @BrowseClick;

  MkLabel(TS, 'Filename:', 8, 62);
  cbFile := MkCombo(TS, 66, 58, 414);
  cbFile.Items.Add('RA{Y}{m}{D}-{r}');
  cbFile.Items.Add('{Y}{m}{D}-{t}-{o}');
  cbFile.Items.Add('{o}');
  cbFile.OnChange := @ExampleChange;

  MkLabel(TS, 'Job code {J}:', 8, 94);
  cbJob := MkCombo(TS, 90, 90, 390);
  cbJob.Items.Add('{Job Name}');
  cbJob.OnChange := @ExampleChange;

  chkPromptJob := MkCheck(TS, 'Prompt for Job code every time Downloader is run', 8, 120);
  MkLabel(TS, 'Sequence number starting', 8, 152);
  seqStart := TSpinEdit.Create(TS);
  seqStart.Parent := TS;
  seqStart.SetBounds(170, 148, 80, 23);
  seqStart.MinValue := 0;
  seqStart.MaxValue := 999999999;
  MkButton(TS, 'Reset', 262, 147, 70).OnClick := @ResetClick;

  MkLabel(TS, 'Directory and filename tokens (press F1 for a complete list):', 8, 184);
  MkWrap(TS, Col1, 8, 204, 150, 125);
  MkWrap(TS, Col2, 168, 204, 150, 125);
  MkWrap(TS, Col3, 330, 204, 150, 125);
  MkLabel(TS, '{seq#} - download sequence', 8, 332);
  MkLabel(TS, '{n4} - download sequence number (this session)', 8, 350);
  MkButton(TS, 'Show tokens...', 380, 346, 100).OnClick := @TokensClick;

  MkLabel(TS, 'Example image', 8, 386);
  edExample := MkEdit(TS, 8, 406, 472);
  edExample.ReadOnly := True;
end;

procedure TPrefsForm.ExampleChange(Sender: TObject);
begin
  if FUpdating then Exit;
  edExample.Text := ExampleDest(FS, cbDir.Text, cbFile.Text, cbJob.Text);
end;

procedure TPrefsForm.BrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Select download directory';
    if D.Execute then
      cbDir.Text := IncludeTrailingPathDelimiter(D.FileName) +
        '{Y}' + PathDelim + '{Y}-{m}-{D}-{J}' + PathDelim;
  finally
    D.Free;
  end;
end;

procedure TPrefsForm.ResetClick(Sender: TObject);
begin
  FResetSeq := True;
  ShowMessage('The sequence number will be reset to ' + IntToStr(seqStart.Value) +
    ' when you press OK.');
end;

procedure TPrefsForm.TokensClick(Sender: TObject);
begin
  ShowTokenHelp;
end;

{ ---- General ---- }

procedure TPrefsForm.BuildGeneralTab(TS: TTabSheet);
var
  G: TGroupBox;
  Y: Integer;
begin
  G := TGroupBox.Create(TS);
  G.Parent := TS;
  G.Caption := 'Image source';
  G.SetBounds(6, 2, 482, 140);
  rbAuto := MkRadio(G, 'Auto-detect camera or card reader (used by Refresh and automation)', 10, 2);
  rbCamera := MkRadio(G, 'Camera (connected by USB)', 10, 26);
  rbCard := MkRadio(G, 'Card reader or external storage device', 10, 50);
  MkLabel(G, 'Drive letter or letters:', 34, 84);
  edLetters := MkEdit(G, 170, 80, 110);
  MkButton(G, 'Locate card reader', 300, 78, 150).OnClick := @LocateClick;
  chkPTP := MkCheck(G, 'Disable PTP downloads', 10, 108);

  Y := 148;
  chkLoadLast := MkCheck(TS, 'Load the last used source folder at startup (otherwise nothing is scanned)', 8, Y);
  Inc(Y, 21);
  chkReadOnly := MkCheck(TS, 'Save files as read-only', 8, Y);
  chkReadOnly.Width := 240;
  chkPreserveRO := MkCheck(TS, 'Preserve read-only status', 260, Y);
  Inc(Y, 21);
  chkProfile := MkCheck(TS, 'Prompt for user profile at startup', 8, Y);
  Inc(Y, 21);
  chkIgnoreSize := MkCheck(TS, 'Ignore file size check to allow for images modified after downloading', 8, Y);
  Inc(Y, 21);
  chkRotate := MkCheck(TS, 'Auto-rotate JPEGs after downloading (lossless rotation)', 8, Y);
  Inc(Y, 21);
  chkJpe := MkCheck(TS, 'Rename files with .jpe extension to .jpg when downloading', 8, Y);
  Inc(Y, 21);
  chkLowerName := MkCheck(TS, 'Convert filename to lower case', 8, Y);
  chkLowerName.Width := 240;
  chkLowerExt := MkCheck(TS, 'Lower case file extensions', 260, Y);
  Inc(Y, 21);
  chkStamp := MkCheck(TS, 'Use image capture time for file timestamp', 8, Y);
  Inc(Y, 21);
  chkSaveJobs := MkCheck(TS, 'Save date based job codes for next time Photo Downloader is run', 8, Y);
  Inc(Y, 21);
  chkExifTxt := MkCheck(TS, 'Generate text file containing EXIF shooting data', 8, Y);
  Inc(Y, 21);
  chkEject := MkCheck(TS, 'Automatically ''eject'' card reader media when disconnecting', 8, Y);
  Inc(Y, 21);
  chkWholeDisk := MkCheck(TS, 'Scan whole disk for known image types', 8, Y);
  Inc(Y, 21);
  chkIptc := MkCheck(TS, 'Add IPTC/XMP data to downloaded images', 8, Y);
  Inc(Y, 21);
  chkPromptIptc := MkCheck(TS, 'Prompt for IPTC/XMP data every time Photo Downloader is run', 28, Y);
  Inc(Y, 21);
  chkIIM := MkCheck(TS, 'Also write legacy IPTC IIM data to downloaded images', 28, Y);
  Inc(Y, 21);
  chkNef := MkCheck(TS, 'Enable writing of legacy IPTC IIM data to Nikon NEF raw files', 28, Y);
  Inc(Y, 28);
  chkExifOwner := MkCheck(TS, 'Add author and copyright to EXIF of downloaded JPEGs (only where empty)', 8, Y);
  Inc(Y, 26);
  MkLabel(TS, 'Author:', 28, Y + 3);
  edAuthor := MkEdit(TS, 100, Y, 380);
  Inc(Y, 28);
  MkLabel(TS, 'Copyright:', 28, Y + 3);
  edCopyright := MkEdit(TS, 100, Y, 380);

  chkIptc.OnClick := @GeneralChange;
  chkExifOwner.OnClick := @GeneralChange;
  rbAuto.OnClick := @GeneralChange;
  rbCamera.OnClick := @GeneralChange;
  rbCard.OnClick := @GeneralChange;
end;

procedure TPrefsForm.GeneralChange(Sender: TObject);
begin
  chkPromptIptc.Enabled := chkIptc.Checked;
  chkIIM.Enabled := chkIptc.Checked;
  chkNef.Enabled := chkIptc.Checked;
  edAuthor.Enabled := chkExifOwner.Checked;
  edCopyright.Enabled := chkExifOwner.Checked;
  edLetters.Enabled := rbCard.Checked;
end;

procedure TPrefsForm.LocateClick(Sender: TObject);
var
  L: TStringList;
  I: Integer;
  Letters: string;
begin
  L := TStringList.Create;
  try
    ListRemovableDrives(L);
    if L.Count = 0 then
      ShowMessage('No card reader or removable drive was found.')
    else
    begin
      Letters := '';
      for I := 0 to L.Count - 1 do
        Letters := Letters + Copy(L[I], 1, 1);
      edLetters.Text := Letters;
      rbCard.Checked := True;
    end;
  finally
    L.Free;
  end;
end;

{ ---- Automation ---- }

procedure TPrefsForm.BuildAutomationTab(TS: TTabSheet);
begin
  MkWrap(TS, 'Use the settings below to enable automatic downloading of images when ' +
    'Downloader is run. Select "Prompt before starting auto sequence" if you want to be ' +
    'able to choose whether automation should run.'#13#10 +
    'The automation sequence will stop if there are any errors or an operation is canceled.',
    8, 8, 480, 90);
  chkAutoStart := MkCheck(TS, 'Enable Automation at startup', 66, 104);
  chkAutoMenu := MkCheck(TS, 'Enable Automation menu option and keyboard shortcut', 66, 128);
  chkAutoPrompt := MkCheck(TS, 'Prompt before starting auto sequence', 66, 152);
  grpActions := TGroupBox.Create(TS);
  grpActions.Parent := TS;
  grpActions.Caption := 'Actions';
  grpActions.SetBounds(44, 186, 420, 180);
  chkADownload := MkCheck(grpActions, 'Download files when application is started', 28, 6);
  chkADelete := MkCheck(grpActions, 'Delete files from CF card after downloading', 28, 32);
  chkAEject := MkCheck(grpActions, '''Soft eject'' card reader media', 28, 58);
  chkALaunch := MkCheck(grpActions, 'Launch app associated with custom button', 28, 84);
  chkAExit := MkCheck(grpActions, 'Exit Downloader', 28, 110);
  chkAutoStart.OnClick := @AutoChange;
  chkAutoMenu.OnClick := @AutoChange;
end;

procedure TPrefsForm.AutoChange(Sender: TObject);
begin
  chkAutoPrompt.Enabled := chkAutoMenu.Checked;
  grpActions.Enabled := chkAutoStart.Checked or chkAutoMenu.Checked;
  chkADownload.Enabled := grpActions.Enabled;
  chkADelete.Enabled := grpActions.Enabled;
  chkAEject.Enabled := grpActions.Enabled;
  chkALaunch.Enabled := grpActions.Enabled;
  chkAExit.Enabled := grpActions.Enabled;
end;

{ ---- Custom button ---- }

procedure TPrefsForm.BuildCustomTab(TS: TTabSheet);
var
  G: TGroupBox;
begin
  G := TGroupBox.Create(TS);
  G.Parent := TS;
  G.Caption := 'Custom button';
  G.SetBounds(16, 24, 458, 160);
  chkCustom := MkCheck(G, 'Enable custom button', 10, 6);
  chkBreeze := MkCheck(G, 'Link button to BreezeBrowser Pro or BreezeBrowser', 10, 30);
  MkLabel(G, 'Button caption:', 10, 64);
  edCaption := MkEdit(G, 110, 60, 150);
  MkLabel(G, 'Command line (use %f for file and %d for directory):', 10, 92);
  edCmd := MkEdit(G, 10, 112, 392);
  btnCmd := MkButton(G, '...', 410, 111, 28);
  btnCmd.OnClick := @CmdBrowseClick;
  MkWrap(TS, 'Select "Enable custom button" to add a custom button to Downloader. The ' +
    'custom button can be used to launch the application of your choice. Pressing the ' +
    'custom button after downloading your files will run the command line, with %f replaced ' +
    'by the last downloaded file and %d by the folder containing the downloaded files.',
    8, 204, 480, 120);
  chkCustom.OnClick := @CustomChange;
end;

procedure TPrefsForm.CustomChange(Sender: TObject);
begin
  chkBreeze.Enabled := False;   // BreezeBrowser integration is not available
  edCaption.Enabled := chkCustom.Checked;
  edCmd.Enabled := chkCustom.Checked;
  btnCmd.Enabled := chkCustom.Checked;
end;

procedure TPrefsForm.CmdBrowseClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    if D.Execute then edCmd.Text := '"' + D.FileName + '" "%f"';
  finally
    D.Free;
  end;
end;

{ ---- Mapping ---- }

procedure TPrefsForm.BuildMappingTab(TS: TTabSheet);
begin
  MkLabel(TS, 'Current camera model mappings for the {T8} and {T9} tokens:', 8, 6);
  lbMaps := TListBox.Create(TS);
  lbMaps.Parent := TS;
  lbMaps.SetBounds(8, 26, 478, 250);
  MkWrap(TS, 'Add camera models by clicking on the "Add camera..." button.', 8, 288, 340, 34);
  MkButton(TS, 'Add camera...', 366, 286, 120).OnClick := @MapAddCameraClick;
  chkSerial := MkCheck(TS, 'Identify camera using serial number, owner string or user comment', 8, 326);
  MkLabel(TS, 'Current camera:', 8, 358);
  edCurCam := MkEdit(TS, 100, 354, 290);
  edCurCam.ReadOnly := False;
  MkButton(TS, 'Add', 400, 353, 86).OnClick := @MapAddClick;
  chkPromptCam := MkCheck(TS, 'Prompt for camera mappings when a new camera is detected', 8, 386);
  MkWrap(TS, 'Remove entries from the list by selecting them and pressing the "Delete" button.',
    8, 418, 340, 34);
  MkButton(TS, 'Delete', 366, 416, 120).OnClick := @MapDeleteClick;
  MkWrap(TS, 'Click on the "Edit..." button to edit the value of the {T8} and {T9} tokens for ' +
    'the selected camera.', 8, 458, 340, 34);
  MkButton(TS, 'Edit...', 366, 456, 120).OnClick := @MapEditClick;
end;

procedure TPrefsForm.RefreshMaps(Sel: Integer);
var
  I: Integer;
  N, A, B: string;
begin
  lbMaps.Items.BeginUpdate;
  try
    lbMaps.Items.Clear;
    for I := 0 to FMaps.Count - 1 do
    begin
      MapSplit(FMaps[I], N, A, B);
      if I = 0 then N := 'Default mapping';
      lbMaps.Items.Add(N + ' -> {T8}=' + A + ' | {T9}=' + B);
    end;
  finally
    lbMaps.Items.EndUpdate;
  end;
  if (Sel >= 0) and (Sel < lbMaps.Items.Count) then lbMaps.ItemIndex := Sel;
end;

procedure TPrefsForm.AddCamera(const CamName: string);
var
  I: Integer;
  N, A, B: string;
begin
  if Trim(CamName) = '' then Exit;
  for I := 1 to FMaps.Count - 1 do
  begin
    MapSplit(FMaps[I], N, A, B);
    if SameText(N, CamName) then
    begin
      RefreshMaps(I);
      Exit;
    end;
  end;
  FMaps.Add(MapJoin(Trim(CamName), '{T1}', '{T1}'));
  RefreshMaps(FMaps.Count - 1);
end;

procedure TPrefsForm.MapAddCameraClick(Sender: TObject);
var
  D: TOpenDialog;
  Info: TExifInfo;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Select an image from the camera';
    D.Filter := 'Images|*.jpg;*.jpeg;*.nef;*.cr2;*.dng;*.arw;*.tif;*.tiff|All files|*.*';
    if D.Execute then
    begin
      if ReadExifFromFile(D.FileName, Info) and (Info.Model <> '') then
        AddCamera(Info.Model)
      else
        ShowMessage('No camera model could be read from that file.');
    end;
  finally
    D.Free;
  end;
end;

procedure TPrefsForm.MapAddClick(Sender: TObject);
begin
  AddCamera(edCurCam.Text);
end;

procedure TPrefsForm.MapDeleteClick(Sender: TObject);
var
  I: Integer;
begin
  I := lbMaps.ItemIndex;
  if I <= 0 then
  begin
    if I = 0 then ShowMessage('The default mapping cannot be deleted.');
    Exit;
  end;
  FMaps.Delete(I);
  RefreshMaps(Min(I, FMaps.Count - 1));
end;

procedure TPrefsForm.MapEditClick(Sender: TObject);
var
  I: Integer;
  N, A, B: string;
begin
  I := lbMaps.ItemIndex;
  if I < 0 then Exit;
  MapSplit(FMaps[I], N, A, B);
  if I = 0 then N := 'Default';
  if EditMapping(N, A, B) then
  begin
    FMaps[I] := MapJoin(N, A, B);
    RefreshMaps(I);
  end;
end;

{ ---- Plug-ins ---- }

procedure TPrefsForm.BuildPluginTab(TS: TTabSheet);
begin
  lbPlugins := TListBox.Create(TS);
  lbPlugins.Parent := TS;
  lbPlugins.SetBounds(8, 8, 380, 200);
  lbPlugins.OnClick := @PluginSelect;
  MkButton(TS, 'Up', 404, 8, 80).OnClick := @PluginUpClick;
  MkButton(TS, 'Down', 404, 40, 80).OnClick := @PluginDownClick;
  chkPlugin := MkCheck(TS, 'Enable plug-in', 8, 220);
  chkPlugin.Width := 130;
  chkPlugin.OnClick := @PluginToggle;
  MkButton(TS, 'Setup...', 150, 218, 100).OnClick := @PluginSetupClick;
  lblPluginInfo := MkWrap(TS, '', 8, 258, 478, 80);
end;

procedure TPrefsForm.RefreshPlugins(Sel: Integer);
var
  I: Integer;
begin
  lbPlugins.Items.Clear;
  for I := 0 to FPlugins.Count - 1 do
    if FPlugins.ValueFromIndex[I] = '1' then
      lbPlugins.Items.Add(FPlugins.Names[I] + ' - enabled')
    else
      lbPlugins.Items.Add(FPlugins.Names[I] + ' - disabled');
  if (Sel >= 0) and (Sel < lbPlugins.Items.Count) then lbPlugins.ItemIndex := Sel;
  PluginSelect(nil);
end;

procedure TPrefsForm.PluginSelect(Sender: TObject);
var
  I: Integer;
  Nm, Info: string;
begin
  I := lbPlugins.ItemIndex;
  FUpdating := True;
  try
    if I < 0 then
    begin
      chkPlugin.Checked := False;
      lblPluginInfo.Caption := '';
      Exit;
    end;
    Nm := FPlugins.Names[I];
    chkPlugin.Checked := FPlugins.ValueFromIndex[I] = '1';
    if Nm = 'JPEG auto profile' then
      Info := 'Automatically embeds color profiles in JPEGs.'#13#10 +
              'Different color profiles can be defined for each camera model.'#13#10 +
              '(Not yet implemented in this build.)'
    else if Nm = 'Backup' then
      Info := 'Saves a second copy of every downloaded image to a backup folder.'
    else if Nm = 'Directory Maker' then
      Info := 'Creates extra sub-folders (for example Edit and Web) next to the download folder.'
    else if Nm = 'DNG Converter' then
      Info := 'Converts raw files to DNG after downloading.'#13#10 +
              '(Not yet implemented in this build.)'
    else
      Info := 'Resizes JPEGs while downloading.'#13#10 + '(Not yet implemented in this build.)';
    lblPluginInfo.Caption := Info;
  finally
    FUpdating := False;
  end;
end;

procedure TPrefsForm.PluginToggle(Sender: TObject);
var
  I: Integer;
begin
  if FUpdating then Exit;
  I := lbPlugins.ItemIndex;
  if I < 0 then Exit;
  if chkPlugin.Checked then
    FPlugins[I] := FPlugins.Names[I] + '=1'
  else
    FPlugins[I] := FPlugins.Names[I] + '=0';
  RefreshPlugins(I);
end;

procedure TPrefsForm.PluginUpClick(Sender: TObject);
var
  I: Integer;
begin
  I := lbPlugins.ItemIndex;
  if I > 0 then
  begin
    FPlugins.Exchange(I, I - 1);
    RefreshPlugins(I - 1);
  end;
end;

procedure TPrefsForm.PluginDownClick(Sender: TObject);
var
  I: Integer;
begin
  I := lbPlugins.ItemIndex;
  if (I >= 0) and (I < FPlugins.Count - 1) then
  begin
    FPlugins.Exchange(I, I + 1);
    RefreshPlugins(I + 1);
  end;
end;

procedure TPrefsForm.PluginSetupClick(Sender: TObject);
var
  I: Integer;
  Nm, V: string;
  D: TSelectDirectoryDialog;
begin
  I := lbPlugins.ItemIndex;
  if I < 0 then Exit;
  Nm := FPlugins.Names[I];
  if Nm = 'Backup' then
  begin
    D := TSelectDirectoryDialog.Create(Self);
    try
      D.Title := 'Select backup folder';
      if D.Execute then FPluginOpts.Values['Backup'] := D.FileName;
    finally
      D.Free;
    end;
  end
  else if Nm = 'Directory Maker' then
  begin
    V := FPluginOpts.Values['Directory Maker'];
    if InputQuery('Directory Maker', 'Folders to create (comma separated):', V) then
      FPluginOpts.Values['Directory Maker'] := V;
  end
  else
    ShowMessage('The "' + Nm + '" plug-in has no options in this build.');
end;

{ ---- load / store ---- }

procedure TPrefsForm.LoadValues;
begin
  FUpdating := True;
  try
    cbDir.Text := FS.DownloadDir;
    cbFile.Text := FS.FileNameMask;
    cbJob.Text := FS.JobCode;
    chkPromptJob.Checked := FS.PromptJobCode;
    seqStart.Value := FS.SeqStart;

    rbAuto.Checked := FS.SourceMode = smAuto;
    rbCamera.Checked := FS.SourceMode = smCamera;
    rbCard.Checked := FS.SourceMode = smCardReader;
    edLetters.Text := FS.DriveLetters;
    chkPTP.Checked := FS.DisablePTP;
    chkReadOnly.Checked := FS.SaveReadOnly;
    chkPreserveRO.Checked := FS.PreserveReadOnly;
    chkProfile.Checked := FS.PromptProfile;
    chkIgnoreSize.Checked := FS.IgnoreSizeCheck;
    chkRotate.Checked := FS.AutoRotate;
    chkJpe.Checked := FS.RenameJpe;
    chkLowerName.Checked := FS.LowerName;
    chkLowerExt.Checked := FS.LowerExt;
    chkStamp.Checked := FS.UseCaptureTime;
    chkSaveJobs.Checked := FS.SaveDateJobCodes;
    chkExifTxt.Checked := FS.WriteExifText;
    chkEject.Checked := FS.AutoEject;
    chkWholeDisk.Checked := FS.ScanWholeDisk;
    chkIptc.Checked := FS.AddIptc;
    chkPromptIptc.Checked := FS.PromptIptc;
    chkIIM.Checked := FS.WriteIptcIIM;
    chkNef.Checked := FS.WriteIptcNef;
    chkExifOwner.Checked := FS.WriteExifOwner;
    chkLoadLast.Checked := FS.LoadLastAtStartup;
    edAuthor.Text := FS.ExifAuthor;
    edCopyright.Text := FS.ExifCopyright;

    chkAutoStart.Checked := FS.AutoAtStartup;
    chkAutoMenu.Checked := FS.AutoMenu;
    chkAutoPrompt.Checked := FS.AutoPrompt;
    chkADownload.Checked := FS.AutoDownload;
    chkADelete.Checked := FS.AutoDelete;
    chkAEject.Checked := FS.AutoSoftEject;
    chkALaunch.Checked := FS.AutoLaunch;
    chkAExit.Checked := FS.AutoExit;

    chkCustom.Checked := FS.CustomEnabled;
    chkBreeze.Checked := FS.CustomLinkBreeze;
    edCaption.Text := FS.CustomCaption;
    edCmd.Text := FS.CustomCmd;

    FMaps.Assign(FS.Mappings);
    chkSerial.Checked := FS.IdentifyBySerial;
    chkPromptCam.Checked := FS.PromptNewCamera;
    edCurCam.Text := FCamera;
    FPlugins.Assign(FS.Plugins);
    FPluginOpts.Assign(FS.PluginOpts);
  finally
    FUpdating := False;
  end;
  GeneralChange(nil);
  AutoChange(nil);
  CustomChange(nil);
  RefreshMaps(0);
  RefreshPlugins(0);
  ExampleChange(nil);
end;

procedure TPrefsForm.Store;
begin
  FS.DownloadDir := Trim(cbDir.Text);
  FS.FileNameMask := Trim(cbFile.Text);
  if Trim(cbJob.Text) <> '' then FS.JobCode := Trim(cbJob.Text);
  FS.PromptJobCode := chkPromptJob.Checked;
  FS.SeqStart := seqStart.Value;
  if FResetSeq then FS.SeqNext := FS.SeqStart;

  if rbCamera.Checked then FS.SourceMode := smCamera
  else if rbCard.Checked then FS.SourceMode := smCardReader
  else FS.SourceMode := smAuto;
  FS.DriveLetters := Trim(edLetters.Text);
  FS.DisablePTP := chkPTP.Checked;
  FS.SaveReadOnly := chkReadOnly.Checked;
  FS.PreserveReadOnly := chkPreserveRO.Checked;
  FS.PromptProfile := chkProfile.Checked;
  FS.IgnoreSizeCheck := chkIgnoreSize.Checked;
  FS.AutoRotate := chkRotate.Checked;
  FS.RenameJpe := chkJpe.Checked;
  FS.LowerName := chkLowerName.Checked;
  FS.LowerExt := chkLowerExt.Checked;
  FS.UseCaptureTime := chkStamp.Checked;
  FS.SaveDateJobCodes := chkSaveJobs.Checked;
  FS.WriteExifText := chkExifTxt.Checked;
  FS.AutoEject := chkEject.Checked;
  FS.ScanWholeDisk := chkWholeDisk.Checked;
  FS.AddIptc := chkIptc.Checked;
  FS.PromptIptc := chkPromptIptc.Checked;
  FS.WriteIptcIIM := chkIIM.Checked;
  FS.WriteIptcNef := chkNef.Checked;
  FS.WriteExifOwner := chkExifOwner.Checked;
  FS.LoadLastAtStartup := chkLoadLast.Checked;
  FS.ExifAuthor := Trim(edAuthor.Text);
  FS.ExifCopyright := Trim(edCopyright.Text);

  FS.AutoAtStartup := chkAutoStart.Checked;
  FS.AutoMenu := chkAutoMenu.Checked;
  FS.AutoPrompt := chkAutoPrompt.Checked;
  FS.AutoDownload := chkADownload.Checked;
  FS.AutoDelete := chkADelete.Checked;
  FS.AutoSoftEject := chkAEject.Checked;
  FS.AutoLaunch := chkALaunch.Checked;
  FS.AutoExit := chkAExit.Checked;

  FS.CustomEnabled := chkCustom.Checked;
  FS.CustomLinkBreeze := chkBreeze.Checked;
  FS.CustomCaption := edCaption.Text;
  FS.CustomCmd := edCmd.Text;

  FS.Mappings.Assign(FMaps);
  FS.IdentifyBySerial := chkSerial.Checked;
  FS.PromptNewCamera := chkPromptCam.Checked;
  FS.Plugins.Assign(FPlugins);
  FS.PluginOpts.Assign(FPluginOpts);
end;

function ExecutePreferences(S: TAppSettings; const CurrentCamera: string): Boolean;
var
  F: TPrefsForm;
begin
  F := TPrefsForm.CreatePrefs(Application, S, CurrentCamera);
  try
    Result := F.ShowModal = mrOK;
    if Result then F.Store;
  finally
    F.Free;
  end;
end;

end.
