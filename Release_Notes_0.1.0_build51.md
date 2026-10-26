## Photo Downloader 0.1.0 – Alpha build 51

> **Alpha software.** Keep your original files until you have checked the copies. Windows is the primary platform.

### What's new
- **Linux build tested** on Linux Mint 22.3 (XFCE, GTK 3): card detection, eject, safe delete (hidden trash folder on cards, system trash on internal disks), View/Empty Trash, settings in `~/.config`, cache in `~/.cache`. See `docs/Linux_Build.md`.
- **Locate card reader** on Linux lists the removable drives found.
- Progress windows stay above the main window; the main window now fits small screens (1366x768); Preferences layout fixes.
- Compiler hint clean-up.

### In development
Video and audio files.

### Known limitations
- Single-instance handling is Windows only; other Linux distributions and Qt are untested.
- Not yet implemented: USB camera download (PTP/MTP), GPS geotagging, watch mode, download history.

### Feedback
https://github.com/RexAlfes/Photo-Downloader/issues

**License:** GNU GPL v3 or later.
