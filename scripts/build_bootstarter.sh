#!/bin/bash
# Rebuild RavnBootStarter.apk from bootstarter/src/.
#
# The manifest is kept from the existing APK (it has no resources); only
# classes.dex is replaced and the APK is re-signed with the debug key, so
# `adb install -r` preserves app data.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
JAR=${JAR:-$HOME/Library/Android/sdk/platforms/android-28/android.jar}
BT=${BT:-$HOME/Library/Android/sdk/build-tools/34.0.0}
KS=${KS:-$HOME/.android/debug.keystore}
WORK=${WORK:-/tmp/ravn_bootstarter_build}
BASE=${BASE:-$HERE/../bootstarter/RavnBootStarter.apk}

rm -rf "$WORK"
mkdir -p "$WORK/classes" "$WORK/dex"

javac -source 1.8 -target 1.8 -bootclasspath "$JAR" \
  -d "$WORK/classes" $(find "$HERE/../bootstarter/src" -name '*.java')
d8 --min-api 28 --output "$WORK/dex" $(find "$WORK/classes" -name '*.class')

cp "$BASE" "$WORK/unsigned.apk"
zip -q -d "$WORK/unsigned.apk" 'META-INF/*' classes.dex 2>/dev/null || true
(cd "$WORK/dex" && zip -q "$WORK/unsigned.apk" classes.dex)

"$BT/zipalign" -p -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$WORK/RavnBootStarter.apk" "$WORK/aligned.apk"
"$BT/apksigner" verify "$WORK/RavnBootStarter.apk"
cp "$WORK/RavnBootStarter.apk" "$BASE"
echo "built: $BASE"
