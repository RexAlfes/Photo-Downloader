{ File > Import from Device...: the window that picks a connected phone, camera or drone controller and
  the folders to import from it (DCIM ticked when it has one). The import itself is done by
  TMainForm.ImportFromDevice with uDevices. }
unit uDeviceDlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, CheckLst, Dialogs;

{ Shows the window. On Import returns True with the device's name and Id and the ticked folders
  (FolderNames: "Storage\Folder", FolderIds: what finds them again). False when canceled or no device
  is connected (the window then says how to connect one). }
function ExecuteDeviceImport(out DevName, DevId: string; FolderNames, FolderIds: TStrings): Boolean;

{ The text shown when no device is found. }
function NoDeviceText: string;

implementation

uses
  uDevices;

type
  TDeviceImportForm = class(TForm)
  private
    cbDevice: TComboBox;  // the connected devices
    lstFolders: TCheckListBox;  // folders of the chosen device
    lblInfo: TLabel;  // hint under the list
    btnOk: TButton;  // Import
    FDevIds, FFolderIds: TStringList;  // what finds the devices and the listed folders again
    procedure DeviceChange(Sender: TObject);
    procedure FolderClick(Sender: TObject);
    procedure SelectAllClick(Sender: TObject);  // ticks every folder
    procedure ClearAllClick(Sender: TObject);  // clears every tick
    procedure UpdateOk;
  public
    constructor CreateDlg(Names, Ids: TStrings);
    destructor Destroy; override;
  end;

function NoDeviceText: string;
begin
  Result := 'No phone, camera or drone controller was found.'#13#10#13#10 +
    'Connect it by USB cable, unlock it and choose "File transfer" (phones and controllers) ' +
    'or PTP/MTP mode (cameras). An iPhone first asks to "Trust this computer".';
  if not DevicesSupported then
    Result := 'Importing from devices works on Windows only. On Linux, a connected phone or camera ' +
      'appears as a folder under /run/user/<your user number>/gvfs: open that folder with ' +
      'File > Open Source Folder.';
end;

constructor TDeviceImportForm.CreateDlg(Names, Ids: TStrings);
var
  L: TLabel;  // L: a label
  B: TButton;  // B: Select All, Clear All and Cancel
begin
  inherited CreateNew(nil);
  Caption := 'Import from Device';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 440;
  ClientHeight := 362;
  FDevIds := TStringList.Create;
  FDevIds.Assign(Ids);
  FFolderIds := TStringList.Create;

  L := TLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(12, 12, 416, 18);
  L.Caption := 'Device:';
  cbDevice := TComboBox.Create(Self);
  cbDevice.Parent := Self;
  cbDevice.Style := csDropDownList;  // choose only
  cbDevice.SetBounds(12, 32, 416, 24);
  cbDevice.Items.Assign(Names);
  cbDevice.OnChange := @DeviceChange;

  L := TLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(12, 66, 416, 18);
  L.Caption := 'Folders to import:';
  lstFolders := TCheckListBox.Create(Self);
  lstFolders.Parent := Self;
  lstFolders.SetBounds(12, 86, 416, 150);
  lstFolders.OnClickCheck := @FolderClick;

  B := TButton.Create(Self);  // tick every folder
  B.Parent := Self;
  B.Caption := 'Select All';
  B.SetBounds(12, 242, 90, 25);
  B.OnClick := @SelectAllClick;
  B := TButton.Create(Self);  // clear every tick
  B.Parent := Self;
  B.Caption := 'Clear All';
  B.SetBounds(108, 242, 90, 25);
  B.OnClick := @ClearAllClick;

  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := Self;
  lblInfo.SetBounds(12, 274, 416, 46);
  lblInfo.AutoSize := False;
  lblInfo.WordWrap := True;
  lblInfo.Caption := 'The files are copied to a staging folder on this computer and then shown like a card. ' +
    'Files copied before are not copied again.';

  btnOk := TButton.Create(Self);
  btnOk.Parent := Self;
  btnOk.Caption := 'Import';
  btnOk.SetBounds(262, 326, 80, 25);
  btnOk.ModalResult := mrOk;
  btnOk.Default := True;
  B := TButton.Create(Self);
  B.Parent := Self;
  B.Caption := 'Cancel';
  B.SetBounds(348, 326, 80, 25);
  B.ModalResult := mrCancel;
  B.Cancel := True;

  cbDevice.ItemIndex := 0;  // the first device
  DeviceChange(nil);
