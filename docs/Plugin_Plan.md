# Plug-in system: planning draft

Status: **draft for discussion**. No code has been written yet. The open questions at the end need answers before work starts.

## 1. Where things stand

- Preferences > Plug-ins lists five fixed names from `uSettings.DefaultPlugins`: JPEG auto profile, Backup, Directory Maker, DNG Converter, JPEG resolution. Each can be switched on or off and moved up or down. Settings live in `[Plugins]` (`Name=0/1`) and `[PluginOpts]` (`Name=value`).
- Only **Directory Maker** does anything. Its code is written straight into `TMainForm` (the post-download steps in `uMain.pas`), and its info text is an `if` chain in `TPrefsForm.PluginSelect`.
- **Backup** was replaced by the backup folder on the Download Path tab and is still listed.
- The order in the list has no effect yet.

## 2. Goals

1. A plug-in is a self-contained step with a name, a description, its own options and its own Setup dialog.
2. The download code calls plug-ins at fixed points (hooks) instead of naming them.
3. The list order sets the run order.
4. Every plug-in result is logged, and a failure is never silent.
5. Windows and Linux both work, with no change to the single-exe, no-installer approach.

## 3. Kinds of plug-ins (recommendation)

| Kind | What it is | Recommendation |
|---|---|---|
| **A. Built-in** | A Pascal class compiled into the exe (one unit per plug-in), registered in a list | **Yes.** Simple and safe, works on both systems, and has no version-matching problems. Directory Maker, JPEG resolution and JPEG auto profile belong here. |
| **B. External program** | A small text file (manifest) in a `plugins` folder describes a command line to run, for example Adobe DNG Converter, exiftool or ImageMagick | **Yes, second step.** Users can add tools without a new build of Photo Downloader, in any language. DNG Converter belongs here. |
| C. Native library | DLL / .so files loaded at run time | **Not now.** Free Pascal strings and memory do not cross library boundaries safely, Windows and Linux need separate builds, and a bad library crashes the program. Revisit only if other developers ask for it. |
| D. Script language | Embedded Lua or Pascal Script | **Not now.** It adds a large dependency for little gain over B. |

## 4. Hooks (where plug-ins run)

| Hook | When | Example |
|---|---|---|
| `BeforeDownload` | once, before the first file is copied | check that an external tool exists; ask a question |
| `AfterFile` | after each file is copied, verified, backed up, auto-rotated and has its XMP written, **before** the read-only flag is set | DNG conversion, embed a color profile, make a resized copy |
| `AfterDownload` | once, after the last file (also after Cancel, with the count done) | Directory Maker (once per destination folder instead of once per file), a summary |

The backup copy is made from the verified download before any `AfterFile` plug-in runs, so the backup always holds the untouched original (the same rule as today for rotation and metadata).

## 5. Built-in plug-in interface (sketch)

New unit `uPlugins.pas`:

```pascal
type
  TPluginHook = (phBeforeDownload, phAfterFile, phAfterDownload);
  TPluginHooks = set of TPluginHook;

  TPluginContext = record
    Settings: TAppSettings;   // all settings, including PluginOpts
    Item: TImageItem;         // the file (nil for BeforeDownload / AfterDownload)
    SourcePath: string;       // original file on the card
    DestPath: string;         // the downloaded file
    DestDirs: TStrings;       // AfterDownload: every destination folder used
  end;

  TPluginResult = (prOk, prSkipped, prFailed);

  TPhotoPlugin = class
    function Name: string; virtual; abstract;          // also the key in [Plugins] / [PluginOpts]
    function Description: string; virtual; abstract;   // text on the Plug-ins tab
    function Hooks: TPluginHooks; virtual; abstract;   // where it runs
    function Handles(Item: TImageItem): Boolean; virtual; // file types it works on (default: all)
    function Setup(AOwner: TComponent; var Opts: string): Boolean; virtual; // Setup... dialog
    function Run(Hook: TPluginHook; const Ctx: TPluginContext;
      out Msg: string): TPluginResult; virtual; abstract;
  end;

procedure RegisterPlugin(P: TPhotoPlugin);   // called from each plug-in unit's initialization
function PluginCount: Integer;
function PluginAt(I: Integer): TPhotoPlugin;
procedure RunPlugins(S: TAppSettings; Hook: TPluginHook; const Ctx: TPluginContext);
```

