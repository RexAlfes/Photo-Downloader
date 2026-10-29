## Photo Downloader 0.1.0.58

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.0.58` (build 58). From the next bundle on every release raises the revision and restarts the build number at 1; the build number then counts up with each compile until the next revision.

### Highlights
- **Save .lrprev previews as JPG.** Select one or more Lightroom preview files, right-click and choose **Save .lrprev preview(s) as JPG...**. You pick a folder; each file's largest preview (at most 256 px) is written there as a `.jpg` with the same base name. The picture is saved exactly as stored in the file, not re-encoded, and an existing file is never overwritten (a number is added). The menu item appears only when .lrprev files are selected.
- **Four-digit year on the cards.** The date line now reads, for example, `10/28/2026   15:31:05   NEF   24.1 MB`. The text area beside the thumbnail is now wide enough for the whole date, type and size line, even at the smallest thumbnail size.
- **Long names on cards.** When a name does not fit, the card shows the first 8 characters, three dots and the last 8 characters (for example `DSC_0012...9876`). The file name itself is not changed. The list view is unchanged.

### Also
- **Linux: use the GTK 2 widgetset.** Build with `lazbuild --ws=gtk2 PhotoDownloader.lpi`. With the GTK 3 widgetset of Lazarus 4.8 the folder chooser raises an Access Violation and windows open in the wrong place; GTK 2 works. The GitHub check now builds the Linux version with GTK 2. Menu commands also run just after the menu has closed on Linux.
- **Linux: start-up windows.** The main window is centered again once it has its real size (GTK placed it shifted to the right and down). On Linux the splash screen closes as soon as the main window is up instead of waiting five seconds; the waiting loop let menu clicks run inside it and froze GTK 3.
- **Linux: icon on the program file.** `linux/install-desktop.sh` now also gives the `PhotoDownloader` file itself its icon in file managers that support it (Nemo, Nautilus, Caja). Use `--no-file-icon` to skip it. Run it again after rebuilding the program.
- **One project file again.** `PhotoDownloader_linux.lpi` is gone; `PhotoDownloader.lpi` no longer names a target system, so it builds for the system you are on (as before build 57). The Linux build keeps its window icon. Build on the system you want the program for (`lazbuild PhotoDownloader.lpi`); cross compiling does not work.
- The build 57 changes (thumbnail sizes, Fit to Window, cleaner cards, Lightroom previews, File Types Default button) are unchanged; see the build 57 notes.

### Downloads
- `PhotoDownloader.0.1.0.58.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.0.58.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.0.58.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.0.58.odt` and `.md` – User Manual

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
