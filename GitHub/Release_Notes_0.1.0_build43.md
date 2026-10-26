## Photo Downloader 0.1.0 – Alpha build 43

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Safe delete.** Deleting files from the card now moves them to the Recycle Bin (fixed disks) or to a hidden `Photo Downloader Trash` folder on the same drive (cards, USB, network), so they can be restored. Switch it off in Preferences > Automation. Files are never erased if the move fails.
- **Auto-rotate of progressive JPEGs.** Progressive JPEGs with an EXIF orientation are now turned losslessly too. They are saved back as sequential JPEG files (same picture, slightly different file size).
- Verified copy, backup, cancel and resume were tested on a real card.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- Safe delete and progressive rotation are new and need testing.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
