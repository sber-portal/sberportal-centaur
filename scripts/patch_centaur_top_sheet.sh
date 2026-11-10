#!/bin/bash
# Patch official Centaur APK so that MainActivity.onNewIntent opens the top sheet.
#
# Requires the *official* Centaur APK with versionName 2000008757.212.71.202401070835
# (the only version this smali patch was verified against) and baksmali/smali jars.
#
# Usage:
#   ./patch_centaur_top_sheet.sh <official-centaur.apk> [out.apk]
#
# Output: centaur_top_sheet_signed.apk, signed with the standard Android debug key
# (same key the working device install uses; keeps app data on `adb install -r`).
set -e

IN=${1:?usage: patch_centaur_top_sheet.sh <official-centaur.apk> [out.apk]}
OUT=${2:-centaur_top_sheet_signed.apk}
WORK=${WORK:-/tmp/centaur_patch_$$}

BT=${BT:-$HOME/Library/Android/sdk/build-tools/34.0.0}
AJ=${AJ:-$HOME/Library/Android/sdk/platforms/android-28/android.jar}
BAKSMALI=${BAKSMALI:-baksmali-3.0.9-fat.jar}
SMALI=${SMALI:-smali-3.0.9-fat.jar}
KS=${KS:-$HOME/.android/debug.keystore}

[ -f "$IN" ] || { echo "no such apk: $IN"; exit 1; }
[ -f "$BAKSMALI" ] || { echo "baksmali jar not found: $BAKSMALI"; exit 1; }
[ -f "$SMALI" ] || { echo "smali jar not found: $SMALI"; exit 1; }
[ -f "$KS" ] || { echo "keystore not found: $KS"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

echo "[1/6] extract classes4.dex"
unzip -o -q "$IN" classes4.dex

echo "[2/6] baksmali"
java -jar "$BAKSMALI" d classes4.dex -o sm >/dev/null

echo "[3/6] patch MainActivity.onNewIntent (open drawer with q(0x30), not close with c)"
python3 - <<'PY'
p = 'sm/ru/yandex/quasar/centaur_app/MainActivity.smali'
s = open(p).read()
start = s.index('    :goto_1a\n')
end = s.index('    .line 1\n    :cond_3e\n')
new = '''    :goto_1a
    if-eqz v0, :cond_3e

    instance-of v1, v0, Lru/yandex/quasar/centaur_app/ui/views/CentaurDrawerLayout;

    if-eqz v1, :cond_walk

    move-object v2, v0

    check-cast v2, Lru/yandex/quasar/centaur_app/ui/views/CentaurDrawerLayout;

    const/4 v1, 0x0

    invoke-virtual {v2, v1}, Lru/yandex/quasar/centaur_app/ui/views/CentaurDrawerLayout;->setDrawerLockMode(I)V

    const/16 v1, 0x30

    invoke-virtual {v2, v1}, Lru/yandex/quasar/centaur_app/ui/views/CentaurDrawerLayout;->q(I)V

    goto :cond_3e

    :cond_walk
    invoke-interface {v0}, Landroid/view/ViewParent;->getParent()Landroid/view/ViewParent;

    move-result-object v0

    goto :goto_1a

'''
s = s[:start] + new + s[end:]
open(p, 'w').write(s)
print("patched onNewIntent")
PY

echo "[3b/6] rebind visible top-sheet controls (Home/Settings/Auto/Brightness/Volume)"
python3 - <<'PY2'
p = 'sm/hz/u.smali'
s = open(p).read()
old = '    .registers 14\n'
assert old in s, 'hz/u constructor register line not found'
s = s.replace(old, '    .locals 2\n', 1)
marker = '    iput-object p13, p0, Lhz/u;->m:Lru/yandex/quasar/centaur_app/ui/views/slider/VolumeSlider;\n'
assert marker in s, 'hz/u volume field assignment not found'
rebind = marker + r'''    # The Centaur layout contains two button bars: the hidden
    # TopSheetAdvancedButtons (first matching ids, listeners attached there)
    # and the visible `buttons` LinearLayout.  Rebind the controls to the
    # visible bar so taps reach the handlers.  Use View.findViewById, not
    # LinearLayout.findViewById: classes4.dex is exactly at the 65536-method
    # limit and a new method reference makes smali fail to assemble.
    const v0, 0x7f0b0250
    invoke-virtual {p6, v0}, Landroid/view/View;->findViewById(I)Landroid/view/View;
    move-result-object v1
    check-cast v1, Landroid/widget/ImageView;
    iput-object v1, p0, Lhz/u;->i:Landroid/widget/ImageView;

    const v0, 0x7f0b043e
    invoke-virtual {p6, v0}, Landroid/view/View;->findViewById(I)Landroid/view/View;
    move-result-object v1
    check-cast v1, Landroid/widget/ImageView;
    iput-object v1, p0, Lhz/u;->j:Landroid/widget/ImageView;

    const v0, 0x7f0b0085
    invoke-virtual {p6, v0}, Landroid/view/View;->findViewById(I)Landroid/view/View;
    move-result-object v1
    check-cast v1, Lru/yandex/quasar/centaur_app/ui/views/main/CentaurTopSheetToggleButton;
    iput-object v1, p0, Lhz/u;->c:Lru/yandex/quasar/centaur_app/ui/views/main/CentaurTopSheetToggleButton;

    const v0, 0x7f0b00ae
    invoke-virtual {p6, v0}, Landroid/view/View;->findViewById(I)Landroid/view/View;
    move-result-object v1
    check-cast v1, Lru/yandex/quasar/centaur_app/ui/views/slider/BrightnessSlider;
    iput-object v1, p0, Lhz/u;->e:Lru/yandex/quasar/centaur_app/ui/views/slider/BrightnessSlider;

    const v0, 0x7f0b0543
    invoke-virtual {p6, v0}, Landroid/view/View;->findViewById(I)Landroid/view/View;
    move-result-object v1
    check-cast v1, Lru/yandex/quasar/centaur_app/ui/views/slider/VolumeSlider;
    iput-object v1, p0, Lhz/u;->m:Lru/yandex/quasar/centaur_app/ui/views/slider/VolumeSlider;
'''
s = s.replace(marker, rebind, 1)
open(p, 'w').write(s)
print('patched top-sheet controls')
PY2

echo "[4/6] assemble classes4.dex"
java -jar "$SMALI" a sm -o classes4.dex >/dev/null

echo "[5/6] repack (keep META-INF/services, drop old signatures)"
cp "$IN" out.apk
zip -q -d out.apk 'META-INF/*.RSA' 'META-INF/*.SF' 'META-INF/*.MF' 'META-INF/MANIFEST.MF' 2>/dev/null || true
zip -q out.apk classes4.dex

echo "[6/6] zipalign + sign"
"$BT/zipalign" -p -f 4 out.apk out_aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT" out_aligned.apk

echo "done: $OUT"
