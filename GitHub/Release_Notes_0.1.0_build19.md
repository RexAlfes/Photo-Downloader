## Photo Downloader 0.1.0 – Alpha build 19

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Canon CR3.** Camera, date, ISO and body serial are now read from the file, so token naming, duplicate and name-clash checks work. Thumbnails and the viewer use the full-size JPEG preview stored in the file.
- **HEIC / HEIF.** Camera and date are read from the file's EXIF data, so renaming and duplicate checks work. The image preview is **in development** (HEVC decoding); a labelled placeholder is shown meanwhile.
- **Support links** and **cleaner build** from earlier alphas carry over.

### In development
HEIC image previews, video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, auto-rotate, download history.
- Compressed (LZW/Deflate) TIFF files without a JPEG preview show a placeholder thumbnail.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues – for thumbnail problems attach `thumbnail.log` and name the camera and file type.

**License:** GNU GPL v3 or later.
