#!/bin/sh
# ---------------------------------------------------------------------------------------------
# install-desktop.sh - menu entry and icons for Photo Downloader (current user only, no root)
#
# What it does:
#   1. Copies the icon (4 sizes) into ~/.local/share/icons/hicolor/
#   2. Writes a launcher (photodownloader.desktop) into ~/.local/share/applications/, so the
#      program appears in the application menu and the taskbar groups its windows under the icon
#   3. Sets a custom icon on the program file itself with 'gio set', for file managers that
#      support it (Nemo, Nautilus, Caja). A Linux program file cannot hold an icon of its own.
#
# Usage:
#   ./install-desktop.sh [/full/path/to/PhotoDownloader] [--no-file-icon]
#   ./install-desktop.sh --remove [/full/path/to/PhotoDownloader]
#
# Without a path the program is looked for next to this script, in ../bin/linux and in ../
# --no-file-icon  skips step 3
# --remove        undoes everything (launcher, icons and the file icon)
#
# Run the script again after rebuilding or copying the program: the file icon is lost then.
# ---------------------------------------------------------------------------------------------
set -e   # stop at the first command that fails (commands followed by '|| true' may fail)

# --- locations ---------------------------------------------------------------------------------
HERE="$(cd "$(dirname "$0")" && pwd)"                       # folder of this script (has icons/ and the .desktop template)
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"    # where launchers for the menu live
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"  # where the user's icons live

# --- options -----------------------------------------------------------------------------------
NOFILEICON=0                                                # 1 = do not set the icon on the program file
for A in "$@"; do
  [ "$A" = "--no-file-icon" ] && NOFILEICON=1
done

# --- helper: put the icon on the program file ----------------------------------------------------
# $1 = full path of the program file.
# gio stores the icon as a file:// address, so the characters that are special in an address
# (percent, space, number sign, question mark) are escaped first.
set_file_icon() {
  command -v gio >/dev/null 2>&1 || return 0                # no gio on this system: nothing to do
  URI="file://$(printf '%s' "$ICONS/256x256/apps/photodownloader.png" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g')"
  if gio set "$1" metadata::custom-icon "$URI" 2>/dev/null; then
    echo "File icon set on: $1"
  else
    echo "Could not set the file icon (the menu entry still works)."
  fi
}

# --- --remove: undo everything --------------------------------------------------------------------
if [ "$1" = "--remove" ]; then
  RM_EXE="$2"                                               # program file whose icon is to be cleared
  if [ -z "$RM_EXE" ] || [ "$RM_EXE" = "--no-file-icon" ]; then
    # no path given: look in the same places as for the install
    for C in "$HERE/PhotoDownloader" "$HERE/../bin/linux/PhotoDownloader" "$HERE/../PhotoDownloader"; do
      if [ -e "$C" ]; then RM_EXE="$C"; break; fi
    done
  fi
  if [ -e "$RM_EXE" ] && command -v gio >/dev/null 2>&1; then
    gio set -t unset "$RM_EXE" metadata::custom-icon 2>/dev/null || true   # remove the file icon
  fi
  rm -f "$APPS/photodownloader.desktop"                     # the launcher
  for S in 48 64 128 256; do
    rm -f "$ICONS/${S}x${S}/apps/photodownloader.png"       # the four icon sizes
  done
  # refresh the menu and icon caches (programs may be missing: ignore that)
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONS" || true
  echo "Removed."
  exit 0
fi

# --- find the program ------------------------------------------------------------------------------
EXE="$1"                                                    # first argument = path of the program
if [ -z "$EXE" ] || [ "$EXE" = "--no-file-icon" ]; then
  EXE=""
  for C in "$HERE/PhotoDownloader" "$HERE/../bin/linux/PhotoDownloader" "$HERE/../PhotoDownloader"; do
    if [ -x "$C" ]; then EXE="$C"; break; fi                # first executable found
  done
fi
if [ -z "$EXE" ] || [ ! -x "$EXE" ]; then
  echo "Program not found. Run:  $0 /full/path/to/PhotoDownloader" >&2
  exit 1
fi
EXE="$(cd "$(dirname "$EXE")" && pwd)/$(basename "$EXE")"   # make the path absolute

# --- icons ---------------------------------------------------------------------------------------------
mkdir -p "$APPS"
for S in 48 64 128 256; do
  mkdir -p "$ICONS/${S}x${S}/apps"
  cp "$HERE/icons/PhotoDownloader-${S}x${S}.png" "$ICONS/${S}x${S}/apps/photodownloader.png"
done

# --- launcher ------------------------------------------------------------------------------------------
# The template PhotoDownloader.desktop has the placeholder @EXEC@; it is replaced by the program path.
# The path is put in quotes so that folders with spaces work; backslash, & and | are escaped for sed.
ESC="$(printf '%s' "$EXE" | sed 's/[\\&|]/\\&/g')"
sed "s|@EXEC@|\"$ESC\"|" "$HERE/PhotoDownloader.desktop" > "$APPS/photodownloader.desktop"
chmod 644 "$APPS/photodownloader.desktop"

# refresh the menu and icon caches (programs may be missing: ignore that)
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONS" || true

# --- icon on the program file ---------------------------------------------------------------------------
[ "$NOFILEICON" = "1" ] || set_file_icon "$EXE"

echo "Installed: $APPS/photodownloader.desktop"
echo "Look for Photo Downloader in your application menu (log out and in if it does not show yet)."
echo "If the program file still shows a plain icon, refresh the file manager (F5). Rebuilding or copying the file removes its icon; run this script again."
