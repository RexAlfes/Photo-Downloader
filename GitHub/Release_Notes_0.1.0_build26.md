## Photo Downloader 0.1.0 – Alpha build 26

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
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
