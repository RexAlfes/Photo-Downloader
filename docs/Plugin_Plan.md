# Plug-in system: plan

Status: **plug-in libraries (DLL / .so) with tokens and a prompt window are built** (interface: `docs/Plugin_Developer_Manual.md`). Hooks that run code after each file or after the download, the move of Directory Maker and external-program plug-ins are still open. The decisions from the first review are in section 2. The first library is a private, organization-specific folder-naming plug-in; it is not part of this repository.

## 1. Where things stand

- Preferences > Plug-ins lists the built-in names from `uSettings.DefaultPlugins`: JPEG auto profile, Directory Maker, DNG Converter, JPEG resolution. Each can be switched on or off and moved up or down. Settings live in `[Plugins]` (`Name=0/1`) and `[PluginOpts]` (`Name=value`).
- The **Backup** plug-in has been removed (the backup folder on the Download Path tab replaced it). An old `[Plugins] Backup=` line is dropped when the settings are read.
- Only **Directory Maker** does anything. Its code sits in `TMainForm` (the post-download steps in `uMain.pas`), and its info text is an `if` chain in `TPrefsForm.PluginSelect`.
- The order in the list has no effect yet.

## 2. Decisions (first review)

| # | Question | Decision |
|---|---|---|
| 1 | A plug-in step fails | The file is **not offered for deletion** from the source (the same as a failed backup), **and the plug-in is switched off** (saved in the settings) with a message naming the plug-in and the reason. It must be switched on again on the Plug-ins tab after the cause is fixed. The rest of the download continues. |
| 2 | JPEG resolution | Built later (build 12): it sets the DPI or dots/cm of downloaded JPEGs without touching the image data (no resizing). |
| 3 | DNG Converter | Keep **both** the raw file and the DNG. |
| 4 | Native library plug-ins | **Yes**: DLL on Windows and .so on Linux (section 7). |
| 5 | Plug-ins and the backup copy | **Never.** Plug-ins do not touch the backup copy; the backup always holds the untouched original. |
| 6 | First plug-in | A private, organization-specific folder-naming plug-in (tokens for an agency folder naming standard). Built as a separate library and handed out as needed; its source and spec are kept outside this repository. |

## 3. Goals

1. A plug-in is a self-contained step with a name, a description, its own options and its own Setup.
2. The download code calls plug-ins at fixed points (hooks) instead of naming them.
3. Plug-ins can **add tokens** that work in the folder and file name templates like the built-in tokens.
4. The list order sets the run order.
5. Every plug-in result is logged, and a failure is never silent.
6. Windows and Linux both work, with no change to the single-exe, no-installer approach. Organization-specific plug-ins stay out of the general program.

## 4. Kinds of plug-ins

| Kind | What it is | Use |
|---|---|---|
| **A. Built-in** | A Pascal class compiled into the exe (one unit per plug-in) | Directory Maker, JPEG auto profile, JPEG resolution |
| **B. External program** | A manifest file (`<name>.plugin.ini`) in the `plugins` folder that describes a command line to run | DNG Converter, exiftool, ImageMagick and other tools |
| **C. Native library** | A DLL (Windows) or .so (Linux) in the `plugins` folder with a small C-style interface (section 7) | Organization-specific plug-ins; plug-ins from other developers |

All three kinds look the same to the rest of the program: the registry in `uPlugins.pas` wraps B and C in the same class as A.

## 5. Hooks (where plug-ins run)

| Hook | When | Example |
|---|---|---|
| `Tokens` | whenever a template is expanded (the Example line, the planned names after a scan, the download) | a folder-naming plug-in: `{ABC}`, `{ABC.Part}` ... |
| `Prompt` | once, when the download starts or when the job code is asked; the host shows fields the plug-in describes | project numbers that make up a folder name |
| `BeforeDownload` | once, before the first file is copied | check that an external tool exists |
| `AfterFile` | after each file is copied, verified, backed up, auto-rotated and has its XMP written, **before** the read-only flag is set | DNG conversion, embed a color profile |
| `AfterDownload` | once, after the last file (also after Cancel, with the count done) | Directory Maker (once per destination folder) |

