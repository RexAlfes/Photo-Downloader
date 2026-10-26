# Photo Downloader – Current Specification and Status

**Version:** 0.1.0 build 51 (baseline: build 42)  **Date:** 25 Oct 2026  **License:** GNU GPL v3 or later

## 1. Purpose

Photo Downloader is a desktop application that enumerates image and video files from a source folder or memory card, shows them as a thumbnail grid, and copies them to a destination while renaming them from a template. This document describes what the application does today and what is still open against *Specifications.odt*.

Status key: **Done** = implemented, **Partial** = implemented with limits, **Open** = not implemented.

## 2. Environment and build

| Item | Status |
|---|---|
| Lazarus 4.8 / FPC 3.2.2, packages LCL and LazUtils | Done |
| Forms in separate .LFM files (spec) | Open – all forms are currently built in code |
| Zero compiler errors and hints (spec) | Partial – the project's own units are clean. Build 41 compiled with Success, 14 warnings and 359 hints, nearly all from the bundled third-party decoder (`third_party/XelHeic`); cleaning those is optional |
| Platform: 64-bit Windows program  | Done – 32-bit builds are not provided; request one through the GitHub testing process (issue) or the online testing form |
| Application icon (PhotoDownloader.ico) | Done |
| Version info with automatic build increment (IDE) | Done – shown in About, Status, Register |
| Settings: PhotoDownloader.ini plus profiles folder in the user config folder | Done – the spec names settings.ini and history.txt |

Units: `uMain` (main form), `uDialogs` (Job Code, Preferences, IPTC, Register, About), `uPhotoView` (thumbnail grid), `uViewer` (image viewer), `uItems` (image model, tokens, scanning, status, thumbnails, copy), `uExif` (EXIF read/write, embedded JPEG), `uSettings`, `uDrives`, `uVersion`, `uHeic` (HEIC/AVIF loader around the bundled decoder), `uScale` (smooth down-scaling), `uRotate` (lossless JPEG rotation), `uSingle` (single instance), `uTiffRead` (own TIFF reader), `uSafeDel` (safe delete), and `third_party/XelHeic` (bundled HEIC/AVIF decoder).

## 3. Functional status

### 3.1 Source and scanning

| Function | Status |
|---|---|
| Open Source Folder (Ctrl+O), recursive scan | Done |
| File types: JPEG, PNG, BMP, GIF, TIFF, RAW (NEF, NRW, CR2, CR3, CRW, ARW, DNG, ORF, RAF, RW2, PEF and others), HEIC, MP4, MOV, LRV, MP3, THM | Listed and copied; View > File Types... chooses the kinds (video, audio and THM are off by default). Canon CR3: preview and EXIF done. HEIC: EXIF done; preview supported (bundled pure-Pascal decoder, no DLLs). Video and audio: preview in development |
| Option to scan only DCIM instead of the whole disk | Done |
| Auto-detect removable drive with DCIM (Refresh with no source, or automation at start-up) | Partial – Windows only |
| Nothing is scanned at start-up; optional "load last used folder at startup" | Done |
| Card reader drive letters, Locate card reader | Done (Windows) |
| UNC paths (\\NAS\Photos) | Partial – work as ordinary paths, untested |
| MTP devices, direct USB cameras | Open |
| Watch mode (automatic download of new files) | Open |
| Refresh (F5), Eject (F6) | Done – eject uses PowerShell on Windows |
| Single or multiple instances (Preferences > General, default single) | Done – Windows only; takes effect at the next start |

### 3.2 Main window

| Function | Status |
|---|---|
| Left list "Date - Job code", right thumbnail grid, status bar | Done |
| Card shows number, name, size, EXIF date/time, status, camera model, new name | Done – camera maker is not shown separately |
| Views: list, small and large thumbnails | Done |
| List view column headings (File, Captured, Status, Camera, Destination); click a heading to sort, click again to reverse; an arrow marks the sorted column | Done (build 44, tested). The order also applies to the thumbnail views and the viewer; downloads and sequence numbers still follow card order |
| Selecting thumbnails highlights their date entries; selecting dates selects their images | Done |
| Status bar: files to download, problem files, copy result | Done |
| Right-click an image: View image, Open image location, Download selected, Delete selected, Properties | Done |
| Right-click a date entry: change job code for it or the highlighted dates | Done |
| The job code may be blank (Job Code dialog, Preferences, date entries): `{J}` expands to nothing and a dash or underscore left next to it is removed from folder and file names. A date given a blank code is stored as `{no job}` in `[DateJobCodes]` | Done (build 46, tested) |
| Double-click an image: viewer (Esc closes, arrows or wheel move) | Done |

