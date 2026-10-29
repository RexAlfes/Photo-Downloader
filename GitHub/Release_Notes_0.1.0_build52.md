## Photo Downloader 0.1.0 – Build 52

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **WebP pictures.** `.webp` files are now listed, copied and previewed. The program decodes them itself (lossy, lossless and transparent files; transparent areas show on white; animated files show their first frame), so no extra library is needed on Windows or Linux.
- **Start-up splash screen.** Appears immediately, stays at least 5 seconds unless clicked, then closes when the program is ready.
- **Pictures are recognized by content, not file name.** A JPEG named `.png`, a TIFF named `.jpg`, a WebP named `.jpg` and similar mix-ups now open correctly.
- **Damaged PNG files.** PNG files whose checksums are wrong (some oscilloscope and screen-capture tools write these) are repaired in memory and now show.

### Other changes
- Files that are not pictures at all (for example a text file named `.jpg`) are logged as "not an image (text file)". The viewer shows "Sorry, viewer can't open this file because the format is currently unsupported, or the file is corrupted".
- WebP added to View > File Types.
- Project output goes to `bin/<OS>/`; compiler hints 5023 and 5024 are muted.
- Tested: delete to the Windows Recycle Bin, and a default destination per Windows user.

### Downloads
- `PhotoDownloader.0.1.0.build.52.win64.exe` – Windows 64-bit
- `PhotoDownloader.0.1.0.build.52.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)

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
