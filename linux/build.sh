#!/bin/sh
# Builds Photo Downloader on Linux from the command line (GTK 2 widgetset).
#
#   linux/build.sh            debug build (Default mode)  -> bin/linux/PhotoDownloader
#   linux/build.sh release    Release build (small)       -> bin/linux-release/PhotoDownloader
#   linux/build.sh run        debug build, then start the program
#   linux/build.sh release run
#   linux/build.sh --no-git   build without pulling and pushing the build number
#
# The build number: PhotoDownloader.lpi holds the number of the NEXT build. lazbuild puts it into the
# program and then counts it up by one itself (AutoIncrementBuild), like the Lazarus IDE. To keep the
# number in step with the other computer this script first pulls from GitHub, and afterwards commits
# only PhotoDownloader.lpi ("Built 0.1.3.N (Linux)") and pushes it (any of your own commits that were
# not pushed yet go along). Only the BuildNr line changes in the committed file: the other lines
# lazbuild rewrites (LCLWidgetType entries) are left as they were. Without network it warns and builds anyway.
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
    -h|--help|help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# the number this build gets (lazbuild counts the file up afterwards)
BUILT=$(sed -n 's/.*<BuildNr Value="\([0-9]*\)".*/\1/p' "$LPI")
if [ -z "$BUILT" ]; then
  echo "No BuildNr found in $LPI"
  exit 1
fi
NEXT=$((BUILT + 1))
MINOR=$(sed -n 's/.*<MinorVersionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
REV=$(sed -n 's/.*<RevisionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
VER="0.${MINOR:-0}.${REV:-0}.$BUILT"
CLEAN=0   # 1 = the project file had no changes of your own before the build
if [ "$SYNC" = 1 ] && git diff --quiet HEAD -- "$LPI" 2>/dev/null; then CLEAN=1; fi
echo "Building Photo Downloader $VER ($MODE, GTK 2) ..."

if [ "$MODE" = Release ]; then
  OUT=bin/linux-release/PhotoDownloader
  set -- -B --build-mode=Release --ws=gtk2 "$LPI"
else
  OUT=bin/linux/PhotoDownloader
  set -- -B --build-mode=Default --ws=gtk2 "$LPI"
fi

# the project file after the build: the next number (every compile counts, also a failed one); when it
# had no changes of your own, the committed file with only the BuildNr line changed
set_next() {
  if [ "$CLEAN" = 1 ]; then
    git show "HEAD:$LPI" > "$LPI"   # undo the other lines lazbuild rewrote
  fi
  sed -i "s/<BuildNr Value=\"[0-9]*\"\/>/<BuildNr Value=\"$NEXT\"\/>/" "$LPI"
}

# sends the build number to GitHub
push_number() {
  [ "$SYNC" = 1 ] || return 0
  if git commit --quiet -m "Built $VER (Linux)" -- "$LPI" && git push --quiet; then
    echo "Build number sent to GitHub (next build: $NEXT)."
  else
    echo "WARNING: the build number could not be sent to GitHub. Later: git push"
  fi
}

LOG=$(mktemp)    # the full compiler output, shown only when the build fails
if lazbuild "$@" >"$LOG" 2>&1; then
  grep -E 'lines compiled' "$LOG" | tail -n 1
  rm -f "$LOG"
  echo "Done: $OUT (version $VER)"
  set_next
  push_number
else
  grep -E 'Error|Fatal' "$LOG" | head -n 20
  if grep -q "Can't create" "$LOG"; then
    echo "The program file could not be written: close Photo Downloader and build again."
  fi
  echo "Build failed (full output: $LOG)."
  set_next
  push_number
  exit 1
fi

if [ "$RUN" = 1 ]; then
  echo "Starting $OUT (messages appear in this terminal) ..."
  exec "./$OUT"
fi
