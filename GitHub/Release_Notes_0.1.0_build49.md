## Photo Downloader 0.1.0 – Alpha build 49

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Linux groundwork.** Card detection from `/proc/mounts`, eject (udisksctl / gio / umount), safe delete through `gio trash` on fixed disks, settings in `~/.config`, thumbnail cache in `~/.cache`. See `docs/Linux_Build.md`. This code has not been compiled on Linux yet.
- **Windows-safe file names** option (Preferences > General; Linux only, always on in Windows).
- Tested and working: JPEG rotation and orientation, GIF support.

### In development
Video and audio files.

### Known limitations
- Linux support is untested; single-instance handling is Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
