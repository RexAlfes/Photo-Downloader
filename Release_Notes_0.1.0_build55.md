## Photo Downloader 0.1.0 – Build 55

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **Video support (MP4, MOV, LRV).** The capture date and the length of the clip are read from the movie header, so date-based folders and names work. Thumbnails are a real frame from the system: the Windows Shell on Windows; `ffmpegthumbnailer` or `ffmpeg` on Linux when installed. If the system cannot supply a frame, a cover picture inside the file or a `.thm` file with the same name is used; otherwise a dark tile with a play symbol, the extension and the length. Frames are kept in the thumbnail cache. Double-click plays the video in your default player.
- **MP3 support.** MP3 files get a default music-note tile; double-click plays them in your default player.
- **MP4, MOV and LRV are separate entries in View > File Types**, so each can be shown or hidden on its own (for example to download them to different destinations). Video and audio are on by default; THM files stay off. Older settings files that have the single `Video` key are read once and applied to the three video types.
- **Right-click menu** on thumbnails now also has the View menu choices (Show 'Downloaded' files, Show 'Duplicate' files, File Types, List View, Thumbnail Views), except the Image Date Selector.
- **Rename name clashes** now shows the clash as **New file (renamed)** instead of a red card, and the destination on the card already carries the new `(1)`, `(2)` number.
- **Shorter status text** in the cells (the clash reason is in Properties and the status bar).
- **Documentation:** the User Manual and specification now explain the difference between a name clash and a duplicate file and list how every status is decided.

### Other changes
- New unit `uVideoThumb.pas`. The File Types dialog is taller to show all entries.
- Untested in the field: the video and audio features and the changed status handling were written without a compiler run; please report anything odd.

### Downloads
- `PhotoDownloader.0.1.0.build.55.win64.exe` – Windows 64-bit
- `PhotoDownloader.0.1.0.build.55.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)

### Linux build
See `docs/Linux_Build.md`. You need Lazarus with the GTK2 or GTK3 widgetset, plus `udisks2`, `gio` and `xdg-open` at run time. For video thumbnails install `ffmpegthumbnailer` (or `ffmpeg`).

### Known limitations
- WebP: ICC color profiles are ignored; only the first frame of animations is shown.
- Video thumbnails depend on the system: the Windows Shell needs a codec for the video; on Linux `ffmpegthumbnailer` or `ffmpeg` must be installed. MP3 files show no cover art or length.
- Single-instance handling is Windows only.
- Other Linux distributions and the Qt widgetset are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
