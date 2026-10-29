## Photo Downloader 0.1.0 – Build 56

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **New application icon with real transparency.** The old icon had solid white corners. The new one has transparent, smoothly edged corners and ten sizes (16 to 256 pixels), so it looks right on dark panels and taskbars, on Windows and Linux.
- **Linux: icon and menu entry.** The window and taskbar icon now show on Linux. A new launcher kit (`linux/install-desktop.sh`, `PhotoDownloader.desktop` and icons) adds Photo Downloader to the application menu with its icon (`docs/Linux_Build.md`).
- **Right-click menu:** new **Refresh** item (rescan the source). On Linux the check items show empty boxes and the three views show round radio marks.
- **Duplicate files:** with "Download duplicates as (1), (2) ...", the card shows the planned numbered name, and each duplicate decision (renamed or skipped, and why) is written to the log. The manual explains exactly when a number is added.
- **Linux Preferences:** the dialog is widened so all seven tabs fit on one row instead of showing scroll arrows.

### Other changes
- The User Manual (`docs/User_Manual.md` and `.odt`) explains the difference between a name clash and a duplicate file, how every status is decided, and how duplicates behave.
- Lazarus 4.8 / FPC 3.2.2 are now used on both Windows and Linux.

### Downloads
- `PhotoDownloader.0.1.0.build.56.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.0.build.56.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.0.build.56.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.0.build.56.odt` and `.md` – User Manual

### Linux build
See `docs/Linux_Build.md`. You need Lazarus with the GTK2 or GTK3 widgetset, plus `udisks2`, `gio` and `xdg-open` at run time. For video thumbnails install `ffmpegthumbnailer` (or `ffmpeg`). To get the menu entry and icon run `linux/install-desktop.sh`.

### Known limitations
- WebP: ICC color profiles are ignored; only the first frame of animations is shown.
- Video thumbnails depend on the system: the Windows Shell needs a codec for the video; on Linux `ffmpegthumbnailer` or `ffmpeg` must be installed. MP3 files show no cover art or length.
- Single-instance handling is Windows only.
- Other Linux distributions and the Qt widgetset are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
