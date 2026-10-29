## Photo Downloader 0.1.0 – Alpha build 38

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Verified copy.** Every file is read back after copying and its checksum (MD5) is compared with the original. A bad copy is deleted and retried once; if it still fails the download stops with a message and the file is not marked downloaded. On by default (Preferences > Download Path).
- **Backup destination.** Optionally save a second copy of every file to a backup folder (same folder and file name patterns), made from the verified download before rotation or metadata changes and verified the same way. If a backup copy fails, that file is never offered for deletion from the image source. This replaces the old Backup plug-in.
- Cancel now also stops a copy in the middle of a large file.
- **Source folder at start-up.** The job code window shown at start-up also asks for the source folder (leave it empty to choose later).
- Documentation: planned features and the Linux version are listed in the specification; note on very large folders.
- Please test: a card with many files, a backup folder on another drive, and canceling in the middle of a download.
- Build 37 changes carry over: gray rows for downloaded files, generic default folders, separate NEF/NRW types, Help > Logging, faster HEIC/AVIF thumbnails.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
