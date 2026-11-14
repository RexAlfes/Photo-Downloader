#!/bin/sh
# Builds Photo Downloader on Linux from the command line (GTK 2 widgetset).
#
#   linux/build.sh            debug build (Debug mode)    -> bin/linux-debug/PhotoDownloader
#   linux/build.sh release    Release build (small)       -> bin/linux-release/PhotoDownloader
#   linux/build.sh both       both, one after the other, with the same build number
#   linux/build.sh run        debug build, then start the program
#   linux/build.sh release run
#   linux/build.sh --no-git   build without pulling and pushing the build number
#
# The build number: one number per version of the program code. build-stamp.txt holds the number and
# a fingerprint of the program sources (units, project file without its BuildNr line); when the
# sources changed since then, the number goes up by one, otherwise it stays, so debug and Release
# builds of the same code (and the builds on Windows and Linux) carry the same number.
# PhotoDownloader.lpi holds that number (AutoIncrementBuild is off). The script first pulls from
# GitHub; after a successful build with a new number it commits only PhotoDownloader.lpi and
# build-stamp.txt ("Built 0.1.4.N (Linux)") and pushes them (any of your own commits that were not
# pushed yet go along). The lines lazbuild rewrites in the project file (LCLWidgetType entries) are
# put back as they were. Without network it warns and builds anyway. Windows: windows/build.ps1.
# Needs Lazarus 4.8 (lazbuild) and the GTK 2 development files: sudo apt install build-essential libgtk2.0-dev
set -e
cd "$(dirname "$0")/.."    # the project folder (this script lies in linux/)

MODES=Debug     # build modes, in order: Debug (debug information) and/or Release
RUN=0           # 1 = start the program after building
SYNC=1          # 1 = pull before and push the build number after the build
for A in "$@"; do
  case "$A" in
    release|Release|--release) MODES=Release ;;
    debug|Debug|default|Default) MODES=Debug ;;
    both|all|--both) MODES="Debug Release" ;;
    run|--run) RUN=1 ;;
    --no-git|nogit|no-git) SYNC=0 ;;
    -h|--help|help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $A (use release, debug, both, run or --no-git)"; exit 1 ;;
  esac
done
if [ "$SYNC" = 1 ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SYNC=0  # not a git working copy (for example an unpacked bundle): nothing to sync
fi

LPI=PhotoDownloader.lpi
STAMP=build-stamp.txt
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

# fingerprint of the program sources: the units, include files and icon Git knows (normalized line
# endings, so it is the same on Windows and Linux) and the project file without the lines that change
# with each build; windows/build.ps1 computes the same value
fingerprint() {
  LPIHASH=$(grep -v -E '<BuildNr |<AutoIncrementBuild |LCLWidgetType|<MacroValues|</MacroValues>' "$LPI" | tr -d '\r' | git hash-object --stdin)
  {
    git ls-files -- '*.pas' '*.pp' '*.lpr' '*.inc' '*.lrs' '*.ico' '*.darkstylecolors' ':!plugins' | git hash-object --stdin-paths
    echo "$LPIHASH"
  } | git hash-object --stdin
}

# the build number of this code: the stamp's number, one more when the sources changed
FP=$(fingerprint)
STAMPNR=$(sed -n '1s/^\([0-9]*\) .*/\1/p' "$STAMP" 2>/dev/null || true)
STAMPFP=$(sed -n '1s/^[0-9]* \(.*\)$/\1/p' "$STAMP" 2>/dev/null || true)
if [ -z "$STAMPNR" ]; then   # no stamp yet: the number in the project file counts as used
  STAMPNR=$(sed -n 's/.*<BuildNr Value="\([0-9]*\)".*/\1/p' "$LPI")
fi
cp "$LPI" "$LPI.before"   # to undo the number when the build fails
cp "$STAMP" "$STAMP.before" 2>/dev/null || : > "$STAMP.before"
if [ "$FP" = "$STAMPFP" ]; then
  BUILT=$STAMPNR
  echo "The program code has not changed since build $BUILT: the number stays."
else
  BUILT=$((STAMPNR + 1))
  echo "$BUILT $FP" > "$STAMP"
fi
sed -i "s/<BuildNr Value=\"[0-9]*\"\/>/<BuildNr Value=\"$BUILT\"\/>/" "$LPI"
MINOR=$(sed -n 's/.*<MinorVersionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
REV=$(sed -n 's/.*<RevisionNr Value="\([0-9]*\)".*/\1/p' "$LPI")
VER="0.${MINOR:-0}.${REV:-0}.$BUILT"
cp "$LPI" "$LPI.keep"   # the project file as it should stay (lazbuild rewrites some lines)
FIRST_OUT=""  # the program file of the first build (started with "run")

# builds one mode ($1); returns 1 when the build failed
build_one() {
  MODE=$1
  echo "Building Photo Downloader $VER ($MODE, GTK 2) ..."
  if [ "$MODE" = Release ]; then
    OUT=bin/linux-release/PhotoDownloader
  else
    OUT=bin/linux-debug/PhotoDownloader
  fi
  [ -n "$FIRST_OUT" ] || FIRST_OUT=$OUT
  LOG=$(mktemp)    # the full compiler output, shown only when the build fails
  if lazbuild -B --build-mode="$MODE" --ws=gtk2 "$LPI" >"$LOG" 2>&1; then
    cp "$LPI.keep" "$LPI"   # undo the lines lazbuild rewrote
    grep -E 'lines compiled' "$LOG" | tail -n 1
    rm -f "$LOG"
    echo "Done: $OUT (version $VER)"
    return 0
  fi
  cp "$LPI.keep" "$LPI"
  grep -E 'Error|Fatal' "$LOG" | head -n 20
  if grep -q "Can't create" "$LOG"; then
    echo "The program file could not be written: close Photo Downloader and build again."
  fi
  echo "Build failed (full output: $LOG)."
  return 1
}

FAILED=0
for M in $MODES; do
  if ! build_one "$M"; then FAILED=1; break; fi   # stop at the first failed build
done
rm -f "$LPI.keep"
if [ "$FAILED" = 1 ]; then
  mv "$LPI.before" "$LPI"   # the number was not used: back to what it was
  if [ -s "$STAMP.before" ]; then mv "$STAMP.before" "$STAMP"; else rm -f "$STAMP" "$STAMP.before"; fi
  exit 1
fi
rm -f "$LPI.before" "$STAMP.before"

# sends a new build number to GitHub
if [ "$SYNC" = 1 ] && ! git diff --quiet HEAD -- "$LPI" "$STAMP" 2>/dev/null; then
  git add "$STAMP"
  if git commit --quiet -m "Built $VER (Linux)" -- "$LPI" "$STAMP" && git push --quiet; then
    echo "Build number $BUILT sent to GitHub."
  else
    echo "WARNING: the build number could not be sent to GitHub. Later: git push"
  fi
fi

if [ "$RUN" = 1 ]; then
  echo "Starting $FIRST_OUT (messages appear in this terminal) ..."
  exec "./$FIRST_OUT"
fi
