# Photo Downloader

[![Licence: GPL v3](https://img.shields.io/badge/licence-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
![Status: alpha](https://img.shields.io/badge/status-alpha-yellow.svg)

A free, open source Windows desktop tool that copies photos from memory cards and folders,
renames them from templates and files them into job-code folders. Written in Lazarus 4.8 / Free Pascal 3.2.2.

Website: <https://rexalfes.github.io/Photo-Downloader/> | Downloads: <https://github.com/RexAlfes/Photo-Downloader/releases> | Issues: <https://github.com/RexAlfes/Photo-Downloader/issues>

> **Alpha software.** Keep your original files until you have checked the copies.

## Features
- Date / job-code list, thumbnail grid (small and large) and list view, image viewer, status line.
- Job Code dialog at start-up with history and a live example of the destination path.
- Token-based folder and file naming (`{T8}`, `{T9}`, `{r}`, sequence numbers, camera and EXIF values), per-camera mapping.
- Thumbnails and viewer for JPEG, PNG, BMP, TIFF, DNG and the embedded previews of RAW files (NEF, NRW, CR2, CRW, ARW and others).
- Status per image: new file, already downloaded, name clash, duplicate (same size, time and camera), with the reason shown.
- XMP sidecar from IPTC/XMP details; author and copyright written only into JPEG fields that are empty.
- Delete from the card only for files that were downloaded and exist in the destination.
- User profiles, export of settings, Eject, right-click Open image location and Properties.
- Single instance by default (switchable in Preferences > General). Nothing is scanned at start-up; the last folder is remembered.

## Build
Open `PhotoDownloader.lpi` in Lazarus 4.8 and press F9, or run:

    lazbuild PhotoDownloader.lpi

Forms are created in code (no `.lfm` files). Required packages: LCL and LazUtils.
Settings live in the per-user config folder (`PhotoDownloader.ini`, `profiles\`).

## Known limitations
- Windows is the primary platform. Card-reader detection, eject and single-instance handling are Windows only.
- Not implemented yet: direct USB camera (PTP/MTP) download, GPS geotagging, MD5-verified copy, watch mode,
  lossless auto-rotate, embedded IIM/IPTC (XMP is written as a `.xmp` sidecar), download history.
- Compressed (LZW/Deflate) TIFF files with no JPEG preview show a placeholder thumbnail.
- {r} (image number) is the longest run of digits in the original name (last on a tie).
- The code is compiled and tested by the project owner; report compiler messages or bugs as issues.

## Versioning
Version info is enabled with "Automatically increment build number". The IDE increments the number on each build; `lazbuild` does not.
The version is shown in About, Status and Register. See `docs/Specification_Current.md` for the version history.

## Licence
GNU General Public License v3 or later; the notice is shown in Help > Register.
Add the full licence text as `COPYING` before distributing.

## Documentation
`docs/Specification_Current.odt` (and `.md`) describe the current functions and their status.
