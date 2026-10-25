## Photo Downloader 0.1.0 – Alpha build 15

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new in build 15
- **Sharper image viewer.** Pictures are decoded at screen size and scaled smoothly, so photos are no longer blocky or aliased.
- **Better TIFF and DNG previews.** The viewer searches the whole file for the largest embedded JPEG preview, so many TIFF and DNG files that looked low resolution now display clearly.
- **Single instance rewritten.** Single-instance handling now uses a Windows mutex with no background threads. Starting the program again brings the running window forward instead of launching another copy.

### Fixed
- Extra copies of Photo Downloader staying in memory after the window was closed (build 14 fix, rewritten in 15). If you still have old copies running from earlier builds, end them in Task Manager before testing.
- Canon CRW files showing a banded grey box instead of a thumbnail.
- Compiler hints in the EXIF code (uninitialised variables).

### Since the first alpha
- Single/multi instance option in Preferences > General (default single).
- Thumbnails and viewer for NEF, NRW, CR2, CRW, ARW, TIFF and DNG; Canon CRW camera and date.
- Nothing scanned at start-up; the last used folder is remembered.
- Right-click **Open image location** and **Properties** in the thumbnail and viewer menus.
- Duplicate detection by size, time and camera; name-clash reasons shown in the status bar.
- Delete from the card only for files that were downloaded and exist in the destination.
- Help menu links to the website and the releases page.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: direct USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, auto-rotate, download history.
- Compressed (LZW/Deflate) TIFF files without a JPEG preview show a placeholder thumbnail.

### Install
Download the attached `PhotoDownloader.exe` (or zip), unzip it anywhere and run it. No installer is needed. Settings are stored in your user config folder.

### Feedback
Report problems at https://github.com/RexAlfes/Photo-Downloader/issues. For thumbnail problems, attach `thumbnail.log` and say which camera and file type are involved.

**License:** GNU GPL v3 or later.
