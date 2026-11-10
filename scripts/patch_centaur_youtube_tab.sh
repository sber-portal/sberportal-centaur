#!/bin/bash
# Make Centaur's YouTube tab open StarTube instead of its internal WebView.
#
# Centaur loads m.youtube.com inside its own WebView through
# p60.h.j(String url). This patch intercepts that call: when the URL contains
# "youtube.com", it starts ru.sberdevices.startube/.ui.StarTubeActivity and
# returns without loading the page.
#
# Usage: ./scripts/patch_centaur_youtube_tab.sh <centaur.apk> [out.apk]
# Requires: apktool, zipalign/apksigner, ~/.android/debug.keystore.
# The input APK must be signed with the same debug key as the installed one,
# otherwise `adb install -r` will refuse to update (uninstall loses data).
set -e

IN=${1:?укажи APK Centaur}
OUT=${2:-$(cd "$(dirname "$IN")" && pwd)/centaur-youtube-tab-patched.apk}
HERE=$(cd "$(dirname "$0")/.." && pwd)
BT=${BT:-$HOME/Library/Android/sdk/build-tools/34.0.0}
KS=${KS:-$HOME/.android/debug.keystore}
WORK=${WORK:-$HERE/.patch-youtube-tab}

[ -f "$IN" ] || { echo "no such apk: $IN" >&2; exit 1; }
[ -f "$KS" ] || { echo "keystore not found: $KS" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"

echo "[1/5] apktool decode"
apktool d -f -o "$WORK/decoded" "$IN" >/dev/null

SMALI="$WORK/decoded/smali_classes5/p60/h.smali"
[ -f "$SMALI" ] || { echo "unexpected APK: $SMALI not found" >&2; exit 1; }

echo "[2/5] patch p60/h.j(String url)"
python3 - "$SMALI" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''.method public final j(Ljava/lang/String;)V
    .locals 1

    .line 1'''
new = '''.method public final j(Ljava/lang/String;)V
    .locals 3

    const-string v0, "youtube.com"

    invoke-virtual {p1, v0}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v0

    if-eqz v0, :cont

    new-instance v0, Landroid/content/Intent;

    invoke-direct {v0}, Landroid/content/Intent;-><init>()V

    const-string v1, "ru.sberdevices.startube"

    const-string v2, "ru.sberdevices.startube.ui.StarTubeActivity"

    invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const/high16 v1, 0x10000000

    invoke-virtual {v0, v1}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;

    iget-object v1, p0, Lp60/h;->e:Landroid/webkit/WebView;

    invoke-virtual {v1}, Landroid/webkit/WebView;->getContext()Landroid/content/Context;

    move-result-object v1

    invoke-virtual {v1, v0}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V

    return-void

    :cont
    .line 1'''
if old not in s:
    sys.exit("patch point not found: Centaur version differs")
open(p, 'w').write(s.replace(old, new, 1))
print("patched")
PY

echo "[3/5] apktool build"
apktool b -o "$WORK/unsigned.apk" "$WORK/decoded" >/dev/null

echo "[4/5] zipalign"
"$BT/zipalign" -p -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"

echo "[5/5] sign"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
    --out "$OUT" "$WORK/aligned.apk"
"$BT/apksigner" verify "$OUT" >/dev/null

echo "built: $OUT"
echo
echo "Install (same debug key, data is preserved):"
echo "  adb -s <IP>:5555 install -r \"$OUT\""
