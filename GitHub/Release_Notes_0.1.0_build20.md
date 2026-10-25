## Photo Downloader 0.1.0 – Alpha build 20

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Large thumbnails by default.** The program opens in large-thumbnail view, wide enough for 3 thumbnails across.
- **Wider thumbnail card.** The first line (number, file name, size) now fits in large view.
- **Optional HEIC previews.** Build with the XelImageFormats package or the HeifImage unit (-dHEIC_XEL or -dHEIC_HEIF) and keep the libheif DLLs next to the program. Without it, HEIC files are still listed, renamed and copied.
- Canon CR3 support and the other changes from build 19 carry over.

### In development
HEIC previews in the standard download, video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, auto-rotate, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
