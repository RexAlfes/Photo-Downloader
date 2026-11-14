{ MessageDlg with the same button order on every system: Yes (or OK) first, on the left.

  On Windows the LCL message box already shows the buttons in the order Yes, No, OK, Cancel. The GTK 2
  widgetset replaces it with GTK's own message box and adds the buttons back to front (GTK's habit:
  No, Yes), so on Linux Yes was on the right. Units list this unit after Dialogs, so their MessageDlg
  calls come here: on GTK 2 they use the LCL's own message window (DefaultPromptDialog, the same one
  other widgetsets use), elsewhere the normal MessageDlg.

  GTK's file windows (open, save, choose folder) show Cancel before Open/Save as well; OkFirst installs a
  GTK hook that moves the Open/Save button to the left whenever such a window is shown. }
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
  on GTK 2 it makes sure the GTK hook that moves the button is installed; elsewhere nothing. }
procedure OkFirst(D: TCommonDialog);

implementation

{$IFDEF LCLGTK2}
uses
  SysUtils, LCLType, LazStringUtils, Forms, glib2, gtk2;

const
  ResponseOk = -5;  // GTK_RESPONSE_OK: Open or Save, as the LCL creates its file windows
  ResponseAccept = -3;  // GTK_RESPONSE_ACCEPT: the same in file windows made by other code

var
  ShowHook: gulong = 0;  // the GTK emission hook on "show" (0 = not installed yet)

type
  { GTK keeps the response of a dialog button as object data "gtk-dialog-response-data". }
  PResponseData = ^TResponseData;
  TResponseData = record
    ResponseId: gint;
  end;

{ The response id of a dialog button (0 when it has none). }
function ButtonResponse(W: PGtkWidget): gint;
var
  D: PResponseData;  // D: GTK's data of the button
begin
  D := PResponseData(g_object_get_data(PGObject(W), 'gtk-dialog-response-data'));
  if D = nil then Result := 0 else Result := D^.ResponseId;
end;

{ Moves the Open/Save button of a GTK file window to the left of its button row. Finds it by its
  response, so calling it again changes nothing. With the environment variable PD_DEBUG_DIALOGS set,
  it reports on the terminal what it found. }
procedure OpenFirst(Dlg: PGtkDialog);
var
  Kids, P: PGList;  // Kids, P: the buttons of the button row
  W, Btn: PGtkWidget;  // W: a button; Btn: the Open/Save button
  Debug: Boolean;  // Debug: report on the terminal
  N: Integer;  // N: buttons seen
begin
  if (Dlg = nil) or (Dlg^.action_area = nil) then Exit;
  Debug := GetEnvironmentVariable('PD_DEBUG_DIALOGS') <> '';
  Kids := gtk_container_get_children(PGtkContainer(Dlg^.action_area));
  Btn := nil;
  N := 0;
  P := Kids;
  while P <> nil do
  begin
    W := PGtkWidget(P^.data);
    if Debug then WriteLn(StdErr, 'PD dialog button ', N, ': response ', ButtonResponse(W));
    if (ButtonResponse(W) = ResponseOk) or (ButtonResponse(W) = ResponseAccept) then Btn := W;
    Inc(N);
    P := P^.next;
  end;
  if Btn <> nil then gtk_box_reorder_child(PGtkBox(Dlg^.action_area), Btn, 0);  // first = leftmost
  if Debug then WriteLn(StdErr, 'PD dialog: ', N, ' buttons, Open/Save ', BoolToStr(Btn <> nil, 'moved to the left', 'not found'));
  g_list_free(Kids);
end;

{ GTK emission hook: called whenever a widget is shown; acts on file chooser windows only. }
function ShowEmitted(ihint: PGSignalInvocationHint; n_param_values: guint; param_values: PGValue;
  data: gpointer): gboolean; cdecl;
var
  Obj: gpointer;  // Obj: the widget being shown
begin
  Result := True;  // keep the hook
  if n_param_values < 1 then Exit;
  Obj := g_value_get_object(param_values);
  if (Obj <> nil) and G_TYPE_CHECK_INSTANCE_TYPE(Obj, gtk_file_chooser_dialog_get_type) then
    OpenFirst(PGtkDialog(Obj));
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
  // a GTK hook on "show" for every file chooser window (installed once, after GTK is running); it does not
  // depend on the dialog's OnShow, which did not move the button on the user's Linux computer
  if ShowHook = 0 then
    ShowHook := g_signal_add_emission_hook(g_signal_lookup('show', gtk_widget_get_type), 0,
      @ShowEmitted, nil, nil);
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

end.
