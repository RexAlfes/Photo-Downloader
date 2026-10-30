# Building Photo Downloader on Linux (groundwork)

Status: built and tested on Linux Mint 22.3 (64-bit) with the LCL GTK 2 widgetset. The GTK 3 widgetset of Lazarus 4.8 is experimental here: with it the folder chooser raises an Access Violation, windows open in the wrong place and menus can lock up. Use GTK 2. Card detection, eject, safe delete, View/Empty Trash, settings, cache and the thumbnail grid work. Other distributions and widgetsets (Qt) are untested.

## Requirements
- Lazarus 4.8 and Free Pascal 3.2.2 (64-bit), the same versions as on Windows, with the LCL GTK2 widgetset (GTK3 is experimental and not recommended; Qt5 later)
- Packages (Debian/Ubuntu/Mint names): `sudo apt install build-essential libgtk2.0-dev`. `libgtk2.0-dev` pulls in the GDK-Pixbuf, Cairo, Pango, ATK and GLib development files the LCL needs. `build-essential` supplies the linker (`ld`) that Free Pascal calls. Lazarus and Free Pascal themselves come from the Lazarus project downloads (`fpc-laz`, `fpc-src`, `lazarus-project`) or from your distribution.
- Runtime helpers: `udisks2` (eject), `libglib2.0-bin` (`gio`, for the trash), `xdg-utils` (`xdg-open`)
- Optional, for Lightroom catalogs (.lrprev files): `libsqlite3-0` (the SQLite library, loaded at run time; almost always installed). No development package is needed to build.
- Optional, for video thumbnails: `ffmpegthumbnailer` (or `ffmpeg`). Without them videos show a play-symbol tile.

## Build
The easiest way is the build script, run in the project folder:
```
linux/build.sh              # debug build -> bin/linux/PhotoDownloader
linux/build.sh release      # Release build (small) -> bin/linux-release/PhotoDownloader
linux/build.sh run          # build, then start the program (messages appear in the terminal)
```
It raises the build number in `PhotoDownloader.lpi` by one (as the Lazarus IDE does; `lazbuild` alone does not), builds with GTK 2 and prints only the errors when the build fails. Commit and push `PhotoDownloader.lpi` afterwards. If Git did not keep the file executable, run `sh linux/build.sh` instead.

The same by hand:
```
lazbuild --ws=gtk2 PhotoDownloader.lpi
```
or, to force a full rebuild:
```
lazbuild -B --ws=gtk2 PhotoDownloader.lpi
```
For files you publish, use the Release build mode (no debug information, a much smaller program in `bin/linux-release/`): `lazbuild -B --build-mode=Release --ws=gtk2 PhotoDownloader.lpi`. `--ws=gtk2` is recommended and is what the GitHub check builds (lazbuild also uses GTK 2 when no widgetset is given). In the Lazarus IDE the default widgetset on Linux is normally GTK 2 as well. The program is written to `bin/linux/PhotoDownloader`. There is one project file for both systems: it does not name a target system or processor, so it builds for the system you are on. Build on Linux itself: cross compiling from Windows to Linux does not work with the current Lazarus and Free Pascal. Tested on Linux Mint. `cthreads` is already the first unit in the project file under `UNIX`, which the decoder thread needs.

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

## Plug-in libraries on Linux
A plug-in is a `.so` file built on Linux (a Windows `.dll` does not load on Linux). The example in the repository:

```
cd plugins/example
fpc -B -Cg example_plugin.lpr          # makes libexample_plugin.so
mkdir -p "$HOME/.config/Photo Downloader/plugins"
cp libexample_plugin.so "$HOME/.config/Photo Downloader/plugins/"
```

`-Cg` makes position-independent code, which a shared library needs. The plug-in folder is the `plugins` folder next to the settings file (File > Status shows where the settings file is; on Linux it is normally `~/.config/Photo Downloader/`), or a `plugins` folder next to the program. See `docs/Plugin_Developer_Manual.md`.

## Linux test checklist (features added since the last Linux test, 0.1.0.58)
Build with `lazbuild -B --ws=gtk2 PhotoDownloader.lpi`, start `bin/linux/PhotoDownloader` from a terminal (messages appear there), and turn on Help > Logging.

| # | Test | Expected |
|---|---|---|
| 1 | Start the program | Splash, then the job code window; no error messages in the terminal |
| 2 | File > Status | Settings file under `~/.config/...`; "SQLite library" line names `libsqlite3.so.0` (or says it is missing) |
| 3 | Open a card or folder with JPG, RAW/DNG, MP4 and LRV files | Thumbnails, dates and camera names; a second scan of the same folder is much faster (EXIF cache) |
| 4 | Lightroom previews (.lrprev) with Preferences > General "Scan Lightroom preview folders" on | Previews listed with the photo's name and date when the catalog is next to the `.lrdata` folder |
| 5 | Download Path tab: folder `.../{Y}/{E}/`, file `{o}-{e}` | Example line shows `JPG` / `jpg`; files land in one folder per type |
| 6 | Select a few files, **Download Selected**; then **Download All** | Only the selected files first, then the rest; the buttons are greyed out when there is nothing to download |
| 7 | File > Plug-ins... | Preferences opens on the Plug-ins tab |
| 8 | Install the example plug-in (above), restart, switch it on | Confirmation with the `.so` path; the list shows "Example Plug-in"; Setup... opens its window (labels right-aligned, red centered reminder, version in the title) |
| 9 | Use `{Example.Site}-{Example.Name}` as file name and download | Files named for example `NORTH-DJI_0001.JPG` |
| 10 | Delete the `.so` file and restart | The plug-in leaves the list |
| 11 | File > User Profiles > Save, then Load (double-click) | Save lists the profiles and suggests the one in use; replacing asks first; Load restores the plug-in settings |
| 12 | Settings with a `{T}` or `{q}` folder and a non-ASCII folder name (for example `Ü`) | Folders are made and files copied |
