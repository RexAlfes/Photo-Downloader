---
title: "Photo Downloader – Plug-in Developer Manual"
subtitle: "Writing plug-in libraries (interface version 1)"
---

# 1. What a plug-in library can do

Photo Downloader can load plug-in libraries: a **DLL** on Windows, a **.so** file on Linux. A library can:

- add **tokens** to the folder and file name templates (for example `{Example.Site}`), which work like the built-in tokens `{Y}`, `{J}`, `{E}` …;
- describe a **window** with fields (lists, text boxes, check boxes) that Photo Downloader draws and shows before each download and from **Setup…**, so the library needs no window code;
- check the values in that window, fill in values for the user, and show a preview and error text;
- show a **logo**, a **reminder note** and its **version** in that window;
- suggest a **folder layout** under a destination folder the user chooses, and let check boxes add or remove the last folder of the download path.

Only plain C types cross the boundary between program and library, so a library can be written in any language that can export C functions: Free Pascal, C, C++, Rust and others.

A plug-in can also be a **program plug-in**: a small `.plugin.ini` text file that names an existing program to run on each downloaded file (section 7), with no code to write. Plug-in libraries cannot yet run code after each file; see `docs/Plugin_Plan.md`.

# 2. Your first plug-in in five steps

The repository contains a complete, working example: `plugins/example/example_plugin.lpr`. It gives two tokens:

- `{Example.Name}`: the original file name in capitals, without the extension;
- `{Example.Site}`: a site name typed into the window.

**Step 1: build it.** Free Pascal 3.2.2 is installed with Lazarus.

| System | Command | Result |
|---|---|---|
| Windows | `fpc -B example_plugin.lpr` | `example_plugin.dll` |
| Linux | `fpc -B -Cg example_plugin.lpr` | `libexample_plugin.so` |

Build on the system the library is meant for. Each system needs its own build, and cross compiling Windows <-> Linux is not used. Libraries must be 64-bit, like the program.

**Step 2: install it.** Copy the file into a `plugins` folder:

| System | Folders searched, in this order |
|---|---|
| Windows | `%LOCALAPPDATA%\Photo Downloader\plugins\`, then `plugins\` next to `PhotoDownloader.exe` |
| Linux | `~/.config/Photo Downloader/plugins/`, then `plugins/` next to the program |

**Step 3: switch it on.** Start Photo Downloader and open **File > Plug-ins…** (the Plug-ins tab of Preferences). The library is listed as **example_plugin (library) - disabled**. Select it, tick **Enable plug-in** and confirm the message that shows its path. The list now shows **Example Plug-in**, and the text below names its tokens.

**Step 4: give it a value.** Click **Setup…**. The window shows the field **Site name**, the red reminder and a preview. **OK** stays disabled until a site name is entered.

**Step 5: use the tokens.** On the Download Path tab, set the file name to `{Example.Site}-{Example.Name}`. The **Example image** line shows the result, for example `NORTH-DJI_0001.JPG`.

# 3. How a library is built

## 3.1 The rules for every function

- Calling convention **cdecl**; every exported name is in lower case.
- Text is **UTF-8** and ends with a `#0` byte.
- **The program owns every buffer.** A text function writes at most `BufLen - 1` bytes plus `#0` and **returns the full length it needs**. When that is larger than the buffer, the program calls again with a larger buffer. `Buf = nil` asks only for the length. The example's `PutText` function does all of this; copy it.
- Data goes both ways as **key=value lines**, separated by line feeds. Unknown keys are ignored, so new keys never break older libraries.
- A function must not keep pointers to the program's text after it returns, and must not let an exception (or a C++ throw, or a Rust panic) leave the function.
- The library must not show windows or message boxes of its own.

## 3.2 Exported functions

| Function | Required | Purpose |
|---|---|---|
| `int pd_api_version(void)` | yes | Returns `1`. A library with another number is refused. |
| `int pd_info(char *buf, int bufLen)` | yes | Information lines (section 3.3). |
| `int pd_token(const char *token, const char *context, char *buf, int bufLen)` | yes | Value of one token; `-1` = no value. The token then stays in the name as written (for example `{Example.Site}`), so a missing value is visible. |
| `int pd_check(const char *values, char *buf, int bufLen)` | no | Checks the values in the window (section 3.5). |
| `int pd_logo(unsigned char *buf, int bufLen)` | no | A PNG logo. Returns its size; copies it when `bufLen` is at least that size. |

The same functions in C:

