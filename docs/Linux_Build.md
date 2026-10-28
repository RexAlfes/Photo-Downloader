# Building Photo Downloader on Linux (groundwork)

Status: built and tested on Linux Mint 22.3 (XFCE 4.18, GTK 3.24, 64-bit). Card detection, eject, safe delete, View/Empty Trash, settings, cache and the thumbnail grid work. Other distributions and widgetsets (Qt) are untested.

## Requirements
- Lazarus 4.8 and Free Pascal 3.2.2 (64-bit), the same versions as on Windows, with the LCL GTK3 (or GTK2) widgetset (Qt5 later)
- Packages for the GTK 3 widgetset (Debian/Ubuntu/Mint names): `sudo apt install build-essential libgtk-3-dev`. `libgtk-3-dev` pulls in the GDK-Pixbuf, Cairo, Pango, ATK and GLib development files the LCL needs. `build-essential` supplies the linker (`ld`) that Free Pascal calls. Lazarus and Free Pascal themselves come from the Lazarus project downloads (`fpc-laz`, `fpc-src`, `lazarus-project`) or from your distribution.
- For GTK 2 instead: `libgtk2.0-dev` (with `libgdk-pixbuf2.0-dev` and `libcairo2-dev`).
- Runtime helpers: `udisks2` (eject), `libglib2.0-bin` (`gio`, for the trash), `xdg-utils` (`xdg-open`)
- Optional, for video thumbnails: `ffmpegthumbnailer` (or `ffmpeg`). Without them videos show a play-symbol tile.

## Build
```
lazbuild PhotoDownloader.lpi
```
or, to force a full rebuild:
```
lazbuild -B PhotoDownloader.lpi
```
or open `PhotoDownloader.lpi` in Lazarus and choose Run > Build. There is one project file for both systems: it does not name a target system or processor, so it builds for the system you are on (on Linux the program is written to `bin/linux/PhotoDownloader` and uses the default widgetset, GTK 3 when Lazarus is installed with it). Add `--widgetset=gtk3` (or `gtk2`) if you want to choose the widgetset explicitly. Build on Linux itself: cross compiling from Windows to Linux does not work with the current Lazarus and Free Pascal. Tested on Linux Mint. `cthreads` is already the first unit in the project file under `UNIX`, which the decoder thread needs.

## Differences from Windows
- Settings: `~/.config/<application name>/PhotoDownloader.ini`; thumbnail cache in `$XDG_CACHE_HOME` or `~/.cache/PhotoDownloader/thumbcache`.
- Card detection: devices mounted under `/media/`, `/run/media/` or `/mnt/` (read from `/proc/mounts`). The card reader drive-letter setting is hidden.
- Eject: `udisksctl`, then `gio mount -u`, then `umount`.
- Safe delete: hidden trash folder on removable media; `gio trash` on fixed disks.
- File names: Preferences > File Handling > "Windows-safe file names" (default on) replaces characters Windows cannot store. Switch it off to keep `: ? * " < > |`.
- Single instance and USB camera download (PTP/MTP) are not available yet.

## Menu entry and icon
A Linux executable cannot carry the icon that file managers and launchers show, so Photo Downloader ships a small launcher kit in the `linux/` folder (`PhotoDownloader.desktop`, `install-desktop.sh` and `icons/`). After building (or unpacking the release), run:

```
cd linux
./install-desktop.sh /full/path/to/PhotoDownloader
```

The script puts the icon into `~/.local/share/icons/hicolor/` and a launcher into `~/.local/share/applications/`, so Photo Downloader appears in the application menu with its icon, and the taskbar groups its windows under that icon. The script also sets a custom icon on the program file itself with `gio set` (file managers such as Nemo, Nautilus and Caja show it; refresh with F5). That icon is lost when the file is rebuilt or copied, so run the script again after a rebuild. Add `--no-file-icon` to skip this step. `./install-desktop.sh --remove [/full/path/to/PhotoDownloader]` undoes everything. The program also loads its window icon from its own resource at start-up.
