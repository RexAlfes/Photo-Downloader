#!/bin/sh
# Installs a menu / launcher entry and the icon for Photo Downloader (current user only).
# Usage:  ./install-desktop.sh [/full/path/to/PhotoDownloader]
# Without an argument it looks for the program next to this script, in ../bin/linux and in ../.
# Undo with:  ./install-desktop.sh --remove
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

if [ "$1" = "--remove" ]; then
  rm -f "$APPS/photodownloader.desktop"
  for S in 48 64 128 256; do rm -f "$ICONS/${S}x${S}/apps/photodownloader.png"; done
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONS" || true
  echo "Removed."
  exit 0
fi

EXE="$1"
if [ -z "$EXE" ]; then
  for C in "$HERE/PhotoDownloader" "$HERE/../bin/linux/PhotoDownloader" "$HERE/../PhotoDownloader"; do
    if [ -x "$C" ]; then EXE="$C"; break; fi
  done
fi
if [ -z "$EXE" ] || [ ! -x "$EXE" ]; then
  echo "Program not found. Run:  $0 /full/path/to/PhotoDownloader" >&2
  exit 1
fi
EXE="$(cd "$(dirname "$EXE")" && pwd)/$(basename "$EXE")"

mkdir -p "$APPS"
for S in 48 64 128 256; do
  mkdir -p "$ICONS/${S}x${S}/apps"
  cp "$HERE/icons/PhotoDownloader-${S}x${S}.png" "$ICONS/${S}x${S}/apps/photodownloader.png"
done

# The Exec value is quoted so that folders with spaces work.
ESC="$(printf '%s' "$EXE" | sed 's/[\\&|]/\\&/g')"
sed "s|@EXEC@|\"$ESC\"|" "$HERE/PhotoDownloader.desktop" > "$APPS/photodownloader.desktop"
chmod 644 "$APPS/photodownloader.desktop"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONS" || true
echo "Installed: $APPS/photodownloader.desktop"
echo "Look for Photo Downloader in your application menu (log out and in if it does not show yet)."
