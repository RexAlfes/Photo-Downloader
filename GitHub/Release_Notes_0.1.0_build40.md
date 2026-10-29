## Photo Downloader 0.1.0 – Alpha build 40

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **TIFF scans.** A new TIFF reader makes thumbnails for TIFF files that had only a gray placeholder: LZW, PackBits, Deflate and CCITT fax (Group 3 / Group 4) compression, 1-bit black-and-white scans (drawings, plans), palette, 16-bit and CMYK, stored in strips or tiles. Large scans are read strip by strip and averaged down, so thin lines in 1-bit drawings stay visible.
- Not supported yet: JPEG-compressed TIFF, planar layout, floating point samples, BigTIFF. `thumbnail.log` now says why a TIFF could not be read.
- A file with the extension .png or .bmp that is really a TIFF or a JPEG is now recognized by its content.
- Build 39 changes carry over: large-folder fix (thumbnail handle limit), verified copy, backup destination.
- Please test with your scanned TIFFs and send `thumbnail.log` for any that still show a gray box.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
