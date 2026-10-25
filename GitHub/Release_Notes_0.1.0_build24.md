## Photo Downloader 0.1.0 – Alpha build 24

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **64-bit.** Photo Downloader is a 64-bit Windows program (and the optional HEIC add-on needs the 64-bit libheif DLLs). A 32-bit build is not provided at this time; request one through the GitHub testing process (open an issue) or the online testing form.
- **HEIC rotation check.** Nine more HEIC files (portrait and landscape, Apple and Samsung) were checked: camera, date and orientation are read correctly. If a HEIC picture asks for a quarter turn but the decoder returns it unturned, the program now turns it itself, so portrait pictures show upright either way.
- Earlier builds' changes carry over: start-up window sizing, lossless auto-rotate, upright previews, Canon CR3, optional HEIC previews, settings file documentation.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
