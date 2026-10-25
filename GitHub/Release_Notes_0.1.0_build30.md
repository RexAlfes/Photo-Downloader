## Photo Downloader 0.1.0 – Alpha build 30

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **File type filter.** View > File Types... (also on the right-click menu) lists and downloads only the file types you tick. All are on by default; Select all and Clear all buttons; saved in the ini file.
- **Progress pop-ups.** A pop-up with a Cancel button shows while the source folder is read, and the download pop-up now follows the size of the files copied.
- **AVIF.** Second fix to the bundled decoder (the deblocking step read past the end of the picture buffer). Please re-test your AVIF files and send `thumbnail.log` if any still show a grey box.
- Earlier builds' changes carry over: bundled HEIC decoder, AVIF listing, decoder edge fix, 64-bit note, lossless auto-rotate, Canon CR3, settings file documentation.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
