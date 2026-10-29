## Photo Downloader 0.1.1.1

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.1.1` (revision 1, build 1). Every release raises the revision and restarts the build number at 1; the build number then counts up with each compile until the next release.

### Highlights
- **Linux: use the GTK 2 widgetset.** Build with `lazbuild --ws=gtk2 PhotoDownloader.lpi` (packages `build-essential libgtk2.0-dev`). With the GTK 3 widgetset of Lazarus 4.8 the folder chooser raised an Access Violation and windows opened in the wrong place; GTK 2 works. The GitHub check now builds the Linux version with GTK 2.
- **Linux: start-up windows.** The main window is centered again once it has its real size, a window that came out too short is restored to its wanted height, and the splash screen closes as soon as the main window is up (Windows keeps the five-second splash). Menu commands also run just after the menu has closed on Linux.
- **Documentation.** `Two_Computers_Guide.txt` explains working with Git and GitHub on two computers; `.gitattributes` keeps line endings the same on Windows and Linux.

### Downloads
- `PhotoDownloader.0.1.1.1.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.1.1.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.1.1.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.1.1.odt` and `.md` – User Manual

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
