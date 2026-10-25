## Photo Downloader 0.1.0 – Alpha build 21

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Auto-rotate.** With *Auto-rotate JPEGs after downloading* switched on (Preferences > General, on by default), downloaded JPEGs are turned upright by their EXIF orientation **without any loss of quality**: the compressed picture data is rearranged, not re-encoded. The orientation tag is reset so the picture is not turned twice.
- **Upright thumbnails and viewer.** Portrait pictures now show the right way up in the thumbnails and in the viewer, including RAW, CR3 and TIFF/DNG previews.
- **HEIC.** Supported with an optional add-on (the XelImageFormats package or the HeifImage unit, plus the libheif DLLs). Without it HEIC files are still listed, renamed and copied. The README has the steps.
- Large-thumbnail default view, wider thumbnail card and Canon CR3 support from builds 19 and 20 carry over.

### Good to know
- Lossless rotation works on 8-bit baseline JPEGs. Progressive JPEGs are left as they are.
- As with the `jpegtran -trim` tool, up to 15 pixel rows or columns that do not fill a complete block are trimmed on the edge that ends up mirrored. Pictures whose size is a multiple of 16 lose nothing.
- The small EXIF thumbnail inside the JPEG is not turned.
- Please report any picture that shows sideways or upside down, with the camera model.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, MD5-verified copy, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
