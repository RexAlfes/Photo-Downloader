## Photo Downloader 0.1.3

> **Pre-release software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### Version numbers
The version is **major.minor.revision.build**. This release is `0.1.3.1` (revision 3, build 1). Every release raises the revision and restarts the build number at 1; the build number then counts up with each compile until the next release. Documents name only the version, `0.1.3`.

### Highlights
- **Plug-in steps after each file.** Plug-ins can now work on every downloaded file. A step that fails keeps the file from being deleted from the card, switches the plug-in off and is reported when the download ends.
- **DNG Converter plug-ins.** Two ready-made program plug-ins in `plugins/dng-converter` make a `.dng` next to each downloaded raw file: one for Adobe DNG Converter (Windows) and one for dnglab (Windows and Linux). The raw file is kept, and a DNG that already exists is skipped. A program is found at its usual place, on the PATH or next to its `.plugin.ini`, or you choose it with **Setup...**.
- **Program plug-ins in general.** A small text file (`.plugin.ini`) can run any command-line program on each downloaded file. The Plug-in Developer Manual explains the format.
- **JPEG resolution.** Adjusts the DPI of downloaded JPEGs. The resolution can be specified in DPI or dots/cm. Adjusting the resolution does not affect the image data; some applications (for example Photoshop and Photoshop Elements) use it to determine the print size.
- **JPEG auto profile.** Embeds an ICC color profile into downloaded JPEGs, chosen per camera model, without recompressing the picture.
- **Directory Maker.** Creates empty folders (for example `Edit, Web`) next to the download folder.
- **Plug-ins tab.** **Install...** copies a plug-in into your plug-ins folder, **Remove** deletes one you installed. Switched-on plug-ins are shown in black, switched-off ones in gray, and the version follows the name.
- **Small screens.** On a screen such as 1366 x 768 the Preferences window is made shorter and its tabs scroll, so OK and Cancel stay reachable.
- **Linux.** The JPEG auto profile setup no longer stops responding after a profile is chosen.

### Downloads
- `PhotoDownloader.0.1.3.1.Win64.exe` – Windows 64-bit (single file)
- `PhotoDownloader.0.1.3.1.Win64.zip` – Windows 64-bit (zipped copy of the exe)
- `PhotoDownloader.0.1.3.1.linux64.tar.gz` – Linux 64-bit (unpack, then run `PhotoDownloader`)
- `User_Manual.0.1.3.docx`, `.odt` and `.md` – User Manual
- `Plugin_Developer_Manual.0.1.3.docx`, `.odt` and `.md` – for writing plug-ins

### Tested
Windows 11: all features above, including Adobe DNG Converter 18.7 and dnglab 0.8.0 on Nikon and Canon raw files. Linux Mint 22.3 (GTK 2): an 18-step plug-in test list passed, including dnglab, Install and Remove, JPEG resolution, JPEG auto profile, Directory Maker and the Release build; the two faults it found are fixed in this release and were checked again on Linux.

### Windows security warning
The `.exe` is not code-signed, so Windows may show **Windows protected your PC** with **Publisher: Unknown publisher**. Click **More info**, then **Run anyway**. See section 1 of the User Manual.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues
