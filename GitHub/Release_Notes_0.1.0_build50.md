## Photo Downloader 0.1.0 – Alpha build 50

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Progressive JPEG fix.** A variable mix-up in the progressive JPEG decoder (used for lossless auto-rotate) could start decoding from a wrong position. Fixed and tested.
- Compiler hints in the program's own code cleaned up.
- Linux groundwork from build 49 compiles cleanly on Windows. It has not yet been built on Linux (see `docs/Linux_Build.md`).

### In development
Video and audio files.

### Known limitations
- Linux support is untested; single-instance handling is Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
