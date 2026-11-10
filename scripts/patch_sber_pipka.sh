#!/bin/bash
# Patch ru.sberdevices.services so Sber's Pipka pill is not shown over Centaur.
#
# GestureNavigationImpl has a hardcoded allowlist:
#   ru.sberdevices.starlauncher, ru.sberdevices.app.setup
# Pipka is shown on every other foreground app, including Centaur.  This patch
# adds ru.yandex.quasar.centaur_app and com.ravn.homeproxy to that set.
#
# The result is NOT installed (system signature).  It is bind-mounted over
# /vendor/priv-app/StarDroidStarServices/StarDroidStarServices.apk by
# CentaurSwipeWatcher (ensurePipkaPatch).
#
# Usage: ./patch_sber_pipka.sh [StarDroidStarServices.apk] [out.apk]
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
D=${D:?укажи адрес портала: D=192.168.1.x:5555}
IN=${1:-}
OUT=${2:-$HERE/../centaur_fix/StarDroidStarServices_pipka_patched.apk}
WORK=${WORK:-/tmp/sber_pipka_patch}
BT=${BT:-$HOME/Library/Android/sdk/build-tools/34.0.0}
KS=${KS:-$HOME/.android/debug.keystore}

if [ -z "$IN" ]; then
    IN=$WORK/StarDroidStarServices.apk
    mkdir -p "$WORK"
    adb -s "$D" pull /vendor/priv-app/StarDroidStarServices/StarDroidStarServices.apk "$IN"
fi
[ -f "$IN" ] || { echo "no such apk: $IN"; exit 1; }
[ -f "$KS" ] || { echo "keystore not found: $KS"; exit 1; }

rm -rf "$WORK/decoded" "$WORK/built.apk" "$WORK/classes2.dex"
mkdir -p "$WORK/decoded"

echo "[1/5] apktool decode"
apktool d -f -o "$WORK/decoded" "$IN" >/dev/null

echo "[2/5] add Centaur/HomeProxy to Pipka allowlist"
python3 - "$WORK/decoded/smali_classes2/u90/e.smali" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''.method static constructor <clinit>()V
    .locals 2

    const-string v0, "ru.sberdevices.starlauncher"

    const-string v1, "ru.sberdevices.app.setup"

    filled-new-array {v0, v1}, [Ljava/lang/String;
'''
new = '''.method static constructor <clinit>()V
    .locals 4

    const-string v0, "ru.sberdevices.starlauncher"

    const-string v1, "ru.sberdevices.app.setup"

    const-string v2, "ru.yandex.quasar.centaur_app"

    const-string v3, "com.ravn.homeproxy"

    filled-new-array {v0, v1, v2, v3}, [Ljava/lang/String;
'''
assert old in s, 'GestureNavigationImpl <clinit> not found'
open(p, 'w').write(s.replace(old, new, 1))
PY

echo "[3/5] rebuild classes2.dex"
apktool b --no-crunch -o "$WORK/built.apk" "$WORK/decoded" >/dev/null
unzip -p "$WORK/built.apk" classes2.dex > "$WORK/classes2.dex"

echo "[4/5] replace classes2.dex in the original APK"
cp "$IN" "$WORK/unsigned.apk"
zip -q -d "$WORK/unsigned.apk" 'META-INF/*' classes2.dex 2>/dev/null || true
(cd "$WORK" && zip -q unsigned.apk classes2.dex)

echo "[5/5] zipalign + sign"
"$BT/zipalign" -p -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
    --out "$OUT" "$WORK/aligned.apk" >/dev/null
"$BT/apksigner" verify "$OUT" >/dev/null
echo "built: $OUT"
