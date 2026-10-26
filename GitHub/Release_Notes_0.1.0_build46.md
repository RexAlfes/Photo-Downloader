## Photo Downloader 0.1.0 – Alpha build 46

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Blank job code.** The job code box may now be left empty (Job Code window, Preferences, or a single date). The `{J}` token then expands to nothing and a leftover dash or underscore next to it is removed from folder and file names.
- **Start-up profile prompt.** With "Prompt for user profile at startup" ticked, the list now always offers **Default** (keep the current settings), so it also appears when no profile has been saved. Loading a profile no longer switches the prompt option off.
- **Preferences > Automation.** The safe delete text fits the window, and the trash folder name box is disabled when safe delete is off.
- Build 43-45 changes carry over: safe delete with a configurable `$Trash.bin` folder, View Trash / Empty Trash, progressive JPEG auto-rotate, sortable list view.

### In development
Video and audio files.

### Known limitations
- Card-reader detection, eject and single-instance handling are Windows only.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.
- Safe delete, progressive rotation, blank job codes and the profile prompt need more testing.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
