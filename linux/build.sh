#!/bin/sh
# Builds Photo Downloader on Linux from the command line (GTK 2 widgetset).
#
#   linux/build.sh            debug build (Default mode)  -> bin/linux/PhotoDownloader
#   linux/build.sh release    Release build (small)       -> bin/linux-release/PhotoDownloader
#   linux/build.sh run        debug build, then start the program
#   linux/build.sh release run
#
# Like the Lazarus IDE, it raises the build number (BuildNr in PhotoDownloader.lpi) by one before
# each build; lazbuild does not do that itself. Commit and push PhotoDownloader.lpi afterwards, so the
# other computer gets the new number and the next pull has nothing to merge.
# Needs Lazarus 4.8 (lazbuild) and the GTK 2 development files: sudo apt install build-essential libgtk2.0-dev
set -e
cd "$(dirname "$0")/.."    # the project folder (this script lies in linux/)

MODE=Default    # build mode: Default (debug information) or Release
RUN=0           # 1 = start the program after building
for A in "$@"; do
  case "$A" in
    release|Release|--release) MODE=Release ;;
    debug|default|Default) MODE=Default ;;
    run|--run) RUN=1 ;;
    -h|--help|help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $A (use release, debug or run)"; exit 1 ;;
  esac
done

if ! command -v lazbuild >/dev/null 2>&1; then
  echo "lazbuild was not found. Install Lazarus 4.8, or add its folder to the PATH."
  exit 1
fi

# raise the build number by one
LPI=PhotoDownloader.lpi
OLD=$(sed -n 's/.*<BuildNr Value="\([0-9]*\)".*/\1/p' "$LPI")
if [ -z "$OLD" ]; then
  echo "No BuildNr found in $LPI"
  exit 1
fi
NEW=$((OLD + 1))
sed -i "s/<BuildNr Value=\"$OLD\"\/>/<BuildNr Value=\"$NEW\"\/>/" "$LPI"
MINOR=$(sed -n 's/.*<MinorVersionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
REV=$(sed -n 's/.*<RevisionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
echo "Building Photo Downloader 0.${MINOR:-0}.${REV:-0}.$NEW ($MODE, GTK 2) ..."

if [ "$MODE" = Release ]; then
  OUT=bin/linux-release/PhotoDownloader
  set -- -B --build-mode=Release --ws=gtk2 "$LPI"
else
  OUT=bin/linux/PhotoDownloader
  set -- -B --build-mode=Default --ws=gtk2 "$LPI"
fi

LOG=$(mktemp)    # the full compiler output, shown only when the build fails
if lazbuild "$@" >"$LOG" 2>&1; then
  grep -E 'lines compiled' "$LOG" | tail -n 1
  rm -f "$LOG"
  echo "Done: $OUT"
else
  grep -E 'Error|Fatal' "$LOG" | head -n 20
  if grep -q "Can't create" "$LOG"; then
    echo "The program file could not be written: close Photo Downloader and build again."
  fi
  echo "Build failed (full output: $LOG)."
  exit 1
fi

if [ "$RUN" = 1 ]; then
  echo "Starting $OUT (messages appear in this terminal) ..."
  exec "./$OUT"
fi