### 3.3 Thumbnails

| Function | Status |
|---|---|
| JPEG, PNG, BMP | Done |
| GIF (.gif): thumbnail and viewer show the first frame (animation is not played); file type "GIF" in View > File Types | Done (build 48, tested) |
| RAW: largest embedded JPEG preview, falls back to the next ones | Partial – NEF needs confirming on real files; failures are logged to thumbnail.log |
| Thumbnails load a few at a time while scrolling | Done |
| TIFF and DNG: embedded JPEG, otherwise the image data itself (build 40: own reader `uTiffRead.pas`: LZW, PackBits, Deflate, CCITT fax Group 3/4/RLE; 1/2/4/8/16-bit grey, palette, RGB, CMYK; strips and tiles; predictor; averaged down to thumbnail size) | Done – needs testing on real scans. Not supported: JPEG-compressed TIFF, planar layout, float samples, BigTIFF (placeholder thumbnail, reason in thumbnail.log). A file named .png or .bmp that is really a TIFF or JPEG is now recognised |
| Canon CRW: embedded JPEG preview, camera and date from the CIFF directories | Done |
| Portrait rotation from EXIF orientation | Done, tested (build 48: also for files whose EXIF holds only the orientation, no camera or date; failures to turn a downloaded JPEG are written to the log) – thumbnails and viewer turn the picture upright (EXIF orientation 2–8). HEIC files carry their own rotation box, which the decoder normally applies; the program only turns a HEIC picture itself when a quarter turn is asked for but the picture comes back unturned |
| Video previews | In development – a labelled placeholder is shown |
| HEIC / AVIF previews | Supported with a bundled pure-Pascal decoder (third_party/XelHeic); no DLLs or compiler settings; a labelled placeholder is shown for a file that cannot be decoded |
| Canon CR3 and TIFF previews | Done |

### 3.4 Status detection and naming

