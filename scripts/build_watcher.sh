#!/bin/bash
# Build centaur_watcher.dex from CentaurSwipeWatcher.java.
#
# Output: centaur_fix/centaur_watcher.dex (pushed to /data/local/tmp by
# install_top_sheet.sh and started by RavnBootStarter at boot).
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
JAR=${JAR:-$HOME/Library/Android/sdk/platforms/android-28/android.jar}
WORK=${WORK:-/tmp/centaur_watcher_build}

rm -rf "$WORK"
mkdir -p "$WORK/classes" "$WORK/dex"

javac -source 1.8 -target 1.8 -bootclasspath "$JAR" \
  -d "$WORK/classes" "$HERE/../centaur_fix/CentaurSwipeWatcher.java"
d8 --min-api 28 --output "$WORK/dex" "$WORK/classes"/*.class
cp "$WORK/dex/classes.dex" "$HERE/../centaur_fix/centaur_watcher.dex"
echo "built: $HERE/../centaur_fix/centaur_watcher.dex"