```c
#define EXPORT __declspec(dllexport)   /* Windows; on Linux use __attribute__((visibility("default"))) */
EXPORT int pd_api_version(void) { return 1; }
EXPORT int pd_info(char *buf, int bufLen);
EXPORT int pd_token(const char *token, const char *context, char *buf, int bufLen);
EXPORT int pd_check(const char *values, char *buf, int bufLen);
EXPORT int pd_logo(unsigned char *buf, int bufLen);
```

## 3.3 pd_info lines

| Key | Meaning |
|---|---|
| `Name`, `Version`, `Description` | Shown on the Plug-ins tab. The version is also shown in the title bar and at the top right of the window. |
| `Tokens` | Token names, separated by `;` (for example `Example.Name;Example.Site`). They are used only when no built-in token has the same name. Give them a common prefix. |
| `Title` | Title of the window. |
| `Note` | A reminder, shown centered in red under the fields. |
| `AccentColor` | `RRGGBB`: a color bar under the logo. |
| `FontName` | Font of the window (used when it is installed). |
| `DestFolder=1` | The window shows the download folder (**Download to:**) and a **Destination folder…** button to choose the folder to download to. |
| `DestTemplate` | The folders the library suggests below the chosen destination, for example `{ABC}\{d}-{J}\`. |
| `Field=key\|kind\|label\|entries\|default\|flags` | One row of the window. May appear many times; the rows keep this order. |

**Fields:**

| Part | Meaning |
|---|---|
| `key` | name of the value (for example `Site`) |
| `kind` | `choice` (list only), `combo` (list or typed text), `text` (typed text) or `check` (a check box; value `1` or `0`) |
| `label` | text in front of the field (right-aligned); for a check box, its text |
| `entries` | list entries separated by `,`; each is `value` or `value:label` (the label is shown, the value is stored) |
| `default` | value used before anything is stored |
| `flags` | optional, separated by `,`: `upper` = typed text is shown and kept in capitals; `folder=A;B;C` (check boxes only) = while checked, `{A}` is the last folder of the download path. `{A}`, `{B}`, `{C}` at the end of the path are removed first, so the box replaces an older last folder (for example `{E}`). |

**Destination folder:** after the user chooses a folder, the download path becomes that folder plus the token part of the current path when that still holds the first token of `DestTemplate` (so the user's own layout is kept), otherwise plus `DestTemplate`. When the window opens, a download path without that token is put back to the destination plus `DestTemplate`. Then the check boxes with `folder=` add or remove their last folder. On **OK** the new path is saved and shown on the Download Path tab.

## 3.4 pd_token context

The stored values of the window (`key=value`), plus details of the file:

| Key | Example |
|---|---|
| `FileName` | `DJI_0001.JPG` |
| `Ext` | `.jpg` (lower case, with the dot) |
| `IsVideo` | `1` for a video |
| `Camera`, `Serial` | camera model and serial number |
| `Date` | capture date `yyyymmdd` |
| `Path` | full path of the file on the source (empty for the Example line), so a library can read the file itself, for example to tell thermal from color pictures |
| `Size` | file size in bytes (with `Path` a good key for remembering what was read) |

Tokens are asked for often: for the Example line, for every file after a scan (to find files already downloaded) and for every download. Keep `pd_token` fast. If it reads the file (`Path`), read only the start or the header, and remember the answer by path and size, so each file is read once. No network access.

## 3.5 pd_check

Called on every change in the window with the current values, plus `_changed=<key>` (the field changed last). It returns lines:

| Key | Meaning |
|---|---|
| `Preview` | text shown in bold under the fields |
| `Error` | text shown in red; while it is not empty, **OK** is disabled |
| `Set.<key>` | a value the window shows in that field now (for example a district filled in from a county) |
| `Value.<key>` | the normalized value stored on OK (for example `95` stored as `0095`) |
| `Invalid.<key>` | `1` = that field breaks its rule: its box is shown light red with dark red text until it is right |

Do not send `Set.` for a text field the user is typing in; the cursor would jump. Use `Value.` to store the cleaned-up text instead.

## 3.6 The logo

`pd_logo` returns a PNG. It is shown at its own size (never scaled) on a white background with 18 pixels of space around it, and on the Plug-ins tab while the plug-in is switched on. Make the PNG at the size it should appear (for example 260 x 60 pixels). Use a logo only when you may: many organizations have rules for their logo.

# 4. When the program asks for values

- **Download:** before a download the user started with **Download Selected** or **Download All** (not with automation), every switched-on library with fields shows its window, in the order of the Plug-ins list. **Cancel** stops the download before anything is copied. When the values or the download path changed, the folder and file names are worked out again first.
- **Preferences > Plug-ins > Setup…** shows the same window.
- The values are kept in the settings file, `[PluginOpts]`, as `key=value;key=value` (`%` and `;` written as `%25` and `%3B`). User profiles are copies of the settings file, so they keep the values, the on/off state and the order of the plug-ins too.

# 5. Safety

- A new library is listed **switched off and not loaded**. None of its code runs until the user switches it on and confirms a message that shows its full path.
- A library runs with the user's rights, and a crash in it stops the whole program. Users should only install libraries they trust.
- Libraries are never loaded from the image source (memory card).
- If a switched-on library cannot be loaded (32-bit, wrong system, other interface version), it is **switched off** and the user is told why, after the start-up screen.
- A library whose file was deleted leaves the Plug-ins list at the next start (logged). Its values stay in `[PluginOpts]` for a later reinstall. A library that is installed but missing from a loaded user profile is added to the list, switched off.

# 6. Testing a library

- Write a small test program that loads the library (`LoadLibrary` / `dlopen`) and calls the functions with known contexts. That is quicker than clicking through the program and catches buffer mistakes.
- Call each text function once with a small buffer (for example 40 bytes) and check that the text is cut off cleanly, with a closing `#0`.
- In Photo Downloader, check the **Example image** line on the Download Path tab, then download a few files to a test folder.
- **Help > Logging** writes `plug-in <name>: loaded <path>` or the reason a library was switched off into the log.

