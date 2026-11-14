{ MessageDlg with the same button order on every system: Yes (or OK) first, on the left.

  On Windows the LCL message box already shows the buttons in the order Yes, No, OK, Cancel. The GTK 2
  widgetset replaces it with GTK's own message box and adds the buttons back to front (GTK's habit:
  No, Yes), so on Linux Yes was on the right. Units list this unit after Dialogs, so their MessageDlg
  calls come here: on GTK 2 they use the LCL's own message window (DefaultPromptDialog, the same one
  other widgetsets use), elsewhere the normal MessageDlg.

  GTK's file windows (open, save, choose folder) show Cancel before Open/Save as well; OkFirst moves the
  Open/Save button to the left when such a window appears. }
unit uMsgDlg;

{$mode objfpc}{$H+}
{$WARN 5024 OFF}  // HelpCtx is not used (the program has no help topics); kept so the calls stay the same
{$WARN 4055 OFF}  // GTK 2: a dialog's handle is the address of its GTK window

interface

uses
  Controls, Dialogs, System.UITypes;  // System.UITypes: TModalResult and the mr... values

{ Message box with a caption; buttons in the order Yes, No, OK, Cancel ... (left to right). }
function MessageDlg(const aCaption, aMsg: string; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons;
  HelpCtx: Longint): TModalResult; overload;
{ Message box without a caption (the program title is used). }
function MessageDlg(const aMsg: string; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons;
  HelpCtx: Longint): TModalResult; overload;
{ A file window (TOpenDialog, TSaveDialog, TSelectDirectoryDialog) with Open/Save on the left of Cancel:
  on GTK 2 it moves the button when the window appears (uses the dialog's OnShow); elsewhere nothing. }
procedure OkFirst(D: TCommonDialog);

implementation

{$IFDEF LCLGTK2}
uses
  LCLType, LazStringUtils, Forms, glib2, gtk2;

type
  { Receives OnShow of the file windows. }
  TOkFirstHelper = class
    procedure DialogShow(Sender: TObject);
  end;

var
  OkFirstHelper: TOkFirstHelper = nil;  // made on first use, freed at the end

{ The GTK window exists now: move its last button (Open or Save; Cancel was added first) to the left. }
procedure TOkFirstHelper.DialogShow(Sender: TObject);
var
  Dlg: PGtkDialog;  // Dlg: the GTK file window
  Kids, P: PGList;  // Kids, P: the buttons of its button row
  Last: PGtkWidget;  // Last: the last button
begin
  if not (Sender is TCommonDialog) or (TCommonDialog(Sender).Handle = 0) then Exit;
  Dlg := PGtkDialog(TCommonDialog(Sender).Handle);
  if Dlg^.action_area = nil then Exit;
  Kids := gtk_container_get_children(PGtkContainer(Dlg^.action_area));
  Last := nil;
  P := Kids;
  while P <> nil do
  begin
    Last := PGtkWidget(P^.data);
    P := P^.next;
  end;
  if Last <> nil then gtk_box_reorder_child(PGtkBox(Dlg^.action_area), Last, 0);  // first = leftmost
  g_list_free(Kids);
end;

const
  DialogIds: array[mtWarning..mtCustom] of Longint = (idDialogWarning, idDialogError, idDialogInfo,
    idDialogConfirm, idDialogBase);  // as Dialogs.MessageDlg passes them
  ButtonIds: array[TMsgDlgBtn] of Longint = (idButtonYes, idButtonNo, idButtonOK, idButtonCancel,
    idButtonAbort, idButtonRetry, idButtonIgnore, idButtonAll, idButtonNoToAll, idButtonYesToAll,
    idButtonHelp, idButtonClose);  // the LCL's order of the buttons

{ The button Enter presses: the same rule as the LCL (Yes, then OK, ...). }
function DefaultButtonOf(Buttons: TMsgDlgButtons): TMsgDlgBtn;
const
  Order: array[0..7] of TMsgDlgBtn = (mbYes, mbOK, mbYesToAll, mbAll, mbRetry, mbCancel, mbNo, mbNoToAll);
var
  B: TMsgDlgBtn;  // B: a button
begin
  for B in Order do
    if B in Buttons then Exit(B);
  Result := mbOK;
  for B := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if B in Buttons then Result := B;
end;

{ The modal result of a button id. }
function ResultOf(Id: Longint): TModalResult;
begin
  case Id of
    idButtonOK: Result := mrOk;
    idButtonCancel: Result := mrCancel;
    idButtonYes: Result := mrYes;
    idButtonNo: Result := mrNo;
    idButtonClose: Result := mrClose;
    idButtonAbort: Result := mrAbort;
    idButtonRetry: Result := mrRetry;
    idButtonIgnore: Result := mrIgnore;
    idButtonAll: Result := mrAll;
    idButtonYesToAll: Result := mrYesToAll;
    idButtonNoToAll: Result := mrNoToAll;
  else
    Result := mrCancel;  // closed with Escape or the window's X
  end;
end;
{$ENDIF}

function MessageDlg(const aCaption, aMsg: string; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons;
  HelpCtx: Longint): TModalResult;
{$IFDEF LCLGTK2}
var
  Ids: array of Longint;  // Ids: the buttons, in the LCL's order (left to right)
  B, Def: TMsgDlgBtn;  // B: a button; Def: the button Enter presses
  DefIndex: Integer;  // DefIndex: its place in Ids
{$ENDIF}
begin
  {$IFDEF LCLGTK2}
  if (Buttons = []) or (Buttons = [mbHelp]) then Buttons := Buttons + [mbOK];  // as the LCL does
  Def := DefaultButtonOf(Buttons);
  Ids := nil;
  DefIndex := 0;
  for B := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if B in Buttons then
    begin
      if B = Def then DefIndex := Length(Ids);
      SetLength(Ids, Length(Ids) + 1);
      Ids[High(Ids)] := ButtonIds[B];
    end;
  Result := ResultOf(DefaultPromptDialog(aCaption, LineBreaksToSystemLineBreaks(aMsg), DialogIds[DlgType],
    @Ids[0], Length(Ids), DefIndex, idButtonCancel, True, 0, 0));  // the LCL's own window: Yes on the left
  {$ELSE}
  Result := Dialogs.MessageDlg(aCaption, aMsg, DlgType, Buttons, HelpCtx);  // Windows: already Yes on the left
  {$ENDIF}
end;

procedure OkFirst(D: TCommonDialog);
begin
  {$IFDEF LCLGTK2}
  if D = nil then Exit;
  if OkFirstHelper = nil then OkFirstHelper := TOkFirstHelper.Create;
  D.OnShow := @OkFirstHelper.DialogShow;
  {$ELSE}
  if D = nil then Exit;  // Windows: Open/Save is on the left already
  {$ENDIF}
end;

function MessageDlg(const aMsg: string; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons;
  HelpCtx: Longint): TModalResult;
begin
  {$IFDEF LCLGTK2}
  Result := MessageDlg(Application.Title, aMsg, DlgType, Buttons, HelpCtx);
  {$ELSE}
  Result := Dialogs.MessageDlg(aMsg, DlgType, Buttons, HelpCtx);
  {$ENDIF}
end;

{$IFDEF LCLGTK2}
finalization
  OkFirstHelper.Free;
{$ENDIF}
end.
