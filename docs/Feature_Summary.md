---
title: "Photo Downloader: Feature Summary"
subtitle: "Version 0.1.5, November 2026"
---

# Photo Downloader

A free, open source (GPL v3) desktop program that copies photos and videos from memory cards, drones and folders, names them from templates and files them into project folders, then checks every copy.

- Runs on Windows 64-bit and Linux (GTK 2).
- Alpha software: keep the originals until the copies are checked.

## Copy safely

- Verified copy: each file is read back and its checksum compared.
- Optional second copy to a backup folder.
- Status per file: new, already downloaded, name clash, duplicate.
- Delete from the card only what was downloaded; safe delete moves files to the Recycle Bin or a trash folder on the card.
- Cancel and resume; nothing is scanned until you ask.

## Name and file automatically

- Folder and file names from tokens: date, time, camera, serial number, job code, sequence numbers.
- `{Type}` gives one folder per file type and keeps drone thermal files apart (JPG-IR, MP4-IR, JPG-IR-R).
- Job code at start-up, per date, or blank.
- Per-camera mapping and user profiles for repeat projects.

## See before you copy

- Thumbnails, list view and a full viewer; Ctrl+F fits the thumbnails to the window.
- JPEG, PNG, TIFF, WebP, HEIC/AVIF, DNG and the previews of RAW files (Nikon, Canon, Sony and others).
- Video and audio with capture date and length.
- File type filter and a date list.

## Process and extend

- Lossless auto-rotate of JPEGs; author and copyright written only where they are empty.
- XMP sidecars from IPTC details; a color profile per camera.
- Plug-ins: libraries add tokens and their own setup window; program plug-ins such as DNG conversion run after each file.
- Plug-ins can name folders to be copied whole, every file kept as it is.

## Good to know

- The Windows program is not code-signed, so Windows asks before the first start (**More info**, then **Run anyway**).
- Downloads, the User Manual and issue reports: <https://github.com/RexAlfes/Photo-Downloader>