- The Plug-ins tab is filled from the registry. `DefaultPlugins` and the `if` chain in `PluginSelect` are no longer needed.
- `RunPlugins` walks `[Plugins]` in the saved order and runs every enabled plug-in that has the hook and handles the file. It logs `plug-in <name>: <file>: <Msg>`.
- Options stay one string per plug-in in `[PluginOpts]` (kept compatible with today's Directory Maker value). A plug-in that needs more can store `key=value;key=value` in that string.

## 6. External-program plug-ins (sketch)

A folder `plugins/` next to the settings file (also `plugins/` next to the exe for a portable copy). Each plug-in is one file, `<name>.plugin.ini`:

```ini
[Plugin]
Name=DNG Converter
Description=Converts raw files to DNG with Adobe DNG Converter.
Hook=AfterFile
FileTypes=.nef;.nrw;.cr2;.cr3;.arw;.orf;.rw2;.raf
Platforms=windows

[Run]
Windows="C:\Program Files\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe"
Args=-c -d "{folder}" "{file}"
Wait=1
TimeoutSec=300
```

- `Args` takes `{file}` (downloaded file), `{folder}` (its folder), `{source}` (original on the card), `{name}` (file name without extension) and **every naming token** (`{Y}`, `{J}`, `{E}` ...), so the token system is shared.
- The same placeholders can later replace `%f` and `%d` of the Custom Button (the spec already lists `{file}` and `{folder}` as open there).
- The exit code decides the result: 0 = OK, anything else = failed. The program's output goes to the log.
- Programs are started without a shell (`TProcess` with separate arguments), so a file name cannot inject a command.
- A new manifest appears in the list **switched off**. The first time it is switched on, a confirmation shows the exact program path and arguments.

## 7. Failure rules (proposal)

- A failed plug-in never deletes or changes the source file, and never stops the rest of the download.
- The file is counted in the status line ("3 plug-in steps failed, see the log").
- Like a failed backup copy, a file whose plug-in step failed is **not offered for deletion** from the source (see question 1).

## 8. Plan by phase

| Phase | Work | Test |
|---|---|---|
| 1 | `uPlugins.pas` registry and hooks. Move Directory Maker into `uPluginDirMaker.pas` and run it at `AfterDownload`. Fill the Plug-ins tab from the registry. Drop the Backup entry (an old `[Plugins] Backup=` line is ignored). Log every result. | Directory Maker makes the same folders as today; order and on/off survive a restart; old settings files load. |
| 2 | External-program plug-ins: manifest reader, `plugins/` folder, placeholder expansion, `TProcess` run with timeout, first-enable confirmation. Ship `DNG Converter.plugin.ini` as an example (switched off). | A test manifest that copies the file; DNG Converter on Windows; a failing exit code; a timeout. |
| 3 | JPEG resolution (built-in): longest side and quality as options; writes a smaller copy (see question 2). EXIF is kept by copying the APP1 segment. | Sizes, orientation, EXIF kept, original untouched. |
| 4 | JPEG auto profile (built-in): per-camera ICC profile file (Mapping-style list); inserts an APP2 ICC segment without re-encoding, like the lossless auto-rotate. | Profile shows in an image viewer that reads ICC; picture data unchanged (MD5 of the scan data). |

Each phase is a separate commit, and the docs are updated with each one: manual (Plug-ins section), spec, Settings_File.md and the website.

## 9. Open questions

1. **Failure and source deletion.** Should a failed plug-in step keep the file from being offered for deletion from the card? *Proposal: yes, the same as a failed backup.*
2. **JPEG resolution.** Should it replace the downloaded JPEG, or write a smaller copy (for example into a `Web` subfolder or with a suffix)? *Proposal: a copy; the full-size original stays.*
3. **DNG Converter.** Keep the raw file and the DNG, or the DNG only? *Proposal: both by default; "DNG only" as an option.*
4. **Native library plug-ins** (DLL / .so for other developers): wanted later, or never? *Proposal: not planned.*
5. **Plug-ins on the backup copy.** *Proposal: never. The backup stays the untouched original.*
6. **Which plug-in first** after the phase 1 groundwork: DNG Converter, JPEG resolution or JPEG auto profile?
