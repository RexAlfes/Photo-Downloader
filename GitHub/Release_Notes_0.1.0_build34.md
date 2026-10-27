## Photo Downloader 0.1.0 – Alpha build 34

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Help > Logging** switches the diagnostic log on or off (on by default; saved in the ini file).
- **Help > Save log file...** saves the log to a folder you choose, with the program version at the top, so testers can email it.
- **File types.** Video, audio and THM are now off by default until their previews are verified. If you already have a settings file, your saved choices are kept: use View > File Types... > Clear all and tick what you want.
- **Faster.** HEIC and AVIF thumbnails use a reduced color conversion and skip the AV1 post-filters; thumbnails of these files are cached on disk (`thumbcache` folder); the program is compiled with optimization level 2.
- The export default file name is now `PhotoDownloaderSettings.ini`.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