The backup copy is made from the verified download before any `AfterFile` plug-in runs and is never passed to a plug-in.

Tokens from plug-ins are looked up only when no built-in token has that name, so a plug-in cannot change a built-in token. A token of a plug-in that is switched off stays as literal text (like an unknown token today), so a template never silently loses a folder level.

## 6. Built-in plug-in interface (sketch)

New unit `uPlugins.pas`:

```pascal
type
  TPluginHook = (phTokens, phPrompt, phBeforeDownload, phAfterFile, phAfterDownload);
  TPluginHooks = set of TPluginHook;

  TPluginContext = record
    Settings: TAppSettings;   // all settings, including PluginOpts
    Item: TImageItem;         // the file (nil for the once-per-download hooks)
    SourcePath: string;       // original file on the card
    DestPath: string;         // the downloaded file
    DestDirs: TStrings;       // AfterDownload: every destination folder used
  end;

  TPluginResult = (prOk, prSkipped, prFailed);

  TPhotoPlugin = class
    function Name: string; virtual; abstract;          // also the key in [Plugins] / [PluginOpts]
    function Description: string; virtual; abstract;   // text on the Plug-ins tab
    function Hooks: TPluginHooks; virtual; abstract;   // where it runs
    function Handles(Item: TImageItem): Boolean; virtual;         // file types it works on (default: all)
    function TokenNames: string; virtual;                        // e.g. 'UAS;UAS.RP;UAS.Dist'
    function TokenValue(const Tok: string; Item: TImageItem; out Value: string): Boolean; virtual;
    function PromptFields: string; virtual;                      // field list for the host's prompt window
    function Setup(AOwner: TComponent; var Opts: string): Boolean; virtual;
    function Run(Hook: TPluginHook; const Ctx: TPluginContext; out Msg: string): TPluginResult; virtual;
  end;
```

