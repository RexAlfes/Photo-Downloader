# Photo Downloader - instructions for Claude Code

Free GPL v3 photo-ingest tool (Windows 64-bit primary, Linux GTK 2). Lazarus 4.8 / Free Pascal 3.2.2, `{$mode objfpc}`, forms built in code (no `.lfm`). Repository: https://github.com/RexAlfes/Photo-Downloader (website from the `docs` folder on `main`).

Read `docs/Specification_Current.md` first, then `docs/Continuation_Prompt.txt` (current state, features, open items). `Claude Prompt/` holds the older continuation prompts.

## Building and testing
- Windows: `windows\build.ps1` (Release and debug, with the build number handled; `-Mode Release` for Release only, `-NoGit` without pull/push), or `lazbuild PhotoDownloader.lpi` / the Lazarus IDE (these do not change the number).
- Build modes: *Default* has debug information (about 30 MB, `bin/<os>/`); *Release* has none and strips symbols (about 4 MB, `bin/<os>-release/`): `lazbuild -B --build-mode=Release PhotoDownloader.lpi` (add `--ws=gtk2` on Linux). Published release files are built with Release.
- Linux: `lazbuild -B --ws=gtk2 PhotoDownloader.lpi`. Use GTK 2: the GTK 3 widgetset of Lazarus 4.8 raised an Access Violation in the folder chooser and misplaced windows. Packages: `build-essential libgtk2.0-dev`.
- Cross compiling Windows <-> Linux does not work. Compile on the system you are on, run the program, and report plainly what was and was not tested.
- GitHub Actions (`.github/workflows/build.yml`) compiles Windows and Linux on every push.
- The build number (`BuildNr` in `PhotoDownloader.lpi`) is one number per version of the program code (decided 2026-11-14): debug and Release builds of the same code, and the builds on Windows and Linux, carry the same number; it goes up by one only when the code changed. `AutoIncrementBuild` is off, so the IDE and `lazbuild` use the number in the file and never change it. `build-stamp.txt` holds the number and a fingerprint of the program sources (units, include files, icon, the lpi without its BuildNr / AutoIncrementBuild / LCLWidgetType lines). The build scripts (`windows\build.ps1`, `linux/build.sh`) compare the fingerprint: changed sources raise the number by one and update the stamp, otherwise the number stays; a failed build gives the number back. Build with a script after code changes (an IDE build alone keeps the old number). Pull before building; afterwards commit `PhotoDownloader.lpi` (BuildNr line only; lazbuild's rewrites of `LCLWidgetType` lines are undone by the scripts) and `build-stamp.txt`, and push. Never lower or revert the number (the bundle reset below is the one exception).
- Document and manual titles carry only the version without the build number (for example 0.1.1), never `0.1.1.1` or "build N".

## Versioning
`major.minor.revision.build` in `PhotoDownloader.lpi` (Version Info): Major 0, Minor 1. Every bundle raises the Revision by one and resets the Build to 0 (decided 2026-11-11; the bundles up to 0.1.4.1 used 1): the next bundle is 0.1.5.0, then 0.1.6.0 ... Just before the bundle compile set `BuildNr` to 0 and write `0 <fingerprint>` into `build-stamp.txt` (the fingerprint the scripts compute; the one exception to never lowering the number); the bundle builds are then 0.1.5.0, and the next code change makes 0.1.5.1. Each bundle also gets a new `Claude Prompt/Claude-Prompt-<version>.txt` (same text as `docs/Continuation_Prompt.txt`).

## Bundles (only when I say "create bundle")
Zip name `PhotoDownloader.<version>.zip`, single top-level folder `PhotoDownloader/` with the source, `linux/`, `Claude Prompt/`, `docs/`, `GitHub/` (release notes `Release_Notes_<version>.md`, `Git Instructions.txt`, `GitHub_About.txt`, `Two_Computers_Guide.txt`, `docs/` with the manual and `index.html`), `.github/`, `.gitignore`, `.gitattributes`, `third_party/XelHeic/`, `third_party/metadarkstyle/`, `windows/`, `build-stamp.txt`, `plugins/example/`, `plugins/dng-converter/`, `README.md`, `THIRD_PARTY_NOTICES.md`, `PhotoDownloader.ico`, `.lpi`, `.lpr`. Exclude `lib/`, `bin/`, `backup/`, and never include `Private/` or `Reference Docs/`.

## Keep every document in step with each change/bundle
Every document except README.md is kept in three formats, `.md` (source), `.docx` and `.odt`: run `python docs/make_formats.py` after a change (add new documents to its list). README, spec (header, version-history row, status tables), `docs/Settings_File.md`, launch materials (txt + both docx), `GitHub/Git Instructions.txt`, website (`GitHub/docs/index.html`), release notes, User Manual, Plug-in Developer Manual (`docs/Plugin_Developer_Manual.md`; example library `plugins/example/`), `docs/Continuation_Prompt.txt`.

## Style and rules
- American English. No "Breeze" and no "Downloader Pro" wording. Defaults must be generic (nothing specific to my computer). Notes say "prototype application images", never "screen shots".
- Comment every source file (header comment and line comments, American English).
- FPC set literals cannot hold values above 255; `TBitmap` has no `FreeCanvasContext` in my Lazarus; use `{$POINTERMATH ON}` for `PByte` indexing.
- Link error "Can't create object file ... .exe (error code 5)" means the program is still running.
- Windows exe is unsigned: keep the "Unknown publisher" help (README, manual section 1, website, release notes, launch materials).

## Git
Small commits with a clear message, pull before starting, push when done. Subfolders of `Private/` (git-ignored here) can be separate private repositories with their own README: commit and push there separately, and never copy their content into this public repository. Keep line endings as set by `.gitattributes`. I am new to Git: explain commands briefly and do not force-push.
