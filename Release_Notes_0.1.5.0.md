## Photo Downloader 0.1.5

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.5.0` (revision 5, build 0). Every release raises the revision and restarts the build number at 0. Between releases the build number goes up by one for each change of the program code; the debug and Release builds of the same code, on Windows and on Linux, carry the same number. Documents name only the version, `0.1.5`.

### Highlights
- **Phones, cameras and drone controllers by USB (Windows).** **File > Import from Device...** (Ctrl+Shift+O) lists the connected devices and their folders (DCIM ticked; Select All and Clear All). The chosen folders are copied to a staging folder on the computer, each copy checked (MD5) and given the device's date, and then shown like a card. Importing again copies only new pictures; Refresh imports again; Delete removes downloaded pictures from the device itself; Eject ends the device as the source. Choosing a phone or camera in **File > Open Source Folder** imports from it too. Tested with a Nikon D700, an Android phone and a Skydio drone controller.
- **Light and dark theme.** **View > Theme**: Follow Windows (Follow System on Linux), Light or Dark. On Windows, menus, buttons, dialog windows and the title bar are dark too; on Linux the program uses the dark or light version of your desktop's GTK theme (for example Mint-Y-Dark). Every text keeps a contrast of at least 4.5:1. Changing the theme offers to restart the program.
- **User profiles in one window.** **File > User Profiles...** loads, saves, saves under another name, creates and deletes profiles; double-clicking a profile loads it and closes the window. The Default profile is used when none is chosen, the program asks about unsaved profile changes when it closes, and loading a profile keeps the theme and view.
- **Scan cards.** Each scan in a drone's `scans` folder (for example a Skydio scan) is shown as one card and is selected, downloaded and deleted as a whole.
- **Dates.** Photos and videos stamped in UTC get local times (with summer time by date), and copies keep the original's creation date.
- **{Type} token.** A folder per type of file (JPG, MP4, ...), with thermal files apart.
- **Plug-ins.** A folder structure field, a changeable note, radio fields and lists sent by the plug-in, tokens that may hold folders, extra source folders and folders copied whole (see the Plug-in Developer Manual).
- **Crash log.** An error message such as "Access violation" is first written with its call chain to `crash.log` (and to the terminal on Linux), for problem reports.

### Fixes
- **DNG pictures** made by DNGLab were shown on their side, and DNG files from DNGLab and Skydio drones had no camera or capture date (the file date was used for names and folders). The EXIF data is now read wherever it lies in the file.
- **Linux:** Yes, Open and Save are on the left in message boxes and file windows (as on Windows); the File Types window fits the screen; menu check marks show from the start.
- **Linux, dark theme:** no more Access Violation at start-up; panels, progress window and title bar are dark.
- One rule now decides what a download copies, so the Download buttons and the download always agree.
- "Prompt for job code at startup" moved to the General tab.

### For developers
- Build mode **Default** is now called **Debug**; the programs go to `bin/<system>-debug/` and `bin/<system>-release/`.
- Build scripts `windows\build.ps1` and `linux/build.sh both` build both modes with one build number per code version (`build-stamp.txt`).
- The dark style on Windows comes from MetaDarkStyle (bundled in `third_party/metadarkstyle`, LGPL with a linking exception; see `THIRD_PARTY_NOTICES.md`). The program now has a Windows manifest.

### Downloads
- `PhotoDownloader.0.1.5.0.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.5.0.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.5.0.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.docx`, `.odt` and `.md` – User Manual (version 0.1.5)
- `Plugin_Developer_Manual.docx`, `.odt` and `.md` – for writing plug-ins (version 0.1.5)
- `Release_Notes_0.1.5.0.md` – these release notes

### Tested
Windows 11 and Linux Mint 22.3 (Xfce and Cinnamon, GTK 2): every change above, in the program, by the user. The iPhone has not been tried with Import from Device.

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
