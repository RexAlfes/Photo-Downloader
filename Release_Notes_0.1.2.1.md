## Photo Downloader 0.1.2

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.2.1` (revision 2, build 1). Every release raises the revision and restarts the build number at 1; the build number then counts up with each compile until the next release. Documents name only the version, `0.1.2`.

### Highlights
- **Plug-ins.** Photo Downloader can load plug-in libraries (a `.dll` on Windows, a `.so` on Linux) from a `plugins` folder. A plug-in adds its own tokens to the folder and file name templates and can show a window for its values before each download (with check boxes, lists, a reminder, its logo and version; wrong entries are shown in red). New plug-ins are listed switched off and run only after you confirm their path. **File > Plug-ins…** opens the Plug-ins tab directly. The **Plug-in Developer Manual** and a working example plug-in (`plugins/example`) explain how to write one.
- **Download Selected and Download All.** The Download button is now **Download Selected**; the new **Download All** downloads every file shown, whatever is selected.
- **File extension tokens.** `{E}` (upper case), `{e}` (lower case) and `{ea}` (as it is) work in folder and file names, for example one folder per file type with `{Y}\{E}\`.
- **User profiles.** Profiles keep the plug-in settings. **Save** lists the saved profiles and suggests the one in use; replacing asks first. Double-click loads a profile. After each download, the profile in use remembers the download path and the plug-in values used.
- **Lightroom previews (.lrprev).** Download them as `.jpg` (or both); the photo's file name, date and camera come from the Lightroom catalog when the optional SQLite library is present (built into Windows 10 and 11). Lightroom preview folders (`.lrdata`) are skipped unless switched on in Preferences > General.
- **Faster scans and thumbnails.** EXIF details are kept in a cache (a second scan of the same card is much faster), thumbnails use the camera's own small previews and are cached on disk (at most 500 MB).
- **Linux.** The token list on Preferences > Download Path is no longer cut off; the Preferences window is a little taller.
- **Documents** are now kept as `.md`, `.docx` and `.odt`.

### Downloads
- `PhotoDownloader.0.1.2.1.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.2.1.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.2.1.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.2.docx`, `.odt` and `.md` – User Manual
- `Plugin_Developer_Manual.0.1.2.docx`, `.odt` and `.md` – for writing plug-ins

### Tested
Windows 11: all features above. Linux Mint 22.3 (GTK 2): the Linux test checklist in `docs/Linux_Build.md` passed except the cut-off token list, which is fixed in this release; the fix was checked on Linux after the release.

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
