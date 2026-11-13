# Phones and cameras over USB (MTP / PTP / WPD): plan

Status: **Phase 0 done (2026-11-13); Phase 1 built in 0.1.4.22/0.1.4.23 (Windows) and tested by the user with a Nikon D700 (selecting, downloading, deleting on the camera), an Android phone and a Skydio drone controller. Still to try: iPhone.** Written 2026-11-10 for version 0.1.4. The specification lists "MTP devices, direct USB cameras" as Partial (Windows done, Linux by hand through GVFS).

## 1. Where things stand

- Photo Downloader reads only sources that have a file path: a card reader (`D:\`), a USB drive, a folder, or a Linux mount point.
- A phone, camera or drone controller connected by USB in **MTP** (Media Transfer Protocol) or **PTP** (Picture Transfer Protocol) mode has no drive letter. Windows shows it under This PC through **WPD** (Windows Portable Devices), and Explorer can browse it, but `FindFirst`, `TFileStream` and every decoder in the program cannot open its files.
- Preferences > General already has the choice **Camera (connected by USB)** (`smCamera`) and the option **Disable PTP downloads** (`DisablePTP`). Both are placeholders: with Camera chosen, Refresh says "Direct camera (PTP) download is not supported" (`TMainForm.AutoDetectSource`), and File > Camera Settings is disabled.
- The whole program works on file paths: `TImageItem.FullPath` is used about 90 times, mostly by decoders that open the file themselves (thumbnails in `uItems.EnsureThumbCore`, the viewer in `uViewer`, EXIF in `uExif.ReadExifFromFile`, thermal detection in `uThermal`, the verified copy `CopyFileChecked`, safe delete, plug-in context `Path=`, and external-program plug-ins).

## 2. The devices and what they allow

| Device | Connection | Reading | Deleting | Notes |
|---|---|---|---|---|
| Android phone | MTP; the phone must be unlocked and set to "File transfer" | yes, `DCIM\Camera` and others | usually yes | slow listing of large folders |
| iPhone / iPad | PTP through Apple's driver | yes, `DCIM\100APPLE` ...; HEIC and MOV (Live Photos) | **no** (read-only) | "Trust this computer" on first use |
| Camera (Nikon, Canon, Sony ...) | PTP or MTP, set in the camera menu | yes | depends on the camera | a card reader is usually faster |
| Drone controller (DJI RC, Skydio controller) | MTP | yes, its internal storage | usually yes | drone cards are normally read with a card reader |

## 3. Ways to read a device

### Windows

1. **Shell namespace (recommended).** The same Shell interfaces Explorer uses (`IShellItem`, `IEnumShellItems`, `IShellItem2.GetProperty` for size and dates, `BindToHandler(BHID_Stream)` for an `IStream` of the file, `IShellItemImageFactory` for thumbnails, `IFileOperation` for deleting). Photo Downloader already uses `IShellItemImageFactory` for video thumbnails (`uVideoThumb`), so the COM groundwork exists. Works for MTP and PTP alike, needs no extra driver.
2. **WPD API directly** (`IPortableDeviceManager`, `IPortableDevice`, `IPortableDeviceContent`, `IPortableDeviceResources`). More control (device model and serial, storage capacity, faster property reads in bulk), but Free Pascal has no declarations for it: about 15 COM interfaces and many property keys would have to be translated from `PortableDeviceApi.h` by hand. Keep it as a fallback if the Shell route proves too slow.

### Linux

1. **GVFS paths.** Desktop Linux mounts MTP and PTP devices as folders under `/run/user/<uid>/gvfs/` (`mtp:host=...`, `gphoto2:host=...`). These behave like files (slowly; seeking can be costly), so the existing code mostly works on them already. Not tested yet.
2. **libgphoto2** (as the specification names): full control, but a C library to bind and ship. Only if GVFS is not good enough.

## 4. Proposed design

### Phase 0: trial (short)

A test program in the scratchpad that lists the devices under This PC, walks `DCIM` of a connected phone, prints name, size and date of each file, and copies one file through `IStream` with an MD5. It proves that the Shell route works from Free Pascal on the user's devices before any program change.

**Result (2026-11-13): works.** On a Nikon D700 connected by USB (PTP), the test program did the following:

- It found the camera under This PC. The camera has no file-system attribute, and its parsing name has the form `::{20D04FE0-...}\\?\usb#vid_04b0&pid_0422#...`.
- It found `DCIM` one level down, inside the camera's storage (`SID-{10001,NIKON D700,...}`).
- It listed 10 files (NEF and JPG) with name, size and date in 0.84 s.
- It copied a 14 MB NEF through `BHID_Stream` at about 6 MB/s. The MD5 computed while reading matched the MD5 of the copy, and the copy's size matched the size the Shell reports.

The same code works on an ordinary folder. Free Pascal needs its own short declarations of `IShellItem`, `IShellItem2` (`GetUInt64` for System.Size, `GetFileTime` for System.DateModified) and `IEnumShellItems` (`BHID_EnumItems`), with `constref` for GUID and property-key parameters. `SHGetKnownFolderItem(FOLDERID_ComputerFolder)` gives This PC. Not tried yet: phones, iPhone and drone controllers.

### Phase 1: import through a staging folder (first release)

**Built in 0.1.4.22** as described below, with these details:

- Items inside a device are found again through their Shell item ID list, not their parsing name.
- Staged copies of downloaded files are removed when the device stops being the source (another source, Eject, exit), not right after the download. That way the pictures stay viewable and can still be deleted from the device. Files that were not downloaded stay staged.
- The device list is not remembered between runs; Refresh repeats the last import while the program runs.

The simplest way to get every feature working at once.

1. **File > Import from Device...** (Ctrl+Shift+O) lists the connected devices (name, storage) and preselects `DCIM`; the user can tick other folders. The Camera choice in Preferences > General becomes "Phone or camera (USB)" and makes Refresh and the automatic sequence use the first device found.
2. The chosen folders are copied to a **staging folder** on the computer (default: in the cache folder, `CacheDir\device\<device name>\`), with a progress window, Cancel, the MD5 computed while reading, and the device file's date kept as the file time.
3. The staging folder is then loaded as a normal source. Everything works unchanged: thumbnails, EXIF dates, status, `{Type}` and thermal detection, plug-ins (including a plug-in that copies a scans folder whole), the verified copy, the backup copy.
4. **Already staged files** (same name, size and date) are not copied again, so importing a phone a second time copies only new pictures.
5. **Delete from the device** after the download: the program keeps the link from each staged file to its device object and deletes there (through `IFileOperation`), only for files that were downloaded and exist in the destination, as today. On a device that refuses deleting (iPhone) the menu item explains why it is not available.
6. The staging folder is emptied after a successful download (option: keep it), and its size is shown in Help > Status.

Costs: every file is read once into the staging folder and copied once more to the destination, so it needs free disk space for the import and takes longer than a direct copy. For phones this is acceptable; reading over USB is the slow part either way.

### Phase 2: direct reading (only if Phase 1 is too slow or uses too much space)

Read devices without staging: a file-access layer (`uSource`: open stream, read head, size, time, delete) behind `TImageItem`, thumbnails from the device (`IShellItemImageFactory`), EXIF and thermal checks from the first bytes read into memory, and the copy straight from the device stream to the destination. Every decoder that takes a path would need a stream version or a temporary file, so this is several times the work of Phase 1.

### Phase 3: Linux

First list GVFS device folders in **File > Import from Device...** and use the same staging import (reading through the GVFS path). libgphoto2 only if GVFS proves unreliable.

## 5. What stays the same

- Card readers, USB drives and folders work exactly as now.
- The program stays a single exe without an installer; the Shell interfaces are part of Windows.
- Nothing is ever changed on the device except deleting files the user asked to delete after a verified download.

## 6. Decisions for the owner

Decided by the owner on 2026-11-13.

| # | Question | Proposal | Decision |
|---|---|---|---|
| 1 | Which devices matter most? | Android phones and drone controllers first, then iPhone, then cameras | **Cameras first** (the D700 is at hand), then Android phones and drone controllers, then iPhone |
| 2 | Phase 1 with a staging folder acceptable? | Yes | **Yes** |
| 3 | Where may the staging folder be, and may it be emptied after the download? | Cache folder; emptied after a successful download | **As proposed:** cache folder, emptied after a successful download (an option keeps it) |
| 4 | Delete from the device after the download? | Yes, on devices that allow it, with the same rules as for cards | **As proposed** |
| 5 | Keep "Disable PTP downloads"? | Remove it; the device list makes it unnecessary | **Keep it:** as a switch that keeps devices out of Refresh and the automatic sequence |

## 7. Testing

- Phase 0 and the copy code with a test program on a connected device (needs the device plugged in and unlocked).
- The import window and downloads by the owner on Windows with each device type available; results recorded in the specification.
- Linux: a phone through GVFS on Linux Mint.

## 8. Effort

| Phase | Work |
|---|---|
| 0 Trial | one short session |
| 1 Staging import (Windows) | about two to three sessions, plus testing with devices |
| 2 Direct reading | several sessions; only if needed |
| 3 Linux (GVFS) | one session, plus testing on Linux |

## 9. Documents to update when it is built

README, specification (status table and version history), User Manual (a section on phones and cameras), Settings_File.md (new settings; `DisablePTP` kept, now keeping devices out of Refresh and the automatic sequence), website, release notes, launch materials, continuation prompt.
