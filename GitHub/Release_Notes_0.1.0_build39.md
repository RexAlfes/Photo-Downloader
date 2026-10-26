## Photo Downloader 0.1.0 – Alpha build 39

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Large folders.** With about 5,000 pictures the thumbnails stopped rendering ("Canvas does not allow drawing" in `thumbnail.log`) and the loading window stopped responding, including its Cancel button. Every thumbnail used up Windows bitmap handles, and a program can only own about 10,000. Now only the most recent 1,200 thumbnails are kept in memory and the others are drawn again when you scroll to them.
- Loading is much faster for big folders: only the first screens of ordinary pictures are rendered up front. HEIC, AVIF, TIFF and DNG thumbnails are still all rendered once and saved in the disk cache.
- Build 38 changes carry over: verified copy, backup destination, source folder at start-up.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
