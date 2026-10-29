# Plug-in libraries: interface version 1

Photo Downloader can load plug-in libraries: a **DLL** on Windows, a **.so** file on Linux. A library adds tokens to the folder and file name templates, and can ask for values in a window that Photo Downloader draws from the library's field list, so the library needs no window code. Only plain C types are used, so a library can be written in any language that can export C functions (Free Pascal, C, C++, Rust ...).

The program side is `uPlugins.pas` (loading, tokens, stored values) and `TPluginPromptForm` in `uDialogs.pas` (the window).

## Where libraries are found

| System | File | Folders searched |
|---|---|---|
| Windows | `name.dll` (64-bit) | `%LOCALAPPDATA%\Photo Downloader\plugins\`, then `plugins\` next to the program |
| Linux | `libname.so` or `name.so` (64-bit) | `~/.config/Photo Downloader/plugins/`, then `plugins/` next to the program |

The key of a library is its file name without `lib` prefix and extension (`folder_names.dll` and `libfolder_names.so` are both `folder_names`). It is the name in `[Plugins]` and `[PluginOpts]` of the settings file. Each system needs its own build of the library; cross compiling Windows <-> Linux is not used.

## Safety

- A new library is listed on the Plug-ins tab **switched off and not loaded**. Nothing of it runs until the user switches it on and confirms a message that shows its full path.
- A library runs with the user's rights, and a crash in it stops the whole program. Only install libraries you trust.
- Libraries are never loaded from the image source (memory card).
- If a switched-on library cannot be loaded (missing, 32-bit, other interface version), it is **switched off** and the user is told why.

## Rules for every function

- Calling convention `cdecl`; text is UTF-8 and ends with a `#0` byte.
- The **program owns every buffer**. A text function writes at most `BufLen - 1` bytes plus `#0` and **returns the full length it needs**. When that is larger than the buffer, the program calls again with a larger buffer. `Buf = nil` asks only for the length.
- Data goes both ways as **key=value lines** (separated by line feeds). Unknown keys are ignored, so new keys never break older libraries.
- Functions must not keep pointers to the program's text after they return, and must not raise exceptions across the boundary.

## Exported functions

| Function | Required | Purpose |
|---|---|---|
| `int pd_api_version(void)` | yes | Returns `1`. A library with another number is refused. |
| `int pd_info(char *buf, int bufLen)` | yes | Information lines (below). |
| `int pd_token(const char *token, const char *context, char *buf, int bufLen)` | yes | Value of one token; `-1` = no value (the token stays in the name as written, for example `{UAS}`, so a missing value is visible). |
| `int pd_check(const char *values, char *buf, int bufLen)` | no | Checks the values in the prompt window (below). |
| `int pd_logo(unsigned char *buf, int bufLen)` | no | A PNG logo. Returns its size; copies it when `bufLen` is at least that size. Shown at its own size (never scaled) on a white background at the top of the prompt window, and on the Plug-ins tab while the plug-in is switched on. |

## pd_info lines

| Key | Meaning |
|---|---|
| `Name`, `Version`, `Description` | shown on the Plug-ins tab |
| `Tokens` | token names, separated by `;` (for example `UAS;UAS.Dist`). They are used only when no built-in token has the same name. |
| `Title` | title of the prompt window |
| `AccentColor` | `RRGGBB`: a color bar under the logo |
| `FontName` | font of the prompt window (used when it is installed) |
| `ParseFolder=1` | the window gets a **Destination folder...** button: it opens in the destination (the download folder template up to its first token), and the chosen path is sent as `_parse` |
| `Field=key\|kind\|label\|entries\|default\|flags` | one row of the prompt window; may appear many times. `kind` is `choice` (list only), `combo` (list or typed text) or `text`. `entries` are separated by `,`; each is `value` or `value:label` (the label is shown, the value is stored). `flags` (optional): `upper` = typed text is shown and kept in capitals. |

## pd_token context

The stored values of the prompt window (`key=value`), plus details of the file:

| Key | Example |
|---|---|
| `FileName` | `DJI_0001.JPG` |
| `Ext` | `.jpg` (lower case, with the dot) |
| `IsVideo` | `1` for a video |
| `Camera`, `Serial` | camera model and serial number |
| `Date` | capture date `yyyymmdd` |

## pd_check

Called on every change in the prompt window with the current values, plus `_changed=<key>` (the field changed last) and, after **Destination folder...**, `_parse=<full path of the chosen folder>`. It returns lines:

| Key | Meaning |
|---|---|
| `Preview` | text shown in bold under the fields |
| `Error` | text shown in red; while it is not empty, **OK** is disabled |
| `Set.<key>` | a value the window shows in that field now (for example a district filled in from a county) |
| `Value.<key>` | the normalized value that is stored on OK (for example `95` stored as `0095`) |

The window is as wide as its longest label and the controls need (at least 600 pixels, and wide enough for the logo).

## When the program asks

- **Download**: before a download that the user started (not with automation), every switched-on library with fields shows its window, in the order of the Plug-ins list. **Cancel** stops the download before anything is copied. When the values changed, the folder and file names are worked out again first.
- **Preferences > Plug-ins > Setup...** shows the same window.
- The values are kept in `[PluginOpts]` as `key=value;key=value` (`%` and `;` escaped as `%25` and `%3B`).

## Not in version 1 yet

Hooks that run code after each file or after the download (`pd_run`), see `docs/Plugin_Plan.md`. They will be optional exports, so version 1 libraries keep working.
