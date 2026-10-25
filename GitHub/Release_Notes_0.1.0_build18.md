## Photo Downloader 0.1.0 – Alpha build 18

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new since build 15
- **Support links.** Optional PayPal and Venmo donation links in the Help menu, on the website and in the README. The program stays free: no subscription, no paid upgrade, no license key.
- **Custom button.** The unused "link to third-party browser" option was removed; the custom button still launches any program you choose.
- **Cleaner build.** Compiler hints in the single-instance code are fixed.
- **Documentation.** Specification, launch materials, README and website refreshed.

### Included from earlier alphas
Sharper viewer, TIFF/DNG/RAW previews, single-instance option, token naming, duplicate and name-clash detection, XMP sidecars, safe delete, profiles. See the build 15 notes for details.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, auto-rotate, download history.
- Compressed (LZW/Deflate) TIFF files without a JPEG preview show a placeholder thumbnail.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues – for thumbnail problems attach `thumbnail.log` and name the camera and file type.

**License:** GNU GPL v3 or later.
