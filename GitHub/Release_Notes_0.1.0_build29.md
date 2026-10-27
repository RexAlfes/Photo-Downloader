## Photo Downloader 0.1.0 – Alpha build 29

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **AVIF fix.** The bundled AV1 decoder wrote outside its arrays at picture edges and for pictures wider than about 1000 px, which crashed the decode and corrupted later ones. Patched; AVIF thumbnails and the viewer should now work.
- **AVIF diagnostics (2).** thumbnail.log now adds the source file and line where a HEIC/AVIF decode failed (the project now compiles with line info, `-g -gl`). Current finding: AVIF decoding raises an access violation.
- **AVIF diagnostics.** A HEIC/AVIF file that cannot be decoded now logs the reason in `thumbnail.log`. Some AVIF files still show a gray placeholder; please send the log line.
- **AVIF files** (`.avif`) are now listed, copied and shown in thumbnails and the viewer. They were missing from the file-type list.
- **HEIC previews are built in.** The pure-Pascal Xelitan HEIC decoder is now part of the source (`third_party/XelHeic`). No DLLs, no extra packages and no compiler settings are needed; the optional add-on steps are gone. If you added `XelImageFormats` as a required package, remove it.
- **Third-party notices.** See `THIRD_PARTY_NOTICES.md`.
- Earlier builds' changes carry over: 64-bit note, start-up window sizing, lossless auto-rotate, upright previews, Canon CR3, settings file documentation.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
