## Photo Downloader 0.1.0 – Alpha build 37

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Gray rows for downloaded files.** Files with the status "Already downloaded" are drawn on a gray background (blue-gray when selected), so new files stand out. Name clashes stay red.
- **Generic default folders.** The default destination is now `Pictures\Photo Downloader\{Y}\{Y}-{m}-{D}-{J}\` in your home folder and the default card reader letter is E. Existing settings files keep their saved values.
- Build 36 changes carry over: separate NEF and NRW file types, clearer name clash text, rescan on destination change, Help > Logging and Save log file, faster HEIC/AVIF thumbnails.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
