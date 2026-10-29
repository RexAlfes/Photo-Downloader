## Photo Downloader 0.1.0 – Build 51

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **Linux build now tested.** The program builds and runs on Linux Mint 22.3 (XFCE 4.18, GTK 3.24, 64-bit). Working on Linux:
  - removable-drive detection
  - **Locate card reader**, which lists the drives it finds
  - eject
  - safe delete (hidden trash folder on cards, system trash on internal disks)
  - File > View Trash and Empty Trash
  - settings in `~/.config/PhotoDownloader/` and the thumbnail cache in `~/.cache/PhotoDownloader/`
  - the thumbnail grid, sortable headings and the viewer
- **Windows-safe file names.** New option in Preferences > General, shown on Linux only (Windows always applies it). It controls whether characters such as `: ? * " < > |` are replaced.
- **Progressive JPEG fix.** A variable mix-up in the decoder used for lossless auto-rotate could start decoding from the wrong position. Fixed and tested.

### Other changes
- Progress windows stay above the main window.
- The main window fits small screens such as 1366x768, with extra room for desktop panels on Linux.
- The Preferences General tab and its labels fit the window.
- Compiler hint clean-up in the program's own code.

### Downloads
- `PhotoDownloader.0.1.0.build.51.win64.exe` – Windows 64-bit
- `PhotoDownloader.0.1.0.build.51.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)

### Linux build
See `docs/Linux_Build.md`. You need Lazarus with the GTK2 or GTK3 widgetset, plus `udisks2`, `gio` and `xdg-open` at run time.

### Known limitations
- Single-instance handling is Windows only.
- Other Linux distributions and the Qt widgetset are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- Video and audio files are still in development and switched off by default.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
