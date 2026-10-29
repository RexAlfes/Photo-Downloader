# PennDOT UAS folder sorter plug-in: draft spec

Status: **draft for the user to confirm.** It is based on the PennDOT UAS folder naming standard (drone portal) and the District 6-0 local file share standard. The source documents are kept outside the repository. Internal server paths, names, phone numbers and email addresses from them are deliberately left out of this file and out of the program: the program stays generic, and the user enters the destination folder.

## 1. Purpose

Sort drone (UAS) downloads into folders named by the PennDOT standard, using new tokens that work in the Download Path templates like the built-in ones. The user fills in the project values once per download in a prompt window; the plug-in turns them into a checked, correctly padded folder name.

## 2. The folder name

```
R-06-09-0095-CAP-CONS
│  │  │   │    │   └─ 6. File type, 4 characters (SURV, MANT, CONS, PRES ...)
│  │  │   │    └───── 5. Section number or survey callout, 3 characters (03M, 04F, CAP)
│  │  │   └────────── 4. State route, 4 digits (0081), or township route: T + 3 digits (T324)
│  │  └────────────── 3. County number, 2 digits (01-67, table in section 6)
│  └───────────────── 2. District number, 2 digits
└──────────────────── 1. Raw or processed, 1 letter (R = raw, P = processed; N, see question 1)
```

Parts are joined with hyphens. Examples from the standard: `R-01-27-0081-03M-SURV`, `P-01-27-0081-03M-SURV`, `N-06-13-T324-04F-MANT`.

## 3. Tokens

| Token | Value | Example |
|---|---|---|
| `{UAS}` | the whole folder name | `R-06-09-0095-CAP-CONS` |
| `{UAS.RP}` | raw / processed letter | `R` |
| `{UAS.Dist}` | district, 2 digits | `06` |
| `{UAS.Cnty}` | county number, 2 digits | `09` |
| `{UAS.CntyName}` | county name | `Bucks` |
| `{UAS.Route}` | route, 4 characters | `0095`, `T324` |
| `{UAS.Sect}` | section / callout | `CAP` |
| `{UAS.Type}` | file type code | `CONS` |
| `{UAS.Sub}` | file-type subfolder of the District 6-0 standard, chosen per file (section 5) | `Photos`, `Video`, `LRV` |

The plug-in's tokens combine with the built-in ones: `{d}` (date `yyyymmdd`), `{J}` (job code), `{T}` (camera / drone model), `{c}` (serial number), `{E}` (extension).

## 4. Two layouts (presets)

