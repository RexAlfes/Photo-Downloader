#!/bin/sh
# Builds Photo Downloader on Linux from the command line (GTK 2 widgetset).
#
#   linux/build.sh            debug build (Default mode)  -> bin/linux/PhotoDownloader
#   linux/build.sh release    Release build (small)       -> bin/linux-release/PhotoDownloader
#   linux/build.sh run        debug build, then start the program
#   linux/build.sh release run
#   linux/build.sh --no-git   build without pulling and pushing the build number
#
# Like the Lazarus IDE, it raises the build number (BuildNr in PhotoDownloader.lpi) by one before
# each build; lazbuild does not do that itself. To keep the number in step with the other computer it
# first pulls from GitHub (so it counts on from the newest number) and afterwards commits only
# PhotoDownloader.lpi ("Build number N (Linux)") and pushes it (any of your own commits that were not
# pushed yet go along). Without network it warns and builds anyway.
# Needs Lazarus 4.8 (lazbuild) and the GTK 2 development files: sudo apt install build-essential libgtk2.0-dev
set -e
cd "$(dirname "$0")/.."    # the project folder (this script lies in linux/)

MODE=Default    # build mode: Default (debug information) or Release
RUN=0           # 1 = start the program after building
SYNC=1          # 1 = pull before and push the build number after the build
for A in "$@"; do
  case "$A" in
    release|Release|--release) MODE=Release ;;
    debug|default|Default) MODE=Default ;;
    run|--run) RUN=1 ;;
    --no-git|nogit|no-git) SYNC=0 ;;
    -h|--help|help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $A (use release, debug, run or --no-git)"; exit 1 ;;
  esac
done
if [ "$SYNC" = 1 ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SYNC=0  # not a git working copy (for example an unpacked bundle): nothing to sync
fi

LPI=PhotoDownloader.lpi
if [ "$SYNC" = 1 ]; then
  echo "Getting the newest version from GitHub (git pull) ..."
  if ! git pull --ff-only --quiet; then
    echo "WARNING: git pull did not work (no network, or changes on both computers)."
    echo "         The build number counts on from this copy; sort it out with git status / git pull later."
  fi
fi

if ! command -v lazbuild >/dev/null 2>&1; then
  echo "lazbuild was not found. Install Lazarus 4.8, or add its folder to the PATH."
  exit 1
fi

# raise the build number by one
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

# sends the new build number to GitHub (every compile counts, also a failed one)
push_number() {
  [ "$SYNC" = 1 ] || return 0
  if git commit --quiet -m "Build number $NEW (Linux)" -- "$LPI" && git push --quiet; then
    echo "Build number $NEW sent to GitHub."
  else
    echo "WARNING: the build number $NEW could not be sent to GitHub. Later: git push"
  fi
}

LOG=$(mktemp)    # the full compiler output, shown only when the build fails
if lazbuild "$@" >"$LOG" 2>&1; then
  grep -E 'lines compiled' "$LOG" | tail -n 1
  rm -f "$LOG"
  echo "Done: $OUT"
  push_number
else
  grep -E 'Error|Fatal' "$LOG" | head -n 20
  if grep -q "Can't create" "$LOG"; then
    echo "The program file could not be written: close Photo Downloader and build again."
  fi
  echo "Build failed (full output: $LOG)."
  push_number
  exit 1
fi

if [ "$RUN" = 1 ]; then
  echo "Starting $OUT (messages appear in this terminal) ..."
  exec "./$OUT"
fi
