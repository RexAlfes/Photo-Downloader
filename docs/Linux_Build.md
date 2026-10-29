# Building Photo Downloader on Linux (groundwork)

Status: built and tested on Linux Mint 22.3 (64-bit) with the LCL GTK 2 widgetset. The GTK 3 widgetset of Lazarus 4.8 is experimental here: with it the folder chooser raises an Access Violation, windows open in the wrong place and menus can lock up. Use GTK 2. Card detection, eject, safe delete, View/Empty Trash, settings, cache and the thumbnail grid work. Other distributions and widgetsets (Qt) are untested.

## Requirements
- Lazarus 4.8 and Free Pascal 3.2.2 (64-bit), the same versions as on Windows, with the LCL GTK2 widgetset (GTK3 is experimental and not recommended; Qt5 later)
- Packages (Debian/Ubuntu/Mint names): `sudo apt install build-essential libgtk2.0-dev`. `libgtk2.0-dev` pulls in the GDK-Pixbuf, Cairo, Pango, ATK and GLib development files the LCL needs. `build-essential` supplies the linker (`ld`) that Free Pascal calls. Lazarus and Free Pascal themselves come from the Lazarus project downloads (`fpc-laz`, `fpc-src`, `lazarus-project`) or from your distribution.
- Runtime helpers: `udisks2` (eject), `libglib2.0-bin` (`gio`, for the trash), `xdg-utils` (`xdg-open`)
- Optional, for video thumbnails: `ffmpegthumbnailer` (or `ffmpeg`). Without them videos show a play-symbol tile.

## Build
```
lazbuild --ws=gtk2 PhotoDownloader.lpi
```
or, to force a full rebuild:
```
lazbuild -B --ws=gtk2 PhotoDownloader.lpi
```
`--ws=gtk2` is recommended and is what the GitHub check builds (lazbuild also uses GTK 2 when no widgetset is given). In the Lazarus IDE the default widgetset on Linux is normally GTK 2 as well. The program is written to `bin/linux/PhotoDownloader`. There is one project file for both systems: it does not name a target system or processor, so it builds for the system you are on. Build on Linux itself: cross compiling from Windows to Linux does not work with the current Lazarus and Free Pascal. Tested on Linux Mint. `cthreads` is already the first unit in the project file under `UNIX`, which the decoder thread needs.

## Differences from Windows
- Settings: `~/.config/<application name>/PhotoDownloader.ini`; thumbnail cache in `$XDG_CACHE_HOME` or `~/.cache/PhotoDownloader/thumbcache`, EXIF cache `exifcache.txt` beside it.
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
