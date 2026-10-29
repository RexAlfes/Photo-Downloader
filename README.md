# Photo Downloader

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
![Status: alpha](https://img.shields.io/badge/status-alpha-yellow.svg)

A free, open source Windows desktop tool that copies photos from memory cards and folders,
renames them from templates and files them into job-code folders. Written in Lazarus 4.8 / Free Pascal 3.2.2.

Website: <https://rexalfes.github.io/Photo-Downloader/> | Downloads: <https://github.com/RexAlfes/Photo-Downloader/releases> | Issues: <https://github.com/RexAlfes/Photo-Downloader/issues>

> **Alpha software.** Keep your original files until you have checked the copies.

## Windows security warning
Windows may show **Windows protected your PC** (SmartScreen) with **Publisher: Unknown publisher** the first time you run the program, because the free, open source `.exe` is not code-signed. It does not mean the file is damaged. Download only from the [Releases page](https://github.com/RexAlfes/Photo-Downloader/releases), click **More info**, then **Run anyway**. If there is no such button, right-click the downloaded file, choose Properties, tick **Unblock** and click OK. The User Manual (section 1) also covers the browser warning, Smart App Control and antivirus quarantine.

## Documentation
- [User Manual](docs/User_Manual.md) – how to use every part of the program.

## Features
- Date / job-code list, thumbnail grid and list view, image viewer, status line. Thumbnails come in Small (64 px), Medium (160 px), Large (320 px) and **Fit to Window** (the default: cards share the window width), and Ctrl + mouse wheel changes the size continuously. A card shows the file name without its extension; the type and size are on the date line.
- List view has column headings; click one to sort by it (click again to reverse).
- Job Code dialog at start-up with history and a live example of the destination path. The job code may be left blank: `{J}` then expands to nothing and the dash or underscore next to it is removed from folder and file names.
- Token-based folder and file naming (`{T8}`, `{T9}`, `{r}`, `{E}`/`{e}`/`{ea}` file extension, sequence numbers, camera and EXIF values; every token works in folder and file names; plug-in libraries (DLL / .so) can add more tokens, see `docs/Plugin_Developer_Manual.md`), per-camera mapping.
- Thumbnails and viewer for JPEG, PNG, BMP, GIF, TIFF (including compressed, palette, 1-bit and fax scans), DNG, WebP (lossy, lossless and transparent, decoded by the program itself), HEIC, AVIF and the embedded previews of RAW files (NEF, NRW, CR2, CR3, CRW, ARW and others). Adobe Lightroom preview files (.lrprev) can be listed and viewed (switched off by default); when the Lightroom catalog is found, the photo's file name, capture date, camera and ISO are read from it (needs the SQLite library, see below).
- Video (MP4, MOV, LRV) and audio (MP3): capture date and length from the movie header, thumbnails from the system (Windows Shell; `ffmpegthumbnailer` or `ffmpeg` on Linux) with a play-symbol or music-note tile as fallback, double-click plays them in the default player.
- File type filter (View > File Types..., with MP4, MOV and LRV as separate entries), progress windows with Cancel while a folder loads, and a disk cache for all thumbnails.
- Status per image: new file, already downloaded, name clash (the new name is already taken), duplicate (the same picture twice: same size, time and camera), with the reason shown. See the [User Manual](docs/User_Manual.md) for exactly how each status is decided.
- XMP sidecar from IPTC/XMP details; author and copyright written only into JPEG fields that are empty.
- Verified copy (checksum read-back) and an optional backup folder; files whose backup failed are never offered for deletion.
- Delete from the card only for files that were downloaded and exist in the destination. Safe delete (on by default) moves them to the Recycle Bin, or to a hidden `$trash.bin` folder (name can be changed in Preferences > Automation) on the card, instead of erasing them. File > View Trash and File > Empty Trash... manage the card's trash folder.
- Auto-rotate: pictures are shown upright, and downloaded JPEGs, including progressive ones, can be turned losslessly by their EXIF orientation (Preferences > General). A progressive file is saved back as a sequential JPEG.
- User profiles (optionally chosen at start-up; "Default" keeps the current settings), export of settings, Eject, right-click Show in source folder / Show in destination folder and Properties.
- Single instance by default (switchable in Preferences > General). Nothing is scanned at start-up; the last folder is remembered.

## Build
Open `PhotoDownloader.lpi` in Lazarus 4.8 and press F9. The same project file builds for the system you are on (Windows 64-bit or Linux 64-bit with GTK 2). Or run:

    lazbuild PhotoDownloader.lpi                           (Windows; add -B for a full rebuild)
    lazbuild --ws=gtk2 PhotoDownloader.lpi                 (Linux: GTK 2 is the tested widgetset)

Build on the system you want the program for: cross compiling does not work with the current Lazarus and Free Pascal.

Forms are created in code (no `.lfm` files). Required packages: LCL and LazUtils.
Settings live in the per-user config folder (`PhotoDownloader.ini`, `profiles\`).

**64-bit.** Photo Downloader is built and tested as a 64-bit Windows program. A 32-bit build is not provided at this time; if you need one, request it through the GitHub testing process (open an issue) or the online testing form.

## HEIC and AVIF previews
HEIC / HEIF / AVIF pictures are shown in thumbnails and the viewer with no extra software, DLLs or compiler
settings. The decoder is the pure-Pascal Xelitan HEIC decoder, bundled in `third_party/XelHeic`
(see `THIRD_PARTY_NOTICES.md`). The project does **not** need the `XelImageFormats` package; if you added it
under Project > Project Inspector > Required Packages, remove it so units are not found twice.

## External library: SQLite (optional)
Photo Downloader is a single program file, with one exception: to read a Lightroom catalog (`.lrcat`) for `.lrprev`
preview files it uses the SQLite library of the system, loaded only when a `.lrprev` file is scanned:

- **Windows 10 and 11:** `winsqlite3.dll` is part of Windows, so there is nothing to install. On older Windows, or to use
  a newer SQLite, put the 64-bit `sqlite3.dll` from [sqlite.org](https://www.sqlite.org/download.html) next to
  `PhotoDownloader.exe`; a `sqlite3.dll` there is used first.
- **Linux:** `libsqlite3` (Debian/Ubuntu/Mint package `libsqlite3-0`), which nearly every system already has.

Without the library everything else works; `.lrprev` files then simply show no file name, date or camera from the
catalog. Help > Status shows which library is in use. The catalog and `previews.db` are opened read-only and never changed.

## File type filter
Use View > File Types... (or the right-click menu) to choose which kinds of files are listed and downloaded: JPEG, PNG, BMP, GIF, TIFF, RAW by brand, DNG, WebP, HEIC, AVIF, video, audio, THM and Lightroom previews. All are selected by default except audio (MP3), THM and Lightroom previews (.lrprev); **Select all**, **Clear all** and **Default** (back to the program's own choice) are provided. The choice is kept in `PhotoDownloader.ini`.

Files that are already downloaded are shown on a gray background; name clashes are red.

## Logging and troubleshooting
Help > Logging switches the diagnostic log on or off (on by default). Help > Save log file... copies the log to a folder of your choice so you can email it. Thumbnails are cached in the `thumbcache` folder (at most 500 MB; the oldest are removed when the program closes) (next to the settings file on Windows, in `~/.cache/PhotoDownloader/` on Linux), so reopening a folder is much faster.

## Verified copy and backup
Preferences > Download Path has two options. **Verify every copy** (on by default) reads each copy back and compares its checksum with the original; a bad copy is deleted and retried once. **Also save a second copy to a backup folder** writes every file to a second folder, using the same folder and file name patterns, from the verified download and before any rotation or metadata changes. If a backup copy fails, that file is never offered for deletion from the image source.

**Cancel and resume.** Cancel stops inside the current file and deletes the partial copy. Downloading again continues with the canceled file and skips files that are already downloaded.

## Linux
The program builds and runs on Linux (tested on Linux Mint 22.3, GTK 2 widgetset; the GTK 3 widgetset is experimental and has known problems). Card detection uses `/proc/mounts`, eject uses udisksctl, safe delete uses `gio trash`, settings are in `~/.config` and the cache in `~/.cache`; see `docs/Linux_Build.md` (including `linux/install-desktop.sh`, which adds the menu entry and icon). Single-instance handling and USB camera download are not available on Linux.

## Number of images
There is no fixed limit on the number of images scanned. The source folder and all its subfolders are read (hidden and system folders are skipped) and every supported file is listed. The practical limits are memory and time:

- Each file's details take a few KB. A 160-pixel thumbnail takes about 60-100 KB, so 10,000 pictures need roughly 0.6-1 GB of memory for thumbnails (the program is 64-bit).
- When a folder loads, the first 300 ordinary thumbnails and every HEIC, AVIF, TIFF and DNG thumbnail are rendered before the grid is shown; the rest are drawn as you scroll. RAW files and JPEGs with embedded previews are fast; HEIC and AVIF files take about a second or more each. Every thumbnail is cached on disk (`thumbcache` folder, at most 500 MB), so a second load is much faster.
- List view is lighter: thumbnails are drawn only for rows you scroll to.
- Only the most recent 1,200 thumbnails (about 600 at the 320-pixel size) are kept in memory (each one uses a Windows bitmap handle and a program may only own about 10,000). Older ones are drawn again when scrolled into view. Folders with about 6,000 pictures have been tested.

## Known limitations
- Lightroom preview files (.lrprev) hold small previews (at most 256 pixels) and no original file name, only an id. Preferences > File Handling can save them as .jpg when downloading, or save both the .lrprev and the .jpg. When the catalog is found (`<catalog> Previews.lrdata` next to `<catalog>.lrcat`, Lightroom Classic), the photo's name, date, camera and ISO come from it and the downloaded file is named after the photo. Lightroom preview folders are only scanned when Preferences > General > "Scan Lightroom preview folders (.lrdata) for .lrprev files" is on.
- Windows is the primary platform. Card-reader detection, eject and single-instance handling are Windows only.
- Not implemented yet: direct USB camera (PTP/MTP) download, GPS geotagging, watch mode,
  embedded IIM/IPTC (XMP is written as a `.xmp` sidecar), download history.
- TIFF thumbnails: LZW, PackBits, Deflate and CCITT fax (Group 3/4) compression, 1/2/4/8/16-bit gray, palette, RGB and CMYK, in strips or tiles, are supported. Not supported (placeholder thumbnail): JPEG-compressed TIFF, planar layout, floating point samples, BigTIFF.
- {r} (image number) is the longest run of digits in the original name (last on a tie).
- The code is compiled and tested by the project owner; report compiler messages or bugs as issues.

## Settings file
Settings are stored in `PhotoDownloader.ini` in the per-user configuration folder, for example
`%LOCALAPPDATA%\<application name>\PhotoDownloader.ini` on Windows and `~/.config/<application name>/PhotoDownloader.ini` on Linux.
The Status dialog shows the exact path. Saved user profiles are in a `profiles` folder next to it (same format), and
`thumbnail.log` (diagnostics, written when Help > Logging is on), the `thumbcache` folder and `exifcache.txt` (what the scan read from each file, so a second scan is faster) are in the same folder. The file is plain UTF-8 text with
`[Section]` headers and `Key=Value` lines; missing keys use their defaults, so deleting the file (program closed) resets everything.
The full list of sections, keys, types and defaults is in `docs/Settings_File.md` (also section 5 of `docs/Specification_Current.md`).

## Versioning
Version info is enabled with "Automatically increment build number". The IDE increments the number on each build; `lazbuild` does not, so raise `BuildNr` in `PhotoDownloader.lpi` by hand before a `lazbuild` run. Documents show only the version (0.1.1), not the build number.
The version is shown in About, Status and Register. See `docs/Specification_Current.md` for the version history.

**Baseline.** Build 42 is the baseline code. Suggested Git tag: `baseline-build-42`; later builds are compared against it.

## Support
Photo Downloader is free. If it saves you time, an optional donation helps: [PayPal](https://paypal.me/PhotoDownLoader) or [Venmo](https://venmo.com/u/RexAlfes) (US). Donations do not unlock anything.

## License
GNU General Public License v3 or later; the notice is shown in Help > Register.
Add the full license text as `COPYING` before distributing.

## Documentation
`docs/Specification_Current.odt` (and `.md`) describe the current functions and their status.
