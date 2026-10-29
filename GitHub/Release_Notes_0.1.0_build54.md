## Photo Downloader 0.1.0 – Build 54

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **Name clashes can be renamed automatically.** New option on the File Handling tab: "Rename name clashes as (1), (2) ...". Files that would overwrite or collide are downloaded as `name (1).jpg`, `name (2).jpg` ... without a question (Windows-style numbering). With the option off, the program still asks, and adds -1, -2 ...
- **Duplicate files are easier to see.** Cards of duplicate files are now amber instead of normal gray.
- **Failed thumbnails are marked.** A gray placeholder gets a red X from corner to corner when the picture could not be rendered.
- **Image Date Selector scrolls** to the selected picture's date when that date is off screen.
- **Status window:** the settings file path is a link that opens its folder.
- **File Handling tab.** Preferences has a new tab between General and Automation that holds the file options in one column. The tab order is now Download Path, General, File Handling, Automation, Mapping, Custom Button, Plug-ins.
- **Duplicate handling.** "Ignore duplicate files on download" (default) or "Download duplicates as (1), (2) ...".
- **About box** shows the program icon.
- **Right-click menu:** "Show in source folder" and, for files already downloaded, "Show in destination folder".
- **User manual** added (`docs/User_Manual.md`).

### Other changes
- The source code is fully commented (American English). The commented code was checked to be identical to the earlier code.
- The log line "the decoder returned an empty picture" now includes the file size.
- Tested with a drive of about 50,000 image files.

### Downloads
- `PhotoDownloader.0.1.0.build.54.win64.exe` – Windows 64-bit
- `PhotoDownloader.0.1.0.build.54.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)

### Linux build
See `docs/Linux_Build.md`. You need Lazarus with the GTK2 or GTK3 widgetset, plus `udisks2`, `gio` and `xdg-open` at run time.

### Known limitations
- WebP: ICC color profiles are ignored; only the first frame of animations is shown.
- Single-instance handling is Windows only.
- Other Linux distributions and the Qt widgetset are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- Video and audio files are still in development and switched off by default.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
