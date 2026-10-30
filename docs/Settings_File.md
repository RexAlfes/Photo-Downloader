## Settings file (PhotoDownloader.ini)

**What it is.** All program settings are kept in one plain-text INI file, written with the standard Lazarus `TMemIniFile` (UTF-8, `[Section]` headers and `Key=Value` lines). It is read at start-up and written when settings change and when the program closes.

**Where it is.** The program uses the per-user configuration folder returned by Lazarus `GetAppConfigDir(False)`:

| System | Location |
|---|---|
| Windows | `%LOCALAPPDATA%\<application name>\PhotoDownloader.ini` (normally `C:\Users\<you>\AppData\Local\...`) |
| Linux | `~/.config/<application name>/PhotoDownloader.ini` |

The exact path in use is shown in the **Status** dialog (line "Settings file:"). Other files in the same folder: `profiles\` (one `.ini` per saved user profile, same format as the main file) and `thumbnail.log` (diagnostics for pictures that could not be previewed and for copy failures; written when Help > Logging is on) and `thumbcache\` (cached thumbnails, at most 500 MB; the oldest are removed when the program closes) and `exifcache.txt` (the camera, date and orientation read from each scanned file, at most 100,000 files; a file is read again when its size or date changes). Both can be deleted at any time; they are rebuilt.

**Format.** Each key below is read with the shown default when it is missing, so a missing or deleted file simply restores the defaults. True/False values are written as `1` and `0`. Unknown keys are ignored. Delete the file (with the program closed) to reset all settings.

| Section | Key | Type | Default | Meaning |
|---|---|---|---|---|
| `[Path]` | `DownloadDir` | text | `Pictures\Photo Downloader\{Y}\{Y}-{m}-{D}-{J}\` in the user's home folder | Destination folder template (tokens such as {Y} {m} {D} {J}) |
| `[Path]` | `FileNameMask` | text | {o} | File name template ({o} = the original file name) |
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
| `[General]` | `AutoRenameClash` | True/False | 0 | Download name-clash files without asking, renamed `name (1).ext`, `name (2).ext` ... |
| `[General]` | `IgnoreDuplicates` | True/False | 1 | Skip duplicate files on download (excludes `RenameDuplicates`) |
| `[General]` | `RenameDuplicates` | True/False | 0 | Download duplicate files too, renamed `name (1).ext`, `name (2).ext` ... when the name exists |
| `[General]` | `AutoRotate` | True/False | 1 | Auto-rotate downloaded JPEGs losslessly |
| `[General]` | `WinSafeNames` | True/False | 1 | Replace characters Windows cannot store in file names (used on Linux; always on in Windows) |
| `[General]` | `RenameJpe` | True/False | 0 | Rename .jpe to .jpg |
| `[General]` | `LrPrevAsJpg` | True/False | 0 | Save Lightroom previews (.lrprev) as .jpg when downloading |
| `[General]` | `LrPrevKeepBoth` | True/False | 0 | With LrPrevAsJpg: keep the .lrprev file as well (save both) |
| `[General]` | `Logging` | True/False | 1 | Write diagnostics to `thumbnail.log` (Help > Logging) |
| `[General]` | `ProfileName` | text | (empty) | User profile loaded or saved last; File > User Profiles > Save suggests it |
| `[General]` | `LowerName` | True/False | 0 | Lower-case file names |
| `[General]` | `LowerExt` | True/False | 0 | Lower-case extensions |
| `[General]` | `UseCaptureTime` | True/False | 1 | Use the image capture time for the file timestamp |
| `[General]` | `SaveDateJobCodes` | True/False | 0 | Save date based job codes for next time |
| `[General]` | `WriteExifText` | True/False | 0 | Generate a text file with the EXIF shooting data |
| `[General]` | `AutoEject` | True/False | 1 | Automatically eject card reader media when disconnecting |
| `[General]` | `ScanWholeDisk` | True/False | 1 | Scan the whole disk for known image types |
| `[General]` | `ScanLrData` | True/False | 0 | Scan Lightroom preview folders (.lrdata) for .lrprev files; an older settings file without the key takes the `[FileTypes] LrPrev` value |
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
| `[View]` | `ThumbView` | number | 1 | View: 0 list, 1 thumbnail cards (build 57; before that 1 meant small and 2 large thumbnails, which are read as sizes 64 and 160) |
| `[View]` | `ThumbSize` | number | 160 | Thumbnail box in pixels, 64 to 320 (presets: Small 64, Medium 160, Large 320; Ctrl + mouse wheel sets any value in steps of 16) |
| `[View]` | `FitToWindow` | True/False | 1 | Thumbnail cards share the window width, thumbnails 64 to 160 pixels (default for new settings; a settings file written by an older build keeps 0) |
| `[FileTypes]` | `Jpeg`, `Png`, `Bmp`, `Gif`, `Tiff`, `CanonRaw`, `NikonRaw`, `NikonNrw`, `SonyRaw`, `Dng`, `OtherRaw`, `Heic`, `Avif`, `WebP`, `Mp4`, `Mov`, `Lrv`, `Audio`, `Thm`, `LrPrev` | True/False | 1 (Audio, Thm, LrPrev: 0) | Show this file type (View > File Types...). Groups: JPEG, PNG, BMP, TIFF, Canon RAW (cr2 cr3 crw), Nikon RAW (nef), Nikon Coolpix RAW (nrw), Sony RAW (arw srf sr2), DNG, other RAW (orf raf rw2 pef srw raw), HEIC/HEIF, AVIF, video MP4, video MOV, video LRV (each its own option), audio (mp3), THM, Lightroom previews (lrprev). The Default button of the dialog restores the defaults. An older `Video` key is read once and applied to the three video types. Hidden types are not listed and not downloaded |

**List sections.** These hold lists, stored as `Count=N` followed by `Item0`, `Item1` ... `Item(N-1)`:

| Section | Content |
|---|---|
| `[JobHistory]` | Previously used job codes, newest first |
| `[Mappings]` | One line per camera: `Camera name|T8 value|T9 value` (`Default|{T1}|{T1}` is created if empty) |
| `[Plugins]` | `Name=0` or `Name=1` for JPEG auto profile, Directory Maker, JPEG resolution, every program plug-in (`.plugin.ini`) and every plug-in library found (key = file name without `lib` and extension; a new library is added as `=0`). The order is the order of the Plug-ins list. Old `Backup=` and `DNG Converter=` lines are removed when the file is read |
| `[PluginOpts]` | `Name=option` settings for the plug-ins (for example `Directory Maker=Edit, Web`: the folders it creates next to the download folder). For a plug-in library: its prompt values as `key=value;key=value` (`%` and `;` written as `%25` and `%3B`). **JPEG auto profile:** `Default=<profile>;Replace=0/1;Cam.<camera model>=<profile>`. **JPEG resolution:** `Value=<number>;Unit=dpi` or `Unit=cm` (a dot as decimal separator; 300 dpi when empty). A program plug-in: `Program=<path>` when chosen with Setup... |
| `[Iptc]` | `Name=value` details for the XMP sidecar: Creator, Copyright, Title, Description, Credit, Source |
| `[DateJobCodes]` | `yyyy/mm/dd=job code`; written only when `SaveDateJobCodes=1`, otherwise the section is removed |

**Notes.** The single/multi instance option (`[General] SingleInstance`) is also read before the main window opens. Fit to Window (`[View] FitToWindow=1`) is the default view for new settings; the view key was renamed in build 20 (it was `ViewMode`).