| Preset | Folder template | Result |
|---|---|---|
| **Drone portal** (no subfolders allowed) | `<root>\{UAS}\` | `<root>\R-06-09-0095-CAP-CONS\DJI_0001.JPG` |
| **District 6-0 share** (mission-day subfolders allowed) | `<root>\{UAS}\{d}-{J}\` | `<root>\R-06-09-0095-CAP-CONS\20230908-INITIAL\DJI_0001.JPG` |
| District 6-0, by file type | `<root>\{UAS}\{d}-{J}\{UAS.Sub}\` | `...\20230908-INITIAL\Photos\DJI_0001.JPG` |
| District 6-0, by drone | `<root>\{UAS}\{d}-{J}\{T}\{UAS.Sub}\` | `...\20230908-INITIAL\M30T\Video\DJI_0002.MP4` |

`<root>` is whatever folder the user picks; no default path is built in. The presets are offered in the plug-in's Setup and fill the Download Path template, which can still be edited.

## 5. File-type subfolders (`{UAS.Sub}`)

| Files | Subfolder |
|---|---|
| .jpg .jpeg .dng and raw photos | `Photos` |
| .mp4 .mov | `Video` (or `MP4`, see question 4) |
| .lrv | `LRV` |
| thermal (IR) photos | `Photos-IR` (see question 4) |
| thermal (IR) video | `Video-IR` / `MP4-IR` |
| anything else | `Other` |

`Ortho` is processing output, not camera files; it is not produced by the downloader.

## 6. County numbers

| # | County | # | County | # | County | # | County |
|---|---|---|---|---|---|---|---|
| 01 | Adams | 18 | Clinton | 35 | Lackawanna | 52 | Pike |
| 02 | Allegheny | 19 | Columbia | 36 | Lancaster | 53 | Potter |
| 03 | Armstrong | 20 | Crawford | 37 | Lawrence | 54 | Schuylkill |
| 04 | Beaver | 21 | Cumberland | 38 | Lebanon | 55 | Snyder |
| 05 | Bedford | 22 | Dauphin | 39 | Lehigh | 56 | Somerset |
| 06 | Berks | 23 | Delaware | 40 | Luzerne | 57 | Sullivan |
| 07 | Blair | 24 | Elk | 41 | Lycoming | 58 | Susquehanna |
| 08 | Bradford | 25 | Erie | 42 | McKean | 59 | Tioga |
| 09 | Bucks | 26 | Fayette | 43 | Mercer | 60 | Union |
| 10 | Butler | 27 | Forest | 44 | Mifflin | 61 | Venango |
| 11 | Cambria | 28 | Franklin | 45 | Monroe | 62 | Warren |
| 12 | Cameron | 29 | Fulton | 46 | Montgomery | 63 | Washington |
| 13 | Carbon | 30 | Greene | 47 | Montour | 64 | Wayne |
| 14 | Centre | 31 | Huntingdon | 48 | Northampton | 65 | Westmoreland |
| 15 | Chester | 32 | Indiana | 49 | Northumberland | 66 | Wyoming |
| 16 | Clarion | 33 | Jefferson | 50 | Perry | 67 | York |
| 17 | Clearfield | 34 | Juniata | 51 | Philadelphia | | |

## 7. The prompt window

Shown when the download starts (or together with the job code prompt), drawn by the host from the plug-in's field list:

| Field | Control | Rule |
|---|---|---|
| Raw / Processed | choice | R, P (N, see question 1) |
| District | choice | 2 digits (list, see question 3) |
| County | choice by name, shows the number | 01-67 |
| Route | text | 1-4 digits, padded to 4 (`95` → `0095`), or `T` + 3 digits; upper case |
| Section / callout | text | exactly 3 letters or digits; upper case |
| File type | choice with free entry | exactly 4 letters; upper case |
| Recent projects | list | the last folder names used; picking one fills all fields |
| Existing folder | button | pick an existing `R-..-..` folder under the root; its name is parsed into the fields (for later mission days of the same project) |

The window shows the resulting folder name live and does not close while a field breaks its rule. The values are remembered for the next download (plug-in options).

## 8. Failure rules

If a token cannot be filled (for example the prompt was canceled), the download does not start; nothing is copied into a half-named folder. A plug-in failure during the download follows the general rule: the file is not offered for deletion and the plug-in is switched off (see `Plugin_Plan.md`, decision 1).

## 9. Open questions

1. **First letter N.** The standard lists R (raw) and P (processed). What does **N** in `N-06-13-T324-04F-MANT` mean, or is it only a placeholder?
2. **Section and file type codes.** Section is described as "3 digits" and file type as "4 digits", but the examples use letters (`03M`, `CAP`, `SURV`). Is any mix of 3 letters/digits allowed for the section? What is the full list of file type codes and their meanings (SURV, MANT, CONS, PRES ...)?
3. **Districts.** Which district numbers should the list offer (01-12)? Should choosing a county fill in its district automatically (then a county-to-district table is needed)?
4. **Subfolder names and thermal files.** Confirm the names (`Photos`, `Video` or `MP4`, `Video-IR` or `MP4-IR`, `LRV`). How are thermal (IR) files recognized for your drones: by file name suffix (for example DJI `_T`), by camera model, or not at all?
5. **Built as a library.** The plan builds this plug-in as a DLL / .so (phase 3), so PennDOT-specific code stays out of the general program. Agreed, or should it be built into the program?
6. **Style guide.** What should the PennDOT style guide apply to: the prompt window (PMS Blue 281 `#002469` heading bar, Verdana text), a logo in the prompt window, or both? Note that the guide says the logo must be used only from the supplied files, never recreated or stretched, and new uses need review by the PennDOT Communications Office. A logo would therefore be loaded at run time from a file the user places next to the plug-in and would not be stored in the public repository.
