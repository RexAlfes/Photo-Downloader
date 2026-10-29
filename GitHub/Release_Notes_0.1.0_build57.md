## Photo Downloader 0.1.0 – Build 57

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Highlights
- **Thumbnail sizes.** View > Thumbnail View now offers **Small (64 px), Medium (160 px), Large (320 px)** and **Fit to Window**. Hold **Ctrl** and turn the mouse wheel to change the size continuously (64 to 320 px). **Fit to Window**, the new default for new settings, uses as few columns as keep the cards at 160 px or less and shares the window width evenly, so no space is left at the right. The same choices are in the right-click menu. Existing settings files keep the fixed size they had.
- **Cleaner cards.** The name no longer shows its extension; the line below shows the date, the **file type** and the **size**, for example `10/28/26 11:02:00   NEF   24.1 MB`. Long names are shortened with "..." and no longer push the information off the card. The list view keeps the full name.
- **Adobe Lightroom previews (.lrprev).** These preview files can now be listed and viewed (the largest preview in the file, at most 256 px). They contain no original file name, only an id, so they are for viewing and copying only. Off by default; switch on View > File Types... > Lightroom previews.
- **File Types: Default button.** Resets every choice to the program's own default: everything on except audio (MP3), camera thumbnail files (THM) and Lightroom previews.

### Other changes
- MP3 files are now off by default (like THM). Existing settings files keep their saved choice.
- The thumbnail log lists the **full path** of each file and each problem only once, so a large scan no longer fills the log with repeats. A folder scan no longer stops with "Stream Read Error" on cloud placeholder files (for example online-only OneDrive files); such files are skipped and logged.
- Thumbnails larger than 160 px are decoded at 320 px, so they stay sharp.
- Two project files: `PhotoDownloader.lpi` for Windows 64-bit and `PhotoDownloader_linux.lpi` for Linux 64-bit (GTK 3). GitHub Actions compiles each of them on every push (`.github/workflows/build.yml`).
- The User Manual and specification describe the new views, keys and file type.

### Downloads
- `PhotoDownloader.0.1.0.build.57.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.0.build.57.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.0.build.57.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.0.build.57.odt` and `.md` – User Manual

### Linux build
See `docs/Linux_Build.md`. You need Lazarus with the GTK2 or GTK3 widgetset, plus `udisks2`, `gio` and `xdg-open` at run time. For video thumbnails install `ffmpegthumbnailer` (or `ffmpeg`). To get the menu entry and icon run `linux/install-desktop.sh`.

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. If there is no such button, right-click the downloaded file, choose Properties, tick **Unblock** and click OK. See section 1 of the User Manual.

### Known limitations
- Lightroom previews (.lrprev) are small (at most 256 px) and carry no file name, only an id, so a preview cannot be matched to its original photo by name.
- WebP: ICC color profiles are ignored; only the first frame of animations is shown.
- Video thumbnails depend on the system: the Windows Shell needs a codec for the video; on Linux `ffmpegthumbnailer` or `ffmpeg` must be installed. MP3 files show no cover art or length.
- Single-instance handling is Windows only.
- Other Linux distributions and the Qt widgetset are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