# 7. Program plug-ins (.plugin.ini)

A program plug-in runs an existing program (for example a DNG converter) on each downloaded file. Nothing is compiled: the plug-in is a text file `<key>.plugin.ini` in a plugins folder (the same folders as for libraries). The program runs as a separate process, started directly without a shell, with its arguments passed one by one, so a file name can never start another command. Examples: `plugins/dng-converter/adobe_dng_converter.plugin.ini` and `dnglab.plugin.ini`.

```ini
[Plugin]
Name=DNG Converter (dnglab)
Description=Makes a DNG copy of each downloaded raw file. The raw file is kept.
Version=1.0.0
Hook=AfterFile
FileTypes=.nef;.cr2;.arw
Platforms=windows;linux

[Run]
Windows=dnglab.exe
Linux=dnglab
Args=convert "{file}" "{folder}{sep}{name}.dng"
Output={folder}{sep}{name}.dng
TimeoutSec=300
```

| Key | Meaning |
|---|---|
| `Name`, `Description`, `Version` | shown on the Plug-ins tab |
| `Hook` | when it runs; `AfterFile` (after each downloaded file) is the only one so far |
| `FileTypes` | extensions it works on, separated by `;` (empty = every file) |
| `Platforms` | `windows`, `linux` or both (empty = both); the plug-in is not offered on other systems |
| `Windows`, `Linux` | the program on each system: a full path, or a bare name that is looked up on the PATH. The user can choose another path with **Setup...** (stored as `Program=` in `[PluginOpts]`) |
| `Args` | the arguments; double quotes keep a path with blanks together |
| `Output` | optional: the file the program makes. If it already exists, the step is skipped; if it is missing afterwards, the step failed |
| `TimeoutSec` | the program is stopped after this many seconds (failed); default 300 |

**Placeholders** in `Args` and `Output`: `{file}` the downloaded file, `{folder}` its folder (without a closing separator), `{name}` its name without extension, `{ext}` its extension without the dot, `{source}` the original file on the card, `{sep}` the folder separator of the system (`\` or `/`).

**Result:** exit code 0 is success; any other exit code, a missing `Output` file, a timeout or a missing program is a failure. Up to 300 characters of what the program printed are shown in the message and the log. A failed step switches the plug-in off and keeps the original on the card (not offered for deletion). Steps run on the downloaded copy only, never on the backup copy or the original.

**Switching on** a program plug-in shows the program and its arguments and asks for confirmation; it cannot be switched on while its program is not found.

# 8. The program side (for Photo Downloader developers)

`uPlugins.pas` finds and loads libraries and `.plugin.ini` files (`uExtPlugin.pas` reads and runs those), keeps their information and answers plug-in tokens through `uItems.PluginTokenHook`. `TPluginPromptForm` in `uDialogs.pas` draws the window; `AskPluginValues` shows it before a download (`TMainForm.DoDownload`). `TMainForm.RunPluginSteps` runs the steps after each file (JPEG auto profile through `uIccEmbed.pas`, program plug-ins through `uExtPlugin.pas`).
