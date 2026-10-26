# Building Photo Downloader on Linux (groundwork)

Status: built and tested on Linux Mint 22.3 (XFCE 4.18, GTK 3.24, 64-bit). Card detection, eject, safe delete, View/Empty Trash, settings, cache and the thumbnail grid work. Other distributions and widgetsets (Qt) are untested.

## Requirements
- Lazarus 3.x/4.x and Free Pascal 3.2.2 (64-bit), with the LCL GTK2 widgetset (`lcl-gtk2`; Qt5 later)
- Packages: `libgtk2.0-dev`, `libgdk-pixbuf2.0-dev`, `libcairo2-dev` (Debian/Ubuntu names)
- Runtime helpers: `udisks2` (eject), `libglib2.0-bin` (`gio`, for the trash), `xdg-utils` (`xdg-open`)

## Build
```
lazbuild --widgetset=gtk2 PhotoDownloader.lpi
```
or open `PhotoDownloader.lpi` in Lazarus and choose Run > Build. `cthreads` is already the first unit in the project file under `UNIX`, which the decoder thread needs.

## Differences from Windows
- Settings: `~/.config/<application name>/PhotoDownloader.ini`; thumbnail cache in `$XDG_CACHE_HOME` or `~/.cache/PhotoDownloader/thumbcache`.
- Card detection: devices mounted under `/media/`, `/run/media/` or `/mnt/` (read from `/proc/mounts`). The card reader drive-letter setting is hidden.
- Eject: `udisksctl`, then `gio mount -u`, then `umount`.
- Safe delete: hidden trash folder on removable media; `gio trash` on fixed disks.
- File names: Preferences > General > "Windows-safe file names" (default on) replaces characters Windows cannot store. Switch it off to keep `: ? * " < > |`.
- Single instance and USB camera download (PTP/MTP) are not available yet.
