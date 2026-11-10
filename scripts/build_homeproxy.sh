#!/bin/bash
# Build RavnHomeProxy.apk — the invisible HOME activity used to resume Centaur's
# MainActivity without going through ChironSplashActivity.
#
# Output: homeproxy/RavnHomeProxy.apk (debug-signed, like the other
# helper APKs on the device).
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../homeproxy"
BT=${BT:-$HOME/Library/Android/sdk/build-tools/34.0.0}
JAR=${JAR:-$HOME/Library/Android/sdk/platforms/android-28/android.jar}
KS=${KS:-$HOME/.android/debug.keystore}
WORK=${WORK:-/tmp/ravn_homeproxy_build}

rm -rf "$WORK"
mkdir -p "$WORK/classes" "$WORK/dex" "$WORK/res"

(cd "$SRC" && "$BT/aapt" package -f -m \
  -M AndroidManifest.xml -S "$WORK/res" -I "$JAR" -F "$WORK/base.apk")

# --release 8 (not -source/-target with -bootclasspath): javac needs
# java.lang.invoke.LambdaMetafactory from the JDK to compile lambdas against
# android.jar; d8 then desugars them. Avoid anonymous/inner classes: d8 34
# crashes on javac's anonymous class output (R8 NPE).
javac --release 8 -classpath "$JAR" \
  -d "$WORK/classes" $(find "$SRC/src" -name '*.java')

# javac emits HomeActivity$1.class etc. for inner/anonymous classes; d8 must
# get every class file, otherwise the dex references missing types and the
# activity dies with NoClassDefFoundError at runtime.
d8 --min-api 28 --output "$WORK/dex" $(find "$WORK/classes" -name '*.class')

cp "$WORK/base.apk" "$WORK/unsigned.apk"
cp "$WORK/dex/classes.dex" "$WORK/classes.dex"
(cd "$WORK" && "$BT/aapt" add unsigned.apk classes.dex >/dev/null)

"$BT/zipalign" -p -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$HERE/../homeproxy/RavnHomeProxy.apk" "$WORK/aligned.apk"
"$BT/apksigner" verify "$HERE/../homeproxy/RavnHomeProxy.apk"
echo "built: $HERE/../homeproxy/RavnHomeProxy.apk"