end;

destructor TDeviceImportForm.Destroy;
begin
  FDevIds.Free;
  FFolderIds.Free;
  inherited Destroy;
end;

{ Lists the folders of the chosen device and ticks DCIM. }
procedure TDeviceImportForm.DeviceChange(Sender: TObject);
var
  Names: TStringList;  // Names: "Storage\Folder"
  I: Integer;  // I: loop counter
begin
  lstFolders.Clear;
  FFolderIds.Clear;
  if cbDevice.ItemIndex < 0 then Exit;
  Names := TStringList.Create;
  Screen.Cursor := crHourGlass;  // a phone can take a moment
  try
    ListDeviceFolders(FDevIds[cbDevice.ItemIndex], Names, FFolderIds);
    lstFolders.Items.Assign(Names);
    for I := 0 to Names.Count - 1 do
      lstFolders.Checked[I] := SameText(ExtractFileName(StringReplace(Names[I], '\', PathDelim, [rfReplaceAll])), 'DCIM');  // photos and videos
  finally
    Screen.Cursor := crDefault;
    Names.Free;
  end;
  if lstFolders.Count = 0 then
    lblInfo.Caption := 'This device shows no folders. Unlock it and choose "File transfer" (phones) ' +
      'or PTP/MTP mode (cameras), then choose it here again.'
  else
    lblInfo.Caption := 'The files are copied to a staging folder on this computer and then shown like a card. ' +
      'Files copied before are not copied again.';
  UpdateOk;
end;

{ A folder was ticked or cleared. }
procedure TDeviceImportForm.FolderClick(Sender: TObject);
begin
  UpdateOk;
end;

{ Select All: ticks every folder. }
procedure TDeviceImportForm.SelectAllClick(Sender: TObject);
begin
  lstFolders.CheckAll(cbChecked, False, False);  // every folder
  UpdateOk;
end;

{ Clear All: clears every tick. }
procedure TDeviceImportForm.ClearAllClick(Sender: TObject);
begin
  lstFolders.CheckAll(cbUnchecked, False, False);  // no folder
  UpdateOk;
end;

{ Import needs at least one ticked folder. }
procedure TDeviceImportForm.UpdateOk;
var
  I: Integer;  // I: loop counter
begin
  btnOk.Enabled := False;
  for I := 0 to lstFolders.Count - 1 do
    if lstFolders.Checked[I] then btnOk.Enabled := True;
end;

function ExecuteDeviceImport(out DevName, DevId: string; FolderNames, FolderIds: TStrings): Boolean;
var
  Names, Ids: TStringList;  // Names, Ids: the connected devices
  F: TDeviceImportForm;  // F: the window
  I: Integer;  // I: loop counter
begin
  Result := False;
  DevName := '';
  DevId := '';
  FolderNames.Clear;
  FolderIds.Clear;
  Names := TStringList.Create;
  Ids := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      ListDevices(Names, Ids);
    finally
      Screen.Cursor := crDefault;
    end;
    if Names.Count = 0 then
    begin
      MessageDlg('Import from Device', NoDeviceText, mtInformation, [mbOK], 0);
      Exit;
    end;
    F := TDeviceImportForm.CreateDlg(Names, Ids);
    try
      if F.ShowModal <> mrOk then Exit;
      DevName := F.cbDevice.Text;
      DevId := Ids[F.cbDevice.ItemIndex];
      for I := 0 to F.lstFolders.Count - 1 do
        if F.lstFolders.Checked[I] then
        begin
          FolderNames.Add(F.lstFolders.Items[I]);
          FolderIds.Add(F.FFolderIds[I]);
        end;
      Result := FolderIds.Count > 0;
    finally
      F.Free;
    end;
  finally
    Names.Free;
    Ids.Free;
  end;
end;

end.
