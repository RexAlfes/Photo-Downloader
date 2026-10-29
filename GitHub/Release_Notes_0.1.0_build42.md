## Photo Downloader 0.1.0 – Alpha build 42 (baseline)

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Baseline build.** No functional change from build 41. This is the reference point for later work (suggested tag `baseline-build-42`).
- Code cleanup: unused variables and units removed from the TIFF reader, HEIC loader and Preferences code.
- All documentation checked and brought up to date (README, specification, settings file reference, launch materials, website).

### Highlights of the baseline
- Thumbnails and viewer for JPEG, PNG, BMP, TIFF (LZW, PackBits, Deflate, fax, palette, 1-bit, CMYK), DNG, HEIC, AVIF and RAW previews.
- Verified copy (checksum read-back) and optional backup folder.
- File type filter, logging with Save log file, start-up job code and source folder, gray rows for already downloaded files.
- Large folders (about 6,000 pictures tested).

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- TIFF with JPEG compression, planar layout, floating point or BigTIFF shows a placeholder.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