| Function | Status |
|---|---|
| Statuses: New file, Already downloaded, Name clash, Duplicate file | Done |
| Red card only for Name clash; the reason is shown, e.g. "same new name as #3" | Done |
| Statuses and new names refresh when preferences, job codes or profiles change | Done |
| Download history file so images are never copied twice | Open – comparison is against the destination only |
| Duplicate handling skip / overwrite / auto-rename | Partial – skip and auto-rename; overwrite missing |
| Tokens: {d} {y} {Y} {m} {b} {B} {D} {a} {A} {W} {t} {H} {I} {M} {S} {q} {r} {o} {f} {O} {i} {c} {T} {T1} {T8} {T9} {J} {seq#} {n1}-{n9} | Done – taken from the screenshots, not the spec's {YYYY} style |
| {r} image number = longest digit run of the original name, else the whole name | Done – the rule is an assumption |

### 3.5 Download and delete

| Function | Status |
|---|---|
| Copy with progress and cancel, size check, capture-time file date, read-only options, lower-case and .jpe options | Done |
| Persistent sequence counter, Reset | Done |
| Verified copy by MD5 | Done (build 38, see 3.8) |
| Move (delete after verified copy) | Open |
| Delete from source only if the file is marked downloaded and exists in the destination | Done |
| Safe delete (Preferences > Automation, ini `[Automation] SafeDelete`, default on): deleted files go to the Recycle Bin on fixed disks; on cards, USB and network drives they are moved to a hidden `$trash.bin` folder (name can be changed in Preferences > Automation) at the drive root (same sub-folders); if neither works the file is kept (build 43, new unit `uSafeDel`, tested; the trash folder name setting is tested too) |
| Author and copyright written to EXIF of downloaded JPEGs, only into empty fields | Done |
| XMP sidecar from IPTC/XMP data, EXIF text file | Done |
| Lossless auto-rotate of downloaded JPEGs (Preferences > General) | Done – works on the compressed data, no quality loss; baseline/extended sequential 8-bit JPEG with one scan. Up to 15 pixel rows or columns that do not fill a block are trimmed on the mirrored edge (like jpegtran -trim); the EXIF orientation is reset to 1; the embedded EXIF thumbnail is not turned; progressive JPEGs are decoded fully and saved back as sequential JPEG files (build 43, tested) |
| Legacy IPTC IIM, GPS geotagging | Open |
| Backup plug-in | Replaced by the backup destination (see 3.8) |
| Directory Maker plug-in | Done |
| JPEG auto profile, DNG Converter, JPEG resolution plug-ins | Open – listed only |
| Launch external program after download | Partial – custom button with %f and %d, not {file} and {folder} |
| Log of per-file results | Partial – copy failures are written to thumbnail.log when logging is on; no full per-file report yet |

### 3.6 Menus and preferences

| Function | Status |
|---|---|
| File, Edit, View, Help menus and shortcuts as in the specification | Done |
| User Profiles Load / Save / Delete, Export Settings | Done |
| "Prompt for user profile at startup" (Preferences > General): a list of profiles is shown at start-up; the entry **Default** is always offered and keeps the current settings, so the prompt also appears when no profile has been saved yet. Loading a profile never switches the prompt option off | Done (build 46, tested) |
| Camera Settings, Check GPS Track Log | Open – disabled |
| GPS Settings | Open – message only |
| Preferences tabs: Download Path, General, Automation, Custom button, Mapping, Plug-ins | Done |
| Camera mapping ({T8}/{T9} per camera) | Done |
| Automation (download, delete, eject, launch, exit; prompt) | Done |
| Help: Contents and Getting Started (short text) | Partial |
| Help: Visit website opens https://rexalfes.github.io/Photo-Downloader/; Check for updates opens https://github.com/RexAlfes/Photo-Downloader/releases | Done – opens the pages; no in-app version comparison |
| Register shows the GNU GPL notice; About shows the version | Done |
| Help > Logging (on/off, ini `[General] Logging`) and Help > Save log file... | Done |

### 3.7 Number of images (performance note)
There is no fixed limit on the number of images scanned. The source folder and all its subfolders are read (hidden and system folders are skipped) and every supported file is listed. The practical limits are memory and time:

- Each file's details take a few KB. A 160-pixel thumbnail takes about 60-100 KB, so 10,000 pictures need roughly 0.6-1 GB of memory for thumbnails (the program is 64-bit).
- When a folder loads, the first 300 ordinary thumbnails and every HEIC, AVIF, TIFF and DNG thumbnail are rendered before the grid is shown (the slow types are cached on disk); the rest are drawn as you scroll. RAW files and JPEGs with embedded previews are fast; HEIC and AVIF files take about a second or more each. HEIC, AVIF, TIFF and DNG thumbnails are cached on disk (`thumbcache` folder), so a second load is much faster.
- List view is lighter: thumbnails are drawn only for rows you scroll to.
- Only the most recent 1,200 thumbnails are kept in memory (each one uses a Windows bitmap handle and a program may only own about 10,000). Older ones are drawn again when scrolled into view. Folders with about 6,000 pictures have been tested.

### 3.8 Verified copy and backup destination (build 38)

| Function | Status |
|---|---|
| Verified copy: the MD5 of the original is calculated while it is copied, the copy is read back and compared; a bad copy is deleted and retried once, then the download stops with a message and the file is not marked downloaded | Done – tested on a real card (build 42). Note: the read-back goes through the operating system, which may serve it from its cache, so it catches interrupted or failed writes better than a faulty card or disk |
| Setting: Preferences > Download Path > "Verify every copy" (default on, ini `[Path] VerifyCopy`) | Done |
| Backup destination: a second copy of every file in its own folder (same {Y}, {m}, {D}, {J} patterns and the same file name), made from the verified download before rotation or metadata changes; verified the same way | Done – tested on a real card (build 42) |
| Settings: "Also save a second copy to a backup folder" and Backup directory (ini `[Path] BackupEnabled`, `BackupDir`); the old Backup plug-in is replaced by this | Done |
| If a backup copy fails, the file stays downloaded but is never offered for deletion from the image source | Done |
| File > View Trash opens the trash folder of the source drive in Explorer; File > Empty Trash... erases its contents after a confirmation that shows the file count and size | Done (build 45, tested) |
| Cancel stops a copy in the middle of a file; incomplete copies are deleted | Done |
| Resume after cancel: the partial file is deleted, and the next download continues with the cancelled file and skips files already downloaded | Done – tested on a real card (build 42) |

## 4. Open items

### 4.1 In progress (planned for coming builds)

| Item | Notes |
|---|---|
| Verified copy | Build 38 (see 3.8). Next: a "verify existing files" check for files downloaded earlier |
| Backup destination | Build 38 (see 3.8). Next: more than one backup destination, backup to a different drive with a free-space check |
| Resume and skip | Done for a cancelled download (see 3.8). Next: resume after a crash or power loss, where a partial file may be left behind |
| Download history | Log of what came from which card and when; makes "already downloaded" work when files were later moved or renamed |
| Content-based duplicate detection | Fast hash of the first and last blocks instead of size, time and camera only |
| Time offset correction | Shift capture times when the camera clock was wrong |
| RAW+JPEG pairing | Treat a RAW and its JPEG as one unit; optionally download only one of them |
| Ratings and labels | Read from the camera and write into the XMP sidecar |
| Watermark or resize on copy | Optional, mainly for event work |
| Dry run / preview | Show what would be copied and renamed without changing anything |
| Installer and code signing | Windows SmartScreen warns about unsigned programs |
| Automated tests | File name tokens, date logic and duplicate rules are pure functions and easy to test |
| Video and audio previews | In development; these file types are switched off by default until verified |
| Direct USB camera download (PTP/MTP) | libgphoto2 on Linux |
| GPS geotagging, watch mode | Open |
| Convert forms to .LFM files | Open |

### 4.2 Linux version (builds and runs; tested on Linux Mint 22.3 XFCE, GTK 3)

| Item | Notes |
|---|---|
| Source detection | `uDrives` reads `/proc/mounts`; removable media are devices mounted under `/media/`, `/run/media/` or `/mnt/` (loop devices excluded). `MountPointOf` and `IsRemovableMount` replace drive-letter logic; the card reader drive letter setting is hidden on Linux. Done, tested on Linux Mint 22.3 |
| Eject and reveal | `udisksctl unmount` then `power-off`, falling back to `gio mount -u` and `umount`; Show in folder uses `xdg-open`. Done, tested on Linux Mint 22.3 |
| Safe delete | Cards and other removable mounts use the hidden trash folder; fixed disks use `gio trash` (freedesktop trash). Done, tested on Linux Mint 22.3 |
| File names | New option `[General] WinSafeNames` (Preferences > General, "Windows-safe file names", default on). Off, only `/` and the null character are replaced; on Windows it is always on. Done, tested on Linux Mint 22.3 |
| Paths and settings | `~/.config/<application name>/` for settings; thumbnail cache in `$XDG_CACHE_HOME` or `~/.cache/PhotoDownloader/thumbcache`. Done, tested on Linux Mint 22.3 |
| Single instance | Windows only; on Linux several copies may run |
| Camera access | USB camera (PTP/MTP) through libgphoto2. Open |
| Packaging | AppImage or Flatpak, `.desktop` file and icon; Flatpak needs permission for removable media. Open |
| Widgetset | GTK2 first, then Qt5/Qt6; check the custom-drawn thumbnail list on each. Open |
| Threads | `cthreads` is the first unit in the project file under `UNIX`. Done |
| Small screens | The main window is limited to the desktop height (150 px margin on Linux for panels); tested at 1366x768 |
| Build instructions | See `docs/Linux_Build.md` |

## 5. Settings file (PhotoDownloader.ini)

**What it is.** All program settings are kept in one plain-text INI file, written with the standard Lazarus `TMemIniFile` (UTF-8, `[Section]` headers and `Key=Value` lines). It is read at start-up and written when settings change and when the program closes.

**Where it is.** The program uses the per-user configuration folder returned by Lazarus `GetAppConfigDir(False)`:

| System | Location |
|---|---|
| Windows | `%LOCALAPPDATA%\<application name>\PhotoDownloader.ini` (normally `C:\Users\<you>\AppData\Local\...`) |
| Linux | `~/.config/<application name>/PhotoDownloader.ini` |

The exact path in use is shown in the **Status** dialog (line "Settings file:"). Other files in the same folder: `profiles\` (one `.ini` per saved user profile, same format as the main file) and `thumbnail.log` (diagnostics for pictures that could not be previewed and for copy failures; written when Help > Logging is on) and `thumbcache\` (cached HEIC, AVIF, TIFF and DNG thumbnails).

**Format.** Each key below is read with the shown default when it is missing, so a missing or deleted file simply restores the defaults. True/False values are written as `1` and `0`. Unknown keys are ignored. Delete the file (with the program closed) to reset all settings.

| Section | Key | Type | Default | Meaning |
|---|---|---|---|---|
| `[Path]` | `DownloadDir` | text | `Pictures\Photo Downloader\{Y}\{Y}-{m}-{D}-{J}\` in the user's home folder | Destination folder template (tokens such as {Y} {m} {D} {J}) |
| `[Path]` | `FileNameMask` | text | {o} | File name template ({o} = the original file name; default since build 48) |
| `[Path]` | `JobCode` | text | {Job Name} | Current job code |
| `[Path]` | `PromptJobCode` | True/False | 1 | Prompt for the job code every time the program is run |
| `[Path]` | `VerifyCopy` | True/False | 1 | Read every copy back and compare checksums |
| `[Path]` | `BackupEnabled` | True/False | 0 | Also save a second copy to the backup folder |
| `[Path]` | `BackupDir` | text | (empty) | Backup folder template (same tokens as DownloadDir) |
| `[Path]` | `SeqStart` | number | 1 | First sequence number |
| `[Path]` | `SeqNext` | number | 1 | Next sequence number |
| `[General]` | `SourceMode` | number | 0 | Source: 0 automatic, 1 camera, 2 card reader |
| `[General]` | `DriveLetters` | text | E | Drive letters treated as card readers |
| `[General]` | `DisablePTP` | True/False | 1 | Disable PTP downloads |
| `[General]` | `SaveReadOnly` | True/False | 0 | Save files as read-only |
| `[General]` | `PreserveReadOnly` | True/False | 0 | Preserve read-only status |
| `[General]` | `PromptProfile` | True/False | 0 | Prompt for a user profile at startup |
| `[General]` | `IgnoreSizeCheck` | True/False | 1 | Ignore file size check (for images modified after downloading) |
| `[General]` | `AutoRotate` | True/False | 1 | Auto-rotate downloaded JPEGs losslessly |
| `[General]` | `WinSafeNames` | True/False | 1 | Replace characters Windows cannot store in file names (Linux only; always on in Windows) |
| `[General]` | `Logging` | True/False | 1 | Write diagnostics to `thumbnail.log` (Help > Logging) |
| `[General]` | `RenameJpe` | True/False | 0 | Rename .jpe to .jpg |
| `[General]` | `LowerName` | True/False | 0 | Lower-case file names |
| `[General]` | `LowerExt` | True/False | 0 | Lower-case extensions |
| `[General]` | `UseCaptureTime` | True/False | 1 | Use the image capture time for the file timestamp |
| `[General]` | `SaveDateJobCodes` | True/False | 0 | Save date based job codes for next time |
| `[General]` | `WriteExifText` | True/False | 0 | Generate a text file with the EXIF shooting data |
| `[General]` | `AutoEject` | True/False | 1 | Automatically eject card reader media when disconnecting |
| `[General]` | `ScanWholeDisk` | True/False | 1 | Scan the whole disk for known image types |
| `[General]` | `AddIptc` | True/False | 0 | Add IPTC/XMP data to downloaded images (written as an XMP sidecar) |
| `[General]` | `PromptIptc` | True/False | 0 | Prompt for IPTC/XMP data every time the program is run |
| `[General]` | `WriteIptcIIM` | True/False | 0 | Also write legacy IPTC IIM data (not implemented yet) |
| `[General]` | `WriteIptcNef` | True/False | 1 | Legacy IPTC IIM data for NEF raw files (not implemented yet) |
| `[General]` | `WriteExifOwner` | True/False | 0 | Write author/copyright into empty JPEG EXIF fields |
| `[General]` | `ExifAuthor` | text | (empty) | EXIF author text |
| `[General]` | `ExifCopyright` | text | (empty) | EXIF copyright text |
| `[General]` | `FirstRunDone` | True/False | 0 | The first-run screen has been shown |
| `[General]` | `LoadLastAtStartup` | True/False | 0 | Reload the last source folder at start |
| `[General]` | `SingleInstance` | True/False | 1 | Allow only one running copy |
| `[General]` | `LastSource` | text | (empty) | Last source folder |
| `[Automation]` | `AutoAtStartup` | True/False | 0 | Enable Automation at startup |
| `[Automation]` | `AutoMenu` | True/False | 0 | Enable the Automation menu option and shortcut |
| `[Automation]` | `AutoPrompt` | True/False | 1 | Prompt before starting the auto sequence |
| `[Automation]` | `AutoDownload` | True/False | 0 | Download files when the application is started |
| `[Automation]` | `AutoDelete` | True/False | 0 | Delete files from the card after downloading |
| `[Automation]` | `SafeDelete` | True/False | 1 | Safe delete: deleting from the source moves files to the Recycle Bin (fixed disks) or a hidden trash folder on the same drive (cards, USB, network) instead of erasing them |
| `[Automation]` | `SafeDeleteFolder` | text | $trash.bin | Name of the hidden trash folder created at the drive root on cards, USB and network drives |
| `[Automation]` | `AutoSoftEject` | True/False | 0 | Soft eject the card reader media |
| `[Automation]` | `AutoLaunch` | True/False | 0 | Launch the app associated with the custom button |
| `[Automation]` | `AutoExit` | True/False | 0 | Exit the program |
| `[Custom]` | `Enabled` | True/False | 0 | Show the custom button |
| `[Custom]` | `Caption` | text | C&ustom | Custom button caption |
| `[Custom]` | `Command` | text | (empty) | Custom button command line (%f file, %d folder) |
| `[Mapping]` | `IdentifyBySerial` | True/False | 0 | Identify the camera by serial number, owner string or user comment |
| `[Mapping]` | `PromptNewCamera` | True/False | 0 | Prompt for camera mappings when a new camera is detected |
| `[View]` | `ShowDownloaded` | True/False | 1 | Show already downloaded images |
| `[View]` | `ShowDuplicates` | True/False | 1 | Show duplicate images |
| `[View]` | `ShowDateSelector` | True/False | 1 | Show the date / job code list |
| `[View]` | `ThumbView` | number | 2 | View: 0 list, 1 small thumbnails, 2 large thumbnails (default) |
| `[FileTypes]` | `Jpeg`, `Png`, `Bmp`, `Gif`, `Tiff`, `CanonRaw`, `NikonRaw`, `NikonNrw`, `SonyRaw`, `Dng`, `OtherRaw`, `Heic`, `Avif`, `Video`, `Audio`, `Thm` | True/False | 1 | Show this file type (View > File Types...). Groups: JPEG, PNG, BMP, TIFF, Canon RAW (cr2 cr3 crw), Nikon RAW (nef), Nikon Coolpix RAW (nrw), Sony RAW (arw srf sr2), DNG, other RAW (orf raf rw2 pef srw raw), HEIC/HEIF, AVIF, video (mp4 mov lrv), audio (mp3), THM. Hidden types are not listed and not downloaded |

**List sections.** These hold lists, stored as `Count=N` followed by `Item0`, `Item1` ... `Item(N-1)`:

| Section | Content |
|---|---|
| `[JobHistory]` | Previously used job codes, newest first |
| `[Mappings]` | One line per camera: `Camera name|T8 value|T9 value` (`Default|{T1}|{T1}` is created if empty) |
| `[Plugins]` | `Name=0` or `Name=1` for JPEG auto profile, Backup, Directory Maker, DNG Converter, JPEG resolution |
| `[PluginOpts]` | `Name=option` settings for the plug-ins (for example the Backup folder) |
| `[Iptc]` | `Name=value` details for the XMP sidecar: Creator, Copyright, Title, Description, Credit, Source |
| `[DateJobCodes]` | `yyyy/mm/dd=job code`; written only when `SaveDateJobCodes=1`, otherwise the section is removed |

**Notes.** The single/multi instance option (`[General] SingleInstance`) is also read before the main window opens. Large thumbnails (`[View] ThumbView=2`) are the default; the key was renamed in build 20 (it was `ViewMode`), so older files simply start with the new default once.

## 6. Version history

| Build | Changes |
|---|---|
| 1–8 | Initial implementation from screenshots and specification, compile and stability fixes, icon, GPL notice, date/thumbnail sync, EXIF author and copyright, RAW previews, throttled thumbnails |
| 51 | Linux build tested on Linux Mint 22.3 (XFCE, GTK 3): card detection, Locate card reader (lists drives found), eject, safe delete, View/Empty Trash, thumbnails, sorting and viewer work; progress window stays above the main window; General tab layout and Windows-safe label fit 1366x768; main window height limited to the desktop; project option mutes hint 5023 (unit not used in project file) |
| 50 | Fixed a bug in progressive JPEG decoding (a local variable hid the spectral-start value; tested); compiler hint clean-up in uRotate, uTiffRead, uHeic and uItems (remaining hints are in the bundled XelHeic decoder); Windows build of the Linux groundwork compiled cleanly |
| 49 | Linux groundwork: mount points and removable-media detection from `/proc/mounts`, eject with udisksctl/gio/umount, safe delete through `gio trash` on fixed disks, thumbnail cache in `~/.cache`, Windows-safe file names option, `docs/Linux_Build.md`. Windows behaviour unchanged; Linux code not yet compiled |
| 48 | Default file name template is `{o}`; GIF files are listed, previewed (first frame) and can be filtered; EXIF orientation is now read from files that have no camera or date (such pictures were shown and downloaded unturned); the log names the reason when a downloaded JPEG cannot be auto-rotated |
| 47 | The default name of the hidden trash folder is now lower case (`$trash.bin`; existing settings keep their saved name); the safe delete confirmation text is split over three lines |
| 46 | The job code may be blank (`{J}` expands to nothing and a leftover dash or underscore is removed); the start-up user profile prompt always offers **Default** and loading a profile no longer switches the prompt off; Preferences > Automation: safe delete text fits the window and the trash folder name box is disabled when safe delete is off |
| 45 | The hidden trash folder on cards is now named `$Trash.bin` by default and the name can be set in Preferences > Automation (`[Automation] SafeDeleteFolder`); File > View Trash and File > Empty Trash...; list view headings tested |
| 44 | List view has column headings; click a heading to sort by it (click again to reverse). The thumbnail views and the viewer follow the sorted order; downloads keep card order |
| 43 | Safe delete (Recycle Bin or hidden trash folder on the card); auto-rotate now also handles progressive JPEGs |
| 42 | **Baseline.** Code cleanup (unused variables and units removed from uTiffRead, uHeic, uDialogs); every document checked and brought up to date; continuation prompt added (docs/Continuation_Prompt.txt). No functional change |
| 41 | The image viewer uses the new TIFF reader too, so palette, compressed and 1-bit TIFF files no longer open as a black window |
| 40 | New TIFF reader (uTiffRead.pas) for compressed and 1-bit TIFF files (LZW, PackBits, Deflate, CCITT fax, palette, 16-bit, CMYK, tiles); files with a wrong .png/.bmp extension are recognised by content; thumbnail.log names the reason when a TIFF cannot be read |
| 39 | Fix: with about 5,000 pictures the thumbnails stopped rendering ("Canvas does not allow drawing") and the loading window stopped responding, because every thumbnail used up Windows bitmap handles (limit about 10,000 per program). Only the most recent 1,200 thumbnails are now kept in memory; the rest are drawn again when scrolled into view (HEIC/AVIF/TIFF/DNG from the disk cache). Loading renders only the first screens of ordinary pictures |
| 38 | Verified copy (MD5 read-back, retry, cancel inside a file); backup destination with its own folder template; files whose backup failed are never offered for deletion; the start-up job code window also asks for the source folder; spec lists planned features and the Linux version; number-of-images note |
| 37 | Generic defaults: destination `Pictures\Photo Downloader\{Y}\{Y}-{m}-{D}-{J}\` in the user's home folder, card reader letter E; files with status Already downloaded are drawn on a grey background (blue-grey when selected) |
| 36 | File Types: Nikon NEF and NRW are now separate entries (new ini key `NikonNrw`); the name clash text names the file it clashes with |
| 35 | Changing the destination folder or file name pattern in Preferences rescans the loaded files against the new destination (status Downloaded / name clash / duplicate) and shows a wait cursor |
| 34 | Help > Logging (on/off, saved as `[General] Logging`) and Help > Save log file...; video, audio and .thm file types are off by default (existing ini files keep their saved choice); faster thumbnails for HEIC/AVIF (reduced colour conversion, AV1 post-filters skipped for thumbnails, thumbnail disk cache in `thumbcache\`); compiler optimisation level 2 |
| 33 | AVIF: fixed an endless decode for pictures whose height/width in 4-pixel blocks is odd (e.g. 1920x2523); the decoder now uses the frame header block counts |
| 32 | HEIC/AVIF decoding runs in its own thread: the loading window stays alive, shows the file being decoded, Cancel works, and a decode that runs more than 2 minutes (30 s after Cancel) is given up and HEIC/AVIF previews are switched off for the rest of the session; decoded pictures are reduced to thumbnail size in the thread |
| 31 | Loading a source folder shows a pop-up with two progress bars (reading files, rendering thumbnails) and a Cancel button; thumbnails are rendered before the grid is shown instead of while it paints. AV1 deblocking now keeps every filter inside the picture buffer |
| 30 | File type filter (View > File Types... and the right-click menu; all on by default, Select all / Clear all, saved in the ini); progress pop-up with Cancel while the source folder is read; download progress is now weighted by file size; AV1 decoder: deblock filter read past the end of the picture buffers (rows padded) |
| 29 | Fixed AVIF decoding crash (access violation): the bundled AV1 decoder wrote past its arrays for blocks on the right/bottom picture edge and for pictures wider than ~1000 px. Local patch in third_party/XelHeic/Av1.Decoder.pas (noted in THIRD_PARTY_NOTICES.md) |
| 28 | Decode errors in thumbnail.log now include a source-line backtrace (project builds with -g -gl); AVIF decode raises an access violation, cause being traced |
| 27 | HEIC/AVIF decode failures are now logged with the reason in thumbnail.log (AVIF files showed grey boxes; cause under investigation) |
| 26 | AVIF (.avif) files are now listed, copied and previewed by the bundled decoder (they were not in the file-type list) |
| 25 | HEIC decoder bundled in the project (third_party/XelHeic, pure Pascal): previews always on, no DLLs, no compiler defines, Option A/B add-on steps removed; THIRD_PARTY_NOTICES.md added |
| 24 | 64-bit platform stated in the README, spec, website, tester materials and release notes (32-bit on request through the GitHub testing process and online form). HEIC: nine more sample files checked (portrait and landscape, Apple and Samsung): camera, date and orientation read correctly. The decoder's rotation is now verified: if a HEIC picture asks for a quarter turn but comes back unturned, the program turns it itself |
| 23 | Start-up sizing also for small thumbnails: 4 columns, or 2 when the window would be wider than 66% of the desktop. Launch materials v2 renamed Photo_Downloader_Launch_Materials_Tester_Kit. Compiler hints fixed in uSingle and uRotate |
| 22 | Startup window is measured after it opens so the scroll bar no longer takes cell space; 3 large-thumbnail columns, or 2 when the window would be wider than 66% of the desktop. "Licence" spelling changed to "License". Settings file location and keys documented (new section 5 and docs/Settings_File.md). README HEIC steps split per option |
| 21 | Auto-rotate: lossless rotation of downloaded JPEGs by their EXIF orientation (new unit uRotate); thumbnails and the viewer now show pictures upright. HEIC is documented as supported with an optional add-on |
| 20 | Large thumbnails are the default view (setting key renamed, so the new default applies once) and the window opens wide enough for 3 cards across; the large card is wider so the first line (number, file name, size) fits. Optional HEIC preview: new unit uHeic uses the Xelitan XelImageFormats package or HeifImage unit when compiled with -dHEIC_XEL or -dHEIC_HEIF (needs libheif DLLs next to the exe) |
| 19 | Canon CR3: camera, date, ISO and serial read from the file's metadata boxes (renaming, duplicate and clash checks now work), thumbnails and viewer use the embedded JPEG. HEIC: camera and date read from the Exif item; image preview in development (HEVC). Format claims in the launch materials changed to "in development" for HEIC, video and audio |
| 18 | uSingle pointer-conversion hints fixed; the unused "link to third-party browser" option removed from Custom button; paid-ware, subscription and paid-upgrade wording used generically in all documents and the website; docs and GitHub folders included in the code zip |
| 17 | Interim IDE build |
| 16 | Help > Support menu items (PayPal, Venmo); Support section on website and README; FUNDING.yml; compiler hint in uSingle fixed (window mark passed through the enumeration parameter); GitHub Pages home page, README and repository About text rewritten |
| 15 | Viewer decodes at screen size and scales smoothly (no blocky or aliased pictures); TIFF/DNG viewer searches the whole file for a larger JPEG preview; single instance rewritten with a Windows mutex (no background threads), fixing copies that stayed running after exit |
| 14 | Single/multi instance option (default single; a second start brings the first window forward); Canon CRW thumbnails use the colour preview instead of the raw data; compiler hints fixed in uExif |
| 13 | TIFF and DNG thumbnails (embedded JPEG or uncompressed image data); Canon CRW camera and date; Properties in the thumbnail and viewer right-click menus; Visit website and Check for updates open the project pages |
| 12 | Nothing is scanned at start-up; last used folder remembered (optional reload at start-up, F5, Open dialog); right-click Open image location; duplicates detected by size, time and camera; selecting a problem image shows its reason in the status bar |
| 11 | Image viewer opens at about two thirds of the main window; RAW thumbnail decode retried with default settings; grey placeholder and thumbnail frame so failed and nearly white thumbnails can be told apart |
| 10 | Removed the obsolete LazUTF8Classes unit (standard TFileStream and TStringList are used) |
| 9 | Stronger RAW preview search with fallback and log; image viewer; delete limited to downloaded files present in the destination; this document |
