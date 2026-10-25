# Third-party notices

Photo Downloader is licensed under the GNU GPL v3 or later (see README).

## Xelitan HEIC / HEIF / AV1 decoder (`third_party/XelHeic`)
Source: Xelitan XelImageFormats (pure Pascal; no external libraries). Bundled files:
`HeicImageX.pas`, `XelImageBase.pas`, `XelHeic.pas`, the `Heif.*`, `Av1.*` and `h265_*` units and their `.inc` tables.

* `HeicImageX.pas`, `XelHeic.pas`: header says LGPL. `XelImageBase.pas`: header says MIT.
* The HEVC (H.265) units are derived from FFmpeg (LGPL 2.1 or later). The AV1 units reference dav1d
  and the AV1 specification; their original license is not stated in the files.
* Each file keeps its original header. Replace or remove the folder to use a different decoder.

The licenses of these files have not been legally reviewed; check them before redistributing builds.

## Local changes to bundled code
* `Av1.Decoder.pas` (build 29): per-block state arrays enlarged and writes at the right/bottom picture edge clipped, to stop out-of-range writes that crashed AVIF decoding. Not sent upstream.
* `Av1.Decoder.pas` (build 33): the 4x4-block grid size now comes from the frame header (MiCols/MiRows, always even) instead of `(size+3) shr 2`; pictures whose height or width gave an odd count (e.g. 1920x2523) never finished decoding.
* `Av1.Decoder.pas` (build 34): new global `Av1SkipFilters`; when set (thumbnails only) deblocking, CDEF and loop restoration are skipped.
* `Heif.Decode.pas` (build 34): new globals `HeifTargetSide`/`HeifLastStep`; when set (thumbnails only) the YUV-to-RGB conversion samples the picture down (2x2 samples per output pixel) instead of converting every pixel.
