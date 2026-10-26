## Photo Downloader 0.1.0 – Alpha build 48

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **GIF files.** GIF is now a file type (View > File Types): listed, copied, and shown in thumbnails and the viewer (first frame; animation is not played).
- **Orientation-only EXIF.** Pictures whose EXIF holds only an orientation (no camera or date) were shown and downloaded unturned. The orientation is now read, so they display upright. If a downloaded JPEG cannot be turned upright, the log says why.
- **Default file name** is now `{o}` (the original file name).
- Tested and working: user profiles, progressive JPEG handling, safe delete, View/Empty Trash, blank job code, start-up profile prompt.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- GIF support and rotation of orientation-only JPEGs need more testing.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
