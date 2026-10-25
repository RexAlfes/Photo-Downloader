# Photo Downloader

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
![Status: alpha](https://img.shields.io/badge/status-alpha-yellow.svg)

A free, open source Windows desktop tool that copies photos from memory cards and folders,
renames them from templates and files them into job-code folders. Written in Lazarus 4.8 / Free Pascal 3.2.2.

Website: <https://rexalfes.github.io/Photo-Downloader/> | Downloads: <https://github.com/RexAlfes/Photo-Downloader/releases> | Issues: <https://github.com/RexAlfes/Photo-Downloader/issues>

> **Alpha software.** Keep your original files until you have checked the copies.

## Features
- Date / job-code list, thumbnail grid (small and large) and list view, image viewer, status line.
- Job Code dialog at start-up with history and a live example of the destination path.
- Token-based folder and file naming (`{T8}`, `{T9}`, `{r}`, sequence numbers, camera and EXIF values), per-camera mapping.
- Thumbnails and viewer for JPEG, PNG, BMP, TIFF, DNG and the embedded previews of RAW files (NEF, NRW, CR2, CR3, CRW, ARW and others).
- Status per image: new file, already downloaded, name clash, duplicate (same size, time and camera), with the reason shown.
- XMP sidecar from IPTC/XMP details; author and copyright written only into JPEG fields that are empty.
- Delete from the card only for files that were downloaded and exist in the destination.
- Auto-rotate: pictures are shown upright, and downloaded JPEGs can be turned losslessly by their EXIF orientation (Preferences > General).
- User profiles, export of settings, Eject, right-click Open image location and Properties.
- Single instance by default (switchable in Preferences > General). Nothing is scanned at start-up; the last folder is remembered.

## Build
Open `PhotoDownloader.lpi` in Lazarus 4.8 and press F9, or run:

    lazbuild PhotoDownloader.lpi

Forms are created in code (no `.lfm` files). Required packages: LCL and LazUtils.
Settings live in the per-user config folder (`PhotoDownloader.ini`, `profiles\`).

**64-bit.** Photo Downloader is built and tested as a 64-bit Windows program. A 32-bit build is not provided at this time; if you need one, request it through the GitHub testing process (open an issue) or the online testing form.

## HEIC and AVIF previews
HEIC / HEIF / AVIF pictures are shown in thumbnails and the viewer with no extra software, DLLs or compiler
settings. The decoder is the pure-Pascal Xelitan HEIC decoder, bundled in `third_party/XelHeic`
(see `THIRD_PARTY_NOTICES.md`). The project does **not** need the `XelImageFormats` package; if you added it
under Project > Project Inspector > Required Packages, remove it so units are not found twice.

## File type filter
Use View > File Types... (or the right-click menu) to choose which kinds of files are listed and downloaded: JPEG, PNG, BMP, TIFF, RAW by brand, DNG, HEIC, AVIF, video, audio and THM. All are selected by default except video, audio and THM (switched off until their previews are verified); **Clear all** and **Select all** are provided. The choice is kept in `PhotoDownloader.ini`.

Files that are already downloaded are shown on a grey background; name clashes are red.

## Logging and troubleshooting
Help > Logging switches the diagnostic log on or off (on by default). Help > Save log file... copies the log to a folder of your choice so you can email it. HEIC and AVIF thumbnails are cached in the `thumbcache` folder next to the settings file, so reopening a folder is much faster.

## Known limitations
- In development: video and audio files. HEIC previews are supported (bundled decoder).
- Windows is the primary platform. Card-reader detection, eject and single-instance handling are Windows only.
- Not implemented yet: direct USB camera (PTP/MTP) download, GPS geotagging, MD5-verified copy, watch mode,
  auto-rotate of progressive JPEGs, embedded IIM/IPTC (XMP is written as a `.xmp` sidecar), download history.
- Compressed (LZW/Deflate) TIFF files with no JPEG preview show a placeholder thumbnail.
- {r} (image number) is the longest run of digits in the original name (last on a tie).
- The code is compiled and tested by the project owner; report compiler messages or bugs as issues.

## Settings file
Settings are stored in `PhotoDownloader.ini` in the per-user configuration folder, for example
`%LOCALAPPDATA%\<application name>\PhotoDownloader.ini` on Windows and `~/.config/<application name>/PhotoDownloader.ini` on Linux.
The Status dialog shows the exact path. Saved user profiles are in a `profiles` folder next to it (same format), and
`thumbnail.log` (written only when a picture cannot be previewed) is in the same folder. The file is plain UTF-8 text with
`[Section]` headers and `Key=Value` lines; missing keys use their defaults, so deleting the file (program closed) resets everything.
The full list of sections, keys, types and defaults is in `docs/Settings_File.md` (also section 5 of `docs/Specification_Current.md`).

## Versioning
Version info is enabled with "Automatically increment build number". The IDE increments the number on each build; `lazbuild` does not.
The version is shown in About, Status and Register. See `docs/Specification_Current.md` for the version history.

## Support
Photo Downloader is free. If it saves you time, an optional donation helps: [PayPal](https://paypal.me/PhotoDownLoader) or [Venmo](https://venmo.com/u/RexAlfes) (US). Donations do not unlock anything.

## License
GNU General Public License v3 or later; the notice is shown in Help > Register.
Add the full license text as `COPYING` before distributing.

## Documentation
`docs/Specification_Current.odt` (and `.md`) describe the current functions and their status.
