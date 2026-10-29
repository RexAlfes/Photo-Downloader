# Photo Downloader – User Manual

**Version:** 0.1.1 · **License:** GNU GPL v3 or later · **Platforms:** Windows 64-bit (primary), Linux 64-bit (GTK 2, tested on Linux Mint 22.3)

Photo Downloader copies photos from a memory card, card reader or folder to your computer. It renames them from templates, files them into folders by date and job code, and checks every copy. This manual explains each part of the program in the order you will meet it.

> **Alpha software.** Keep the original files on the card until you have checked the copies on your computer.

**Contents**

1. [Installing and starting](#1-installing-and-starting)
2. [The main window](#2-the-main-window)
3. [Quick start: your first download](#3-quick-start-your-first-download)
4. [Job codes](#4-job-codes)
5. [Loading pictures](#5-loading-pictures)
6. [What the colors and statuses mean](#6-what-the-colors-and-statuses-mean)
7. [Selecting pictures](#7-selecting-pictures)
8. [Naming files and folders (tokens)](#8-naming-files-and-folders-tokens)
9. [Downloading](#9-downloading)
10. [Deleting from the card](#10-deleting-from-the-card)
11. [The image viewer](#11-the-image-viewer)
12. [Preferences](#12-preferences)
13. [User profiles and exporting settings](#13-user-profiles-and-exporting-settings)
14. [Choosing file types](#14-choosing-file-types)
15. [Supported picture formats](#15-supported-picture-formats)
16. [Logging and troubleshooting](#16-logging-and-troubleshooting)
17. [Keyboard shortcuts](#17-keyboard-shortcuts)
18. [Where your settings are stored](#18-where-your-settings-are-stored)
19. [Questions and answers](#19-questions-and-answers)
20. [Getting help](#20-getting-help)

---

## 1. Installing and starting

**Windows.** Download `PhotoDownloader.<version>.Win64.exe` from the [Releases page](https://github.com/RexAlfes/Photo-Downloader/releases) and run it. There is no installer; the program is a single file. You can keep it in any folder.

**Windows warning: "Windows protected your PC" / "Unknown publisher".** Photo Downloader is a free, open source program and its file is not code-signed (a signing certificate costs money every year), so Windows may stop it the first time you run it. You will see a blue window titled **Windows protected your PC** (Microsoft Defender SmartScreen) saying that it prevented an unrecognized app from starting, with **Publisher: Unknown publisher**. This does not mean the file is damaged. Windows shows it for any new program that is not signed or not yet widely downloaded. To run the program:

1. Make sure you downloaded the file from the official [Releases page](https://github.com/RexAlfes/Photo-Downloader/releases) and not from another site.
2. In the blue window click **More info**. A **Run anyway** button appears. Click it. Windows remembers your choice for that file, so you will not be asked again.
3. If there is no **Run anyway** button, close the window, right-click the downloaded file (the `.exe`, or the `.zip` before you unpack it), choose **Properties**, tick **Unblock** at the bottom of the General tab, click **OK** and start the program again.
4. Your browser may also say the file "isn't commonly downloaded" or "could harm your device". In Edge or Chrome open the downloads list, choose the **...** menu next to the file and pick **Keep** (then **Keep anyway**).
5. On Windows 11 with **Smart App Control** turned on, unsigned programs are blocked without a **Run anyway** choice. You can switch Smart App Control off in Windows Security > App & browser control > Smart App Control settings, but on many Windows versions it cannot be turned on again afterwards, so decide carefully. Or build the program yourself from the source (see the README).
6. If your antivirus program quarantines the file, restore it and add the folder to its exceptions. Photo Downloader does not need administrator rights; if anything asks for them, answer **No**.

**Linux.** Download `PhotoDownloader.<version>.linux64.tar.gz`, unpack it and run `PhotoDownloader`. The program needs `udisks2` (to eject cards), `gio` (for the trash) and `xdg-open` (to open folders). To build it yourself, see `docs/Linux_Build.md` in the repository.

**Lightroom catalogs (optional SQLite library).** Photo Downloader needs no other files, with one exception: to read a Lightroom catalog for `.lrprev` preview files (see [section 15](#15-supported-picture-formats)) it uses the SQLite library of the system. On Windows 10 and 11 this is `winsqlite3.dll`, which is part of Windows, so there is nothing to do. On older Windows download the 64-bit `sqlite3.dll` from [sqlite.org](https://www.sqlite.org/download.html) and put it in the same folder as `PhotoDownloader.exe` (a `sqlite3.dll` there is always used first). On Linux it is `libsqlite3` (package `libsqlite3-0`), which is almost always installed. Without it, everything else works. **Help > Status** shows which library is in use.

**Starting.** A splash screen appears for at least five seconds (click it to close it sooner). Then the **Job Code** window appears (see [section 4](#4-job-codes)). By default nothing is scanned at start-up; you choose a source folder or insert a card.

**Updating.** Download the newer file and replace the old one. Your settings are kept separately (see [section 18](#18-where-your-settings-are-stored)). Help > Check for updates opens the Releases page.

## 2. The main window

| Area | What it does |
|---|---|
| **Menu bar** | File, Edit, View and Help. |
| **Date – Job code list** (left) | One line per capture date found on the card, with its job code. Also called the *Image Date Selector*. |
| **Picture area** (right) | The pictures as thumbnail cards (Small, Medium, Large or Fit to Window) or as a list. |
| **Status line** (bottom) | How many files will be downloaded, how many have problems, and the result of the last copy. |
| **Buttons** | **Close**, **Delete**, **Download Selected**, **Download All**, and an optional **Custom** button. |

Each picture card shows its number, file name and size, the date and time it was taken, its status, the camera model and the new name it will get.

**Views.** View > List View shows one line per picture with column headings (File, Captured, Status, Camera, Destination). Click a heading to sort; click it again to reverse the order. The thumbnail views show a picture with its details beside it: the number and file name (without the extension) on the first line, then the capture date, the **file type** and the **size** (for example `10/28/26 11:02:00   NEF   24.1 MB`), the status, the camera and the destination. A name that is too long is shortened with "...". The order you choose also applies to the viewer.

**Thumbnail size.** View > Thumbnail View offers **Small** (64 pixels, Ctrl+T), **Medium** (160 pixels, Ctrl+M), **Large** (320 pixels, Ctrl+X) and **Fit to Window**. Fit to Window is the default for new settings: it uses as few columns as keep the thumbnails at 160 pixels or less and shares the window width evenly, so nothing is left over at the right, and it follows the window when you resize it. You can also hold **Ctrl** and turn the mouse wheel over the pictures to make the thumbnails larger or smaller in small steps (64 to 320 pixels); that replaces Fit to Window with the size you stop at. The same choices are in the right-click menu. Larger sizes use more memory, so fewer thumbnails are kept at once.

**Date list.** Selecting pictures highlights their dates in the list. Clicking dates selects all pictures of those dates. If a highlighted date is out of sight, the list scrolls to it. Hide or show the list with View > Image Date Selector (Ctrl+Tab).

## 3. Quick start: your first download

1. Start the program. In the **Job Code** window, type a short name for this shoot, for example `Smith Wedding`, and enter the folder to load. Click **OK**.
2. If you did not enter a folder, choose File > Open Source Folder (Ctrl+O) and select the card or folder. A progress window shows the files being read; you can cancel it.
3. Check the thumbnails. The status line says how many files are ready.
4. Choose the pictures you want (Ctrl+A selects all) or leave everything selected.
5. Click **Download All** (or select files and click **Download Selected**). Each file is copied, then read back and compared with the original. The status line reports the result.
6. Open your Pictures folder. The default location is `Pictures\Photo Downloader\<year>\<year>-<month>-<day>-<job code>\`.

That is all you need to start. The rest of this manual explains how to change the folders, the names and the checks.

## 4. Job codes

A **job code** is a name for the shoot. It becomes part of the destination folder, and can be part of file names.

- The **Job Code** window opens at start-up (you can switch this off in Preferences > Download Path). It remembers earlier codes. A live **Example image name** shows where the next file will go.
- Edit > Job Code (Ctrl+J) changes the code later.
- **Different codes for different days.** Right-click a date in the list to give that date, or all highlighted dates, its own code. With "Save date based job codes for next time" (Preferences > General) the codes are remembered.
- The code may be **blank**. `{J}` then expands to nothing, and a dash or underscore beside it is removed so you do not get names like `2026-10-27-`.

## 5. Loading pictures

- **File > Open Source Folder (Ctrl+O)** scans the folder and all folders inside it.
- **File > Refresh (F5)** scans again. With no source chosen, it looks for a removable drive with a `DCIM` folder (Windows).
- **Preferences > General** can load the last used folder at start-up. Otherwise nothing is scanned until you choose.
- **Scan whole disk for known image types** is on by default. Turn it off to scan only the `DCIM` folder of a card.
- A progress window with a **Cancel** button appears while a large folder loads. Thumbnails are drawn a few at a time while you scroll; they are kept in a disk cache (at most 500 MB, the oldest are removed first) so they appear much faster next time. The camera, date and orientation read from each file are kept as well, so scanning the same folder again is much faster.
- **File > Eject (F6)** safely removes the card or drive after use.

If a picture cannot be shown, its thumbnail is a gray box with the file extension and a **red X**. The file can still be copied. The reason is written to the log if logging is on (see [section 16](#16-logging-and-troubleshooting)).

## 6. What the colors and statuses mean

Every picture is compared with your destination folder and with the other pictures in the list.

| Status | Card color | Meaning |
|---|---|---|
| **New file** | light gray / white | Not downloaded yet. |
| **Already downloaded** | darker gray | A file with the new name and the same size already exists in the destination. (The size check can be turned off: Preferences > File Handling, "Ignore file size check".) |
| **Name clash** | **red** | A *different* file with the same new name already exists, or two pictures in the list would get the same new name. The reason is shown, for example "same new name as #3". |
| **Duplicate file** | **amber** | The same picture was found twice (same size, capture time and camera), for example copies in two folders. Duplicates are not downloaded by default (**Ignore duplicate files on download**). They can instead be downloaded when the name is free, or numbered with **Download duplicates as (1), (2) …**. |

Selected cards have a darker shade of their color. View > Show 'Downloaded' files and Show 'Duplicate' files hide those groups.

### Duplicate file or name clash: what is the difference?

They answer different questions. A **duplicate** is about the *content*: is this the same picture as another file in the list? A **name clash** is about the *destination file name*: is the new name already taken?

- **Duplicate file** is decided from the source list alone. The program builds a key from the file size, the capture time and the camera. When two files have the same key, the first stays *New file* and the later ones are marked *Duplicate file*. This catches the same picture copied into two folders on the card, or a renamed copy. File names and the destination folder are not looked at.
- **Name clash** is decided from the new destination path. It means that path is already taken, either by a *different* file that is already in the destination (the size does not match), or by another new picture in the list that would get exactly the same new name (for example when the name pattern does not tell them apart).
- **Already downloaded** is the third case: the destination file exists and has the same size, so it is taken to be this very picture from an earlier download.

A picture has exactly one status. A duplicate is decided first and is never also shown as a name clash.

### How the status of each picture is decided

The program goes through the list in order (oldest capture time first) and applies these steps to every picture:

1. **Work out the new name.** The folder and file name patterns, the job code, the date and the sequence number give the planned destination path of the picture.
2. **Look for a duplicate.** If an earlier picture in the list has the same size, capture time and camera, this one is **Duplicate file**. Nothing else is checked for it (not even the destination), and it keeps that status. Otherwise it starts as **New file**.
3. **Look at the destination** (for pictures that are not duplicates):
   - A file with the planned name exists and has the **same size** (or "Ignore file size check" is on): **Already downloaded**.
   - A file with the planned name exists but has a **different size**: **Name clash** ("a different file with this name already exists").
   - No such file exists, but **two or more new pictures** in the list have the same planned name: **Name clash** for all of them ("same new name as #3").
   - Otherwise it stays **New file**.
4. **Rename name clashes** (only when that option is on): a name clash is turned into **New file (renamed)**. The destination shown on the card already has the new name (`IMG_0001 (1).jpg`). Of several pictures that share a name, the first keeps it and the others get `(1)`, `(2)` and so on. A picture that meets an existing different file is numbered right away.

The statuses are worked out again whenever the destination, the file name pattern, the job code, a profile or one of the file handling options changes, and after a download.

| Status | Shown as | Downloaded when you click Download? | Delete from source allowed? |
|---|---|---|---|
| New file | light gray / white | Yes | No (not downloaded yet) |
| New file (renamed) | light gray / white | Yes, under the new numbered name | No |
| Already downloaded | darker gray | No, skipped | Yes, if it exists in the destination (and the backup, if on) |
| Name clash | red | Only if you answer **Yes** to the question (numbered with `-1`, `-2`); otherwise skipped | No |
| Duplicate file | amber | Only with **Download duplicates as (1), (2) …** or when both duplicate options are off and the name is free; skipped by default | No |

**Name clashes.** When you click Download with name clashes in the list, the program asks:

- **Yes** – download them anyway, adding `-1`, `-2` … to the name.
- **No** – skip the problem files.
- **Cancel** – download nothing.

If you turn on **Rename name clashes as (1), (2) …** (Preferences > File Handling), the program never asks. Clashing files are downloaded as `IMG_0001 (1).jpg`, `IMG_0001 (2).jpg` and so on, like Windows does. With this option on, such files are not shown red: they appear as **New file (renamed)** and the destination shown on the card already has the new name, for example `IMG_0001 (1).jpg`. The reason is shown in Properties and in the status bar.

**Duplicates.** Preferences > File Handling has two exclusive options: **Ignore duplicate files on download** (the default; duplicates are skipped) and **Download duplicates as (1), (2) …**. With both off, duplicates are downloaded only when their new name is free. With the second option, duplicate files are downloaded too, and any that would collide with an existing file get the same `(1)`, `(2)` numbering. Because a duplicate is still a duplicate afterwards, downloading the same card again with this option on makes another numbered copy each time.

**Good to know about duplicates.**

- **Names do not matter for the duplicate check.** Two files are duplicates when their size, capture time and camera match, even if their file names differ (for example `IMG_0001.jpg` and `IMG_0001 copy.jpg`).
- **A number is added only when the name is taken.** With **Download duplicates as (1), (2) …**, a duplicate becomes `name (1).jpg` only if its new destination name is already used, by a file in the destination folder or by another picture in the same download. If its new name is different, it is downloaded under that name with no number. Several duplicates that share a name are numbered `(1)`, `(2)`, `(3)` in turn. The card shows the planned name, number included.
- **The amber color does not depend on the options.** It shows the status. The options only decide what a download does with those files (skip them, download them numbered, or download them only when the name is free).
- **A downloaded duplicate stays amber.** After a download the original shows as *Already downloaded*, but a duplicate is never compared with the destination, so it keeps the status *Duplicate file*. If you download the same card again with **Download duplicates as (1), (2) …** on, another numbered copy is made each time. Use **Ignore duplicate files on download** to avoid that.
- With logging on, the log records for every duplicate whether it was renamed or skipped and why.

## 7. Selecting pictures

Click a card to select it; Ctrl-click and Shift-click extend the selection. The Edit menu has shortcuts:

| Command | Shortcut | Selects |
|---|---|---|
| Select All | Ctrl+A | every picture shown |
| Select Downloaded | Ctrl+D | pictures already downloaded |
| Select Read Only | Ctrl+R | read-only pictures |
| Select JPEGs | Ctrl+Shift+J | JPEG pictures |
| Select None | Ctrl+N | clears the selection |
| Invert Selection | Ctrl+I | swaps selected and not selected |

Only **New file** pictures and name clashes are downloaded; downloaded files are skipped, and so are duplicates unless you turned on **Download duplicates as (1), (2) …**.

**Right-click a picture** for: View image, Show in source folder, Show in destination folder (only for files already downloaded), Download selected file(s), Delete selected file(s) from source, Save .lrprev preview(s) as JPG... (only when Lightroom previews are selected), Properties (everything known about the file, with a Copy button), Refresh (rescans the source, the same as File > Refresh or F5), and then the same choices as the View menu (except the Image Date Selector): Show 'Downloaded' files, Show 'Duplicate' files, File Types…, List View and the Thumbnail Views (small, medium, large and fit to window).

## 8. Naming files and folders (tokens)

The destination folder and the file name are built from a template. Words in braces are **tokens** that are replaced by details of each picture. Every token works in both templates, so the tokens that name a file can also build the folder structure (for example one folder per file type with `{E}`). Plug-in libraries can add more tokens (see Preferences > Plug-ins). Set the templates in **Preferences > Download Path**; the **Example image** line shows the result as you type, and **Show tokens…** (or F1) lists all tokens.

Default folder template: `Pictures\Photo Downloader\{Y}\{Y}-{m}-{D}-{J}\`
Default file name template: `{o}` (the original name)

| Token | Meaning |
|---|---|
| `{d}` | date, `yyyymmdd` |
| `{y}` / `{Y}` | 2-digit / 4-digit year |
| `{m}` | month (2 digits) |
| `{b}` / `{B}` | month, abbreviated / full name |
| `{D}` | day of month |
| `{a}` / `{A}` | weekday, abbreviated / full |
| `{W}` | week number |
| `{t}` | time, `hhmmss` |
| `{H}` / `{I}` | hour 00–23 / 01–12 |
| `{M}` / `{S}` | minutes / seconds |
| `{q}` | name of the folder the picture came from |
| `{r}` | image number from the original name |
| `{o}` | original file name without extension |
| `{f}` | letters before the number in the original name |
| `{O}` | owner / artist |
| `{i}` | ISO |
| `{c}` | camera serial number |
| `{T}` or `{T1}` | camera model |
| `{T8}`, `{T9}` | custom tokens set per camera (Mapping tab) |
| `{J}` | job code |
| `{E}` / `{e}` / `{ea}` | file extension in upper case / lower case / as it is, without the dot |
| `{seq#}` | download sequence number |
| `{n1}` … `{n9}` | sequence number for this session, padded to 1–9 digits |

**Examples** (for a Nikon D700 picture `DSC_1234.NEF` taken 27 October 2026 at 2:05 pm, job code `Smith`):

- `{Y}-{m}-{D}-{J}` → folder `2026-10-27-Smith`
- `{d}_{t}_{o}` → `20261027_140500_DSC_1234.NEF`
- `{J}_{n4}` → `Smith_0001.NEF`, `Smith_0002.NEF` …
- `{Y}\{E}\` → folder `2026\NEF`, so RAW and JPEG files land in separate folders

**Extension tokens.** `{E}`, `{e}` and `{ea}` give the extension of the saved file: a `.jpe` file renamed to `.jpg`, or a Lightroom preview saved as a .jpg, gives `JPG` / `jpg`. The option "Convert filename to lower case" also lowers `{E}` when it is used in the file name.

**Sequence numbers.** `{seq#}` continues from download to download. Set the starting number in Preferences > Download Path; **Reset** sets it back.

## 9. Downloading

- **Download Selected** (or right-click > Download selected file(s)) downloads only the selected files. It is available when at least one selected file still needs downloading.
- **Download All** downloads every file shown in the window, whatever is selected (files hidden by View > File Types or the Show options are not included).
- Automation (Preferences > Automation) downloads the selected files, or all files when nothing is selected.

For each file the program:

1. creates the destination folder if needed,
2. copies the file,
3. **verifies** it by reading the copy back and comparing a checksum (one automatic retry if it differs),
4. optionally makes a **backup copy**, and
5. applies the options you chose: capture time as the file date, read-only, lower-case names, lossless auto-rotation, author/copyright, IPTC/XMP data, EXIF text file.

A progress window shows the file being copied and has a **Cancel** button; a cancelled download can simply be started again, and files already copied are recognized as downloaded.

**Verify every copy** is on by default (Preferences > Download Path). **Also save a second copy to a backup folder** makes another copy, using the same patterns, from the verified download before any rotation or metadata is applied. A file whose backup failed is never offered for deletion.

**Auto-rotate.** Downloaded JPEGs are turned upright according to their EXIF orientation without recompressing them (lossless). Up to 15 rows or columns that do not fill a block may be trimmed at one edge, as the standard tool `jpegtran -trim` does. The thumbnails and viewer always show pictures upright regardless of this option.

**Other options** (Preferences > File Handling): Save files as read-only; Preserve read-only status; Use image capture time for file timestamp; Convert file name to lower case; Lower case file extensions; Rename `.jpe` to `.jpg`; Save Lightroom previews (`.lrprev`) as `.jpg`, optionally keeping both; Generate text file containing EXIF shooting data; Add IPTC/XMP data (a `.xmp` sidecar is written; see Edit > IPTC/XMP Data); Add author and copyright to EXIF of downloaded JPEGs (only where those fields are empty).

**Custom button.** Preferences > Custom button adds a button with your own caption that runs a program. In the command line `%f` is the file and `%d` its directory.

## 10. Deleting from the card

**Delete** (the button, or right-click > Delete selected file(s) from source) removes selected pictures from the *source* – but only those that are marked **Already downloaded** and really exist in the destination (and, if a backup is on, in the backup). Anything else is left alone.

**Safe delete** is on by default (Preferences > Automation):

- On your computer's own disks, deleted files go to the **Recycle Bin** (Linux: the trash).
- On cards, USB drives and network drives, they are moved to a hidden folder named `$trash.bin` at the root of the drive. You can change the folder name.
- File > **View Trash** opens it; File > **Empty Trash…** empties it after asking.
- If neither is possible, the file is kept and you are told.

## 11. The image viewer

Double-click a picture, or right-click > View image. The viewer shows the picture at about the size of the screen, upright.

| Key | Action |
|---|---|
| Esc | close the viewer |
| ← ↑ Page Up | previous picture |
| → ↓ Page Down Space | next picture |
| Home / End | first / last picture |
| Mouse wheel | previous / next picture |

If the file cannot be shown, the viewer says so and the log tells you why.

## 12. Preferences

Open File > Preferences (Ctrl+P). The dialog has seven tabs: Download Path, General, File Handling, Automation, Mapping, Custom Button and Plug-ins. **File > Plug-ins...** opens it directly on the Plug-ins tab.

### Download Path
Destination folder template, file name template, default job code, "Prompt for job code every time Downloader is run", the starting sequence number with Reset, "Show tokens…", the example image, **Verify every copy**, and the **backup folder**.

### General
- **Image source:** auto-detect, camera (USB) or card reader/external storage. On Windows you can enter the drive letters of card readers or use **Locate card reader**. On Linux, removable drives are found automatically.
- **Disable PTP downloads.**
- Load the last used source folder at start-up.
- Prompt for user profile at start-up.
- Save date-based job codes.
- Automatically eject card reader media when disconnecting.
- Scan whole disk.
- **Scan Lightroom preview folders (.lrdata) for .lrprev files** (off by default). Lightroom keeps its previews in tens of thousands of small folders; with this option off they are skipped, which makes scanning a picture folder that holds a Lightroom catalog much faster. Changing it scans the source again.
- IPTC/XMP options, including legacy IPTC IIM data and Nikon NEF raw files.
- Author and copyright for downloaded JPEGs.
- Run only one copy at a time (Windows; applies at the next start).

### File Handling
How downloaded files are named, copied and treated.
- Save files as read-only; preserve read-only status.
- **Rename name clashes as (1), (2) …**; **Ignore duplicate files on download**; **Download duplicates as (1), (2) …** (the last two exclude each other).
- Ignore file size check (for images modified after downloading).
- Auto-rotate JPEGs after downloading (lossless).
- Rename `.jpe` files to `.jpg`.
- **Save Lightroom previews (.lrprev) as .jpg when downloading**: the largest preview picture in the file is saved as a `.jpg` (unchanged, not re-encoded) instead of the `.lrprev` file. **Save both** (only with the option above) keeps the `.lrprev` file and writes the `.jpg` next to it. A `.lrprev` saved as `.jpg` counts as downloaded when the `.jpg` exists (its size never matches the original).
- Convert file names to lower case; lower case file extensions.
- Use image capture time for the file timestamp.
- Generate a text file containing EXIF shooting data.
- Windows-safe file names (Linux only): replaces characters such as `: ? * " < > |`.

### Automation
For hands-free use: start-up automation, an Automation menu item and shortcut (F4, **Start Auto Sequence**), an optional prompt before it starts, and what it does – download, delete from the card, eject, launch an application, exit. Safe delete and the trash folder name are set here too.

### Mapping
Gives each camera its own values for the `{T8}` and `{T9}` tokens, for example a short code per camera body. Add cameras with **Add camera…**; edit or delete entries with the buttons. Cameras can be identified by name or by serial number/owner string/user comment, and the program can ask when it meets a new camera.

### Custom Button
Enable the button, set its caption and the command line.

### Plug-ins
Lists the built-in plug-ins and any plug-in libraries found. **Directory Maker** works. The other built-in ones (JPEG auto profile, DNG Converter, JPEG resolution) are listed only and do nothing yet. The old Backup plug-in has been removed; backups are set with the backup folder on the Download Path tab.

**Plug-in libraries.** A plug-in library is a separate file that adds its own tokens to the folder and file name templates, for example to build folder names by an organization's naming standard. Put the file into the `plugins` folder:

- Windows: `%LOCALAPPDATA%\Photo Downloader\plugins\name.dll` (or a `plugins` folder next to `PhotoDownloader.exe`)
- Linux: `~/.config/Photo Downloader/plugins/libname.so` (or a `plugins` folder next to the program)

The next time the program starts, the library appears in the list as **name (library) - disabled**. Nothing of it runs yet. Select it and tick **Enable plug-in**: a message shows the full path of the file. Click **OK** only when you trust where the file came from, because a library runs with your rights. If a library cannot be loaded (for example a 32-bit or a Linux file on Windows), the program says why and switches it off. To remove a plug-in, delete its file from the `plugins` folder: at the next start it leaves the list. Its values are kept, so they are back if you install it again.

Once it is switched on, the list shows the library's own name, the information below the list names its tokens, and its logo (if it has one) is shown. **Setup...** opens the library's window for its values. The same window opens each time you start a download (**Download Selected** or **Download All**), filled with the last values; check them and click **OK**. **Cancel** stops the download before anything is copied. **OK** is only available when the values are valid. If the library offers a **Destination folder...** button, use it to choose the folder to download to. The download folder on the Download Path tab is set to that folder plus the library's folder layout (for example a project folder named from the values, then a folder per day and job code); the window shows the result as **Download to:**. A library can also offer check boxes that change the last folder of the download path, for example one folder per type of file; the **Download to:** line follows the box. The library's version is shown in the window's title bar. Use the library's tokens in the templates on the Download Path tab like any other token; the **Example image** line shows the result. A token whose value is missing stays in the name as written (for example `{ABC}`), so you can see it.

The interface for writing libraries is described in `docs/Plugin_Developer_Manual.md`.

## 13. User profiles and exporting settings

A **profile** is a saved set of preferences – useful if you use several cameras, clients or computers.

- File > User Profiles > **Save** stores the current settings under a name; **Load** applies one; **Delete** removes one. In the Load window (and the start-up profile list), double-clicking a profile loads it.
- **Save** lists the saved profiles and fills in the name of the profile in use (the one loaded or saved last). Click **Save** to update that profile, click another profile in the list (double-click saves at once) to save over it, or type a new name. Saving over a profile asks for confirmation first.
- **The download path and plug-in values follow the profile.** After each download, the download path and the plug-in values that were used are written into the profile in use, so loading that profile later downloads to the same place with the same plug-in values, even when they were changed after the profile was saved (for example in a plug-in's window). Only these are updated; other changes still need **Save**. Choosing **Default** at start-up means no profile is in use.
- A profile holds all preferences, including the **plug-ins**: which are switched on, their order, and the values entered in a plug-in's window (with the download path it set). Loading a profile switches the plug-ins on or off as saved; a plug-in library that is missing on this computer is switched off with a message.
- With "Prompt for user profile at start-up", a list appears each time the program starts. The entry **Default** keeps your current settings.
- File > **Export Settings** saves a copy of your settings to a file you choose.

## 14. Choosing file types

View > **File Types…** (or right-click > File Types…) selects which kinds of file are shown and copied: JPEG, PNG, BMP, GIF, TIFF, WebP, HEIC/AVIF, RAW (NEF and NRW are separate, with the other RAW formats), video (MP4, MOV and LRV are separate options, so each can be shown or hidden on its own, for example to download them to different destinations), audio and THM. Adobe Lightroom previews (`.lrprev`) can be listed too; select them, right-click and choose **Save .lrprev preview(s) as JPG...** to write the largest preview of each (at most 256 pixels) as a `.jpg` in a folder you choose (the picture is saved as stored in the file; existing files are never overwritten). Audio (MP3), THM and Lightroom preview files are switched **off** by default; video is on. The **Default** button sets every choice back to the program's own default (nothing changes until you click OK). (If you already have a settings file, saved choices are kept.)

## 15. Supported picture formats

| Format | Thumbnail and viewer |
|---|---|
| JPEG, PNG, BMP, GIF (first frame) | Yes. Files are recognized by their content, so a JPEG named `.png` still opens. Damaged PNG checksums are repaired in memory. |
| TIFF, DNG | Yes – embedded preview, or the picture data itself (LZW, PackBits, Deflate, fax, palette, 1–16 bit, CMYK). Not supported: JPEG-compressed TIFF, planar, floating-point and BigTIFF files. |
| RAW (NEF, NRW, CR2, CR3, CRW, ARW, ORF, RAF, RW2, PEF and others) | The largest embedded JPEG preview. |
| WebP | Yes – lossy, lossless and transparent (shown on white); first frame of animations. ICC profiles are ignored. |
| HEIC, HEIF, AVIF | Yes, with the bundled decoder; no extra software needed. Files that are corrupt show the gray box with a red X. |
| Video (MP4, MOV, LRV, one option each) | Listed and copied. The capture date and length come from the movie header. The thumbnail is a real frame from the Windows Shell, or on Linux from ffmpegthumbnailer or ffmpeg when installed (`sudo apt install ffmpegthumbnailer`). Otherwise the cover picture inside the file or a `.thm` file with the same name is used, and if there is none, a dark tile with a play symbol. Double-click plays the video in your default player. |
| Audio (MP3) | Listed and copied. It shows a default music-note tile, and double-click plays it in your default player. |
| Adobe Lightroom preview (.lrprev) | Listed and copied. The thumbnail and viewer show the largest preview stored in the file, at most 256 pixels, already upright. The file holds no original file name and no EXIF data, so without the catalog the capture date is the file's own date. When the Lightroom Classic catalog is found (the previews folder `<catalog> Previews.lrdata` lies next to `<catalog>.lrcat`), the photo's file name, capture date, camera, serial number and ISO are read from it: the file is named after its photo (tokens `{o}`, `{r}`, `{f}`), filed by its real date, and Properties shows the **Lightroom photo**. This needs the SQLite library (see [section 1](#1-installing-and-starting)). Preferences > File Handling can save it as a `.jpg` when downloading (or both); Preferences > General must have **Scan Lightroom preview folders** on. |

## 16. Logging and troubleshooting

Help > **Logging (for troubleshooting)** writes problems to a file named `thumbnail.log` in the settings folder: pictures that could not be shown (with the reason and the first bytes of the file), failed copies, and failed rotations. The log stops growing at about 200 KB.

- Help > **Save log file…** saves a copy with the program version and the time at the top. Attach it when you report a problem.
- File > **Status** shows the number of files by status, the job code, the next sequence number, an example name and the **settings file location** – click the path to open its folder.

**Common questions**

| Problem | What to check |
|---|---|
| A thumbnail is a gray box with a red X | The file could not be decoded. It may be damaged, not really a picture, or an unsupported variant. Look it up in the log. |
| Windows says "Windows protected your PC" or "Unknown publisher" | The program file is not code-signed. Click **More info**, then **Run anyway**; see [section 1](#1-installing-and-starting) for the other cases (Unblock, browser warning, Smart App Control). |
| Nothing happens at start-up | By design nothing is scanned until you choose a source (Ctrl+O), unless "Load the last used source folder" is on. |
| Card is not found | Press F5; on Windows check the drive letters in Preferences > General or use **Locate card reader**. |
| Everything shows "Already downloaded" | The destination already holds files with the same names and sizes. Change the job code or the templates, or turn off the size check. |
| Cards are red | Name clashes. Use the Yes/No question, or turn on **Rename name clashes as (1), (2) …** (then they are no longer red). |
| Delete does nothing for some files | Only files that are marked downloaded and verified in the destination can be deleted. |

## 17. Keyboard shortcuts

| Shortcut | Command |
|---|---|
| Ctrl+O | Open Source Folder |
| Ctrl+P | Preferences |
| F4 | Start Auto Sequence |
| F5 | Refresh |
| F6 | Eject |
| Ctrl+A / D / R / N / I | Select All / Downloaded / Read Only / None / Invert |
| Ctrl+Shift+J | Select JPEGs |
| Ctrl+C | IPTC/XMP Data |
| Ctrl+J | Job Code |
| Ctrl+L | List View |
| Ctrl+T | Small thumbnails (64 px) |
| Ctrl+M | Medium thumbnails (160 px) |
| Ctrl+X | Large thumbnails (320 px) |
| Ctrl + mouse wheel | Change the thumbnail size |
| Ctrl+Tab | Show or hide the Image Date Selector |
| F1 (in Preferences) | Token list |
| Arrow keys, Home, End, Page Up/Down, Space | Move through the pictures; double-click opens the viewer |

## 18. Where your settings are stored

Settings are in the per-user configuration folder, in a file named `PhotoDownloader.ini`, with a `profiles` sub-folder for user profiles. The log is `thumbnail.log` in the same folder. The easiest way to find it is File > Status and clicking the **Settings file** path.

Typical locations: Windows `C:\Users\<you>\AppData\Local\PhotoDownloader\`; Linux `~/.config/PhotoDownloader/`. Every setting is described in `docs/Settings_File.md` in the project source. Delete the `.ini` file to return to the defaults.

## 19. Questions and answers

**Does the program change my original files?** No. It copies, verifies, and only then (if you ask) moves originals to the trash. Rotation, metadata and sidecar files apply to the *copies*.

**Can I download the same card twice?** Yes. Files that are already in the destination show as *Already downloaded* and are skipped.

**Why does a duplicate not download?** Two files with the same size, capture time and camera are treated as the same picture. Turn on View > Show 'Duplicate' files to see them.

**Why does Windows call the publisher "Unknown"?** The program is free and not code-signed, so Windows cannot name a publisher. See [section 1](#1-installing-and-starting) for what to click.

**Can I use it without an internet connection?** Yes. It only uses the internet when you open the website, the Releases page or the donation links from the Help menu.

**Does it work with cameras connected by USB cable?** Not yet. Use a card reader or copy the camera's folder first. USB camera download (PTP/MTP) is planned.

**Is there a Mac version?** Not at present.

## 20. Getting help

- Website: <https://rexalfes.github.io/Photo-Downloader/>
- Report a problem or ask a question: <https://github.com/RexAlfes/Photo-Downloader/issues> – please attach the saved log file and say which build you use (Help > About).
- Downloads and release notes: <https://github.com/RexAlfes/Photo-Downloader/releases>

Photo Downloader is free software. If it saves you time, the Help menu has donation links.
