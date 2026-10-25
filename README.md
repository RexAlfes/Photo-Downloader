# Photo Downloader (Lazarus 4.8 / FPC 3.2.2)

Desktop photo downloader built from the screenshots in `Photo_Downloader_Specs.zip`.

## Build
Open `PhotoDownloader.lpi` in Lazarus and press F9, or run:

    lazbuild PhotoDownloader.lpi

Forms are created in code (no .lfm files). Only the LCL package is required.
Settings are stored in the per-user config folder (`PhotoDownloader.ini`, `profiles\`).

## Implemented (from the screenshots)
- Main window: Date - Job code list, thumbnail grid (small / large) and list view,
  status line, Download / Delete / Close (+ optional custom button).
- Job Code dialog at startup with history, Delete, live example path, Preferences...
- File, Edit, View and Help menus with the shortcuts shown; User Profiles load/save/delete;
  Export settings; Status; Refresh (F5); Eject (F6, Windows/`eject`); auto sequence (F4).
- Preferences: Download Path (tokens, sequence number), General, Automation,
  Custom button, Mapping ({T8}/{T9} per camera), Plug-ins.
- EXIF date/camera/ISO/serial read from JPEG and TIFF-based raw files.
- Status per image: New file, Already downloaded, Name clash (red), Duplicate file.

## Not implemented / assumptions
- `Specifications.odt` was NOT in the zip (only its lock file), so behaviour is inferred from screenshots.
- {r} (image number) rule is a guess: first run of 4+ digits in the original name, else last digit run.
- Not implemented: direct camera (PTP) download, lossless JPEG auto-rotate, IIM/embedded IPTC
  (XMP is written as a `.xmp` sidecar), GPS geotagging, Breeze link, plug-ins
  "JPEG auto profile", "DNG Converter", "JPEG resolution" (Backup and Directory Maker work).
- Raw files show a blank thumbnail (as in the NEF example in the screenshot).
- Auto-detect of card readers is Windows-only; elsewhere use File > Open Source Directory.
- The code has not been compiled by the author's tooling; expect to fix a few small compile errors.

## Versioning
Version info is enabled in the project (Project > Project Options > Version Info) with
"Automatically increment build number" ON. The .lpi stores 0.1.0 build 4 so the next build made
in the Lazarus IDE is 0.1.0 build 5. Only the IDE increments the number, not `lazbuild`.
The version is shown in About, Status and Register (read from the compiled resource).

## License
GNU General Public License v3 or later; the notice is shown in Help > Register.
Add a copy of the full license text as `COPYING` before distributing.

## Notes
- {r} (image number) = longest run of digits in the original name (last on a tie); a name with no digits uses the whole name.
- Name-clash cards state the reason, e.g. "same new name as #3".
- RAW thumbnails come from the JPEG preview embedded in the file; portrait previews are not rotated yet.
- EXIF author/copyright are only written into fields that are empty or missing in the downloaded JPEG.

## Documentation
`docs/Specification_Current.odt` (and `.md`) describe the current functions and their status (build 9).
Each delivered update raises the stored build number by one; the IDE then increments it again when you build.
