## Photo Downloader 0.1.4

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.4.1` (revision 4, build 1). Every release raises the revision and restarts the build number at 1; the build number then counts up with each compile until the next release. Documents name only the version, `0.1.4`.

### Highlights
- **Editable lists in plug-in windows.** A plug-in can give a list field an **Edit list...** button. The list editor keeps each entry as a short code (letters and digits, a plug-in may require an exact length) and a short descriptor, with Add, Replace selected, Remove, Move up, Move down and Defaults, all in one window. The edited list is kept with the plug-in's values (also in user profiles). The Plug-in Developer Manual explains the new field flags `edit` and `code=N`.
- **The title bar shows the user profile in use**, right after the program name, for example **Photo Downloader - Profile: Bridges - Folder E:\DCIM**.
- **Easier to read.** The reminder and error texts in plug-in windows are dark red and the version text dark gray, with a contrast of at least 4.5:1.
- **Linux.** Long drop-down lists (for example 67 counties) now open below their box with a scroll bar instead of filling the screen. New build script `linux/build.sh` (debug, release, run): it gets the newest version from GitHub first and sends the new build number back afterwards, so Windows and Linux count on from the same number.
- **Two computers.** `GitHub/Two_Computers_Guide.txt` now explains signing in to GitHub on Linux with a personal access token, and what to check when GitHub Desktop seems to pull nothing.

### Downloads
- `PhotoDownloader.0.1.4.1.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.4.1.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.4.1.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.4.docx`, `.odt` and `.md` – User Manual
- `Plugin_Developer_Manual.0.1.4.docx`, `.odt` and `.md` – for writing plug-ins

### Tested
Windows 11 and Linux Mint 22.3 (GTK 2): every change above, in the program, by the user.

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