- The Plug-ins tab is filled from the registry; `DefaultPlugins` and the `if` chain in `PluginSelect` go away.
- `RunPlugins` walks `[Plugins]` in the saved order and runs every enabled plug-in that has the hook and handles the file. It logs `plug-in <name>: <file>: <Msg>`.
- On `prFailed`: log, count, mark the file as not deletable from the source, switch the plug-in off in the settings, save, and tell the user once at the end of the download.
- Options stay one string per plug-in in `[PluginOpts]` (compatible with today's Directory Maker value); plug-ins that need more store `key=value;key=value` in it, or their own section `[Plugin.<Name>]`.

## 7. Native library plug-ins (DLL / .so)

Free Pascal strings, objects and memory managers cannot cross a library boundary safely, and plug-ins may be written in other languages. The interface therefore uses only plain C types:

- Calling convention `cdecl` on both systems; 64-bit only.
- Text is UTF-8 `PAnsiChar`. Data goes both ways as **key=value lines** (`#10` separated), so no record layouts have to match and new keys never break old plug-ins.
- The host always owns the memory: it passes a buffer and its size; the plug-in returns the length it needs. If the buffer is too small, the host calls again with a bigger one.
- An interface version number lets the host refuse a library built for a newer interface.

Exported functions (draft):

```c
int  pd_api_version(void);                                   // returns 1
int  pd_info(char *buf, int bufLen);                         // Name=, Version=, Description=, Hooks=, Tokens=, Fields=...
int  pd_token(const char *token, const char *context,       // context: key=value lines about the file and the prompt values
              char *buf, int bufLen);                        // returns length, or -1 = unknown token
int  pd_run(int hook, const char *context,                  // returns 0 = OK, 1 = skipped, 2 = failed
            char *msg, int msgLen);
void pd_setup(const char *opts, char *buf, int bufLen);     // optional; returns new options
```

- The **prompt window is drawn by the host** from the field list in `pd_info` (field name, label, kind: choice / text / number, allowed values, pattern, default). So a library needs no user interface code, which avoids putting the LCL inside a DLL.
- Files: `plugins/<name>.dll` (Windows) or `plugins/lib<name>.so` (Linux), in the folder next to the settings file, or next to the exe for a portable copy. Each system needs its own build of the library.
- Safety: a library runs with the user's rights and a crash in it stops the whole program. A new library appears in the list **switched off**; the first time it is switched on, a confirmation shows its full path. Libraries are never loaded from the source card.
- Linux: loaded with `dynlibs.LoadLibrary`; the same unit works on Windows.

## 8. External-program plug-ins (sketch)

A manifest `<name>.plugin.ini` in the `plugins` folder:

```ini
[Plugin]
Name=DNG Converter
Description=Converts raw files to DNG with Adobe DNG Converter (the raw file is kept).
Hook=AfterFile
FileTypes=.nef;.nrw;.cr2;.cr3;.arw;.orf;.rw2;.raf
Platforms=windows

[Run]
Windows=C:\Program Files\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe
Args=-c -d "{folder}" "{file}"
TimeoutSec=300
```

- `Args` takes `{file}`, `{folder}`, `{source}`, `{name}` and every naming token. The same placeholders can later replace `%f` / `%d` of the Custom Button.
- Exit code 0 = OK, anything else = failed; the program's output goes to the log.
- Programs are started without a shell (`TProcess` with separate arguments), so a file name cannot inject a command.
- A new manifest appears switched off; the first time it is switched on, a confirmation shows the exact program path and arguments.

## 9. Plan by phase

| Phase | Work | Test |
|---|---|---|
| 0 | Backup plug-in removed (done). | Old settings files load without it. |
| 1 | **Done:** plug-in tokens and the host-drawn prompt (`uPlugins.pas`, `TPluginPromptForm`). **Open:** registry for built-in plug-ins and run hooks; move Directory Maker into `uPluginDirMaker.pas` (`AfterDownload`). Fill the Plug-ins tab from the registry. Failure rules of decision 1. | Directory Maker makes the same folders as today; order and on/off survive a restart; a test plug-in that fails is switched off and its files are not offered for deletion. |
| 2 | **Done (Windows tested, Linux not tested yet):** native library loader (section 7, details in `docs/Plugin_Developer_Manual.md`). Open: a small public example library. | Example library loads, gives a token, fails on request; a library with a newer interface version is refused. |
| 3 | First library: a private folder-naming plug-in (kept outside this repository). | Done on Windows: its test program passes; Linux build untested. |
| 4 | **Done:** external-program plug-ins (`uExtPlugin.pas`, `.plugin.ini`), run after each file with the failure rules of decision 1; two DNG Converter plug-ins (Adobe, dnglab) in `plugins/dng-converter`. | Tested with a stand-in program: DNG made, skipped when it exists, exit code, timeout, missing program. Tested on Windows with the real converters (dnglab 0.8.0 and Adobe DNG Converter 18.7) on Nikon and Canon raw files: valid DNGs, raw files kept, second run skipped. Both also worked inside a real download in the program, and a failed step kept the file and switched the plug-in off (build 9); dnglab also tested on Linux (GTK 2) by the user (build 12). |
| 5 | **Done:** JPEG auto profile (built-in; `uIccEmbed.pas` writes APP2 ICC segments without re-encoding; one profile per camera model and a default). | Profiles of 560 bytes and 557 KB (9 segments) embedded; profile bytes and picture data checked; the JPEG still decodes. |
| later | Hooks for plug-in libraries (`pd_run`). JPEG resolution is done (build 12, `uJpegDpi.pas`). | |

Each phase is a separate commit; the manual (Plug-ins section), spec, Settings_File.md and the website are updated with each one.
