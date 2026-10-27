## Photo Downloader 0.1.0 – Alpha build 33

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **AVIF fix for odd sizes.** Pictures whose size does not divide evenly into 8-pixel blocks (for example 1920x2523) never finished decoding, which is why one file kept the loading window busy until the time-out. The decoder now uses the block counts from the picture header.
- **HEIC/AVIF no longer freeze the window.** Decoding now runs in a worker thread, so the loading window keeps updating and Cancel works. A decode that runs for more than 2 minutes (or 30 seconds after Cancel) is given up, logged in `thumbnail.log`, and HEIC/AVIF previews stay off until the program is restarted.
- Decoded pictures are reduced to thumbnail size inside the thread, which makes loading faster.
- **Two progress bars when loading.** Opening a source folder shows one bar for reading the files and one for rendering the thumbnails, with a Cancel button. Thumbnails are now rendered up front, so the window no longer freezes while it paints (large AVIF files take a while to decode).
- **AVIF.** The deblocking step can no longer read outside the picture buffer. If a file still fails, `thumbnail.log` shows the line.
- **File type filter.** View > File Types... (also on the right-click menu) lists and downloads only the file types you tick. All are on by default; Select all and Clear all buttons; saved in the ini file.
- **Progress pop-ups.** A pop-up with a Cancel button shows while the source folder is read, and the download pop-up now follows the size of the files copied.
- **AVIF.** Second fix to the bundled decoder (the deblocking step read past the end of the picture buffer). Please re-test your AVIF files and send `thumbnail.log` if any still show a gray box.
- Earlier builds' changes carry over: bundled HEIC decoder, AVIF listing, decoder edge fix, 64-bit note, lossless auto-rotate, Canon CR3, settings file documentation.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
