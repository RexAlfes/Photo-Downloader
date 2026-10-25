## Photo Downloader 0.1.0 – Alpha build 36

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **File Types fix.** Nikon NEF and NRW are now separate entries, so selecting only NEF no longer shows NRW files. If your settings file has the NEF/NRW entry ticked, NRW starts ticked too.
- **Name clash text.** A file flagged "same new name" now names the file it clashes with, so you can see why. With the default pattern `RA{Y}{m}{D}-{r}` two files with the same picture number taken on the same day (for example from two camera folders) get the same name; add `{q}` (source folder) or `{t}` (time) to the pattern to tell them apart.
- Build 35 changes carry over: rescan on destination change, Help > Logging, Save log file, faster HEIC/AVIF thumbnails.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
