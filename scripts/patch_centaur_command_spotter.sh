#!/usr/bin/env bash
# Включает командный споттер Centaur («стоп/хватит/пауза/громче/тише»
# без слова «Алиса») в APK.
#
# Проблема: в APK-ассете `assets/quasar/quasar.cfg` стоит
#   "enableCommandSpotters": false
#   "ENABLE_COMMAND_SPOTTERS": false
# поэтому CommandSpotterCapability распознаёт фразу, но отбрасывает её:
#   Command phrase spotted: стоп
#   spotterCommand ... "disabled_reason":"Command spotters disabled",
#                      "phrase_passed":false
# Кроме того, без `libspotterfix.so` командному споттеру не задан путь:
#   createCommandSpotter Do not create command spotter. Spotter path is empty.
#
# Скрипт:
#   1) правит оба флага в assets/quasar/quasar.cfg на true;
#   2) подкладывает spotterfix/libspotterfix.so в lib/armeabi-v7a/
#      (он задаёт путь command-модели и возвращает споттер после диалога);
#   3) zipalign + apksigner (debug key), если найдены в Android SDK.
#
# Использование:
#   scripts/patch_centaur_command_spotter.sh in.apk out.apk
#
# ВАЖНО: APK уже должен содержать голосовой патч (Native.ensure(),
# extractNativeLibs=true) — см. patch/README.md. Скрипт не делает smali-патчи.
set -euo pipefail

IN="${1:?input apk}"
OUT="${2:?output apk}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$IN" "$OUT" "$HERE/spotterfix/libspotterfix.so" <<'PY'
import sys, zipfile

src, dst, libpath = sys.argv[1], sys.argv[2], sys.argv[3]
CFG = 'assets/quasar/quasar.cfg'
LIB = 'lib/armeabi-v7a/libspotterfix.so'

zin = zipfile.ZipFile(src)
cfg = zin.read(CFG).decode('utf-8')
if '"enableCommandSpotters": true' in cfg and '"ENABLE_COMMAND_SPOTTERS": true' in cfg:
    print('quasar.cfg: command spotters already enabled')
else:
    cfg = cfg.replace('"enableCommandSpotters": false',
                      '"enableCommandSpotters": true')
    cfg = cfg.replace('"ENABLE_COMMAND_SPOTTERS": false',
                      '"ENABLE_COMMAND_SPOTTERS": true')
    if '"enableCommandSpotters": true' not in cfg:
        raise SystemExit('enableCommandSpotters pattern not found in quasar.cfg')
    print('quasar.cfg: enableCommandSpotters=true, ENABLE_COMMAND_SPOTTERS=true')

lib = open(libpath, 'rb').read()
zout = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED)
for it in zin.infolist():
    if it.filename == CFG:
        data = cfg.encode('utf-8')
    elif it.filename == LIB:
        data = lib
    else:
        data = zin.read(it.filename)
    zout.writestr(it, data)
zout.close()
print('built', dst)
PY

ZA=$(ls "$HOME"/Library/Android/sdk/build-tools/*/zipalign 2>/dev/null | tail -1 || true)
AS=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | tail -1 || true)
if [ -n "$ZA" ] && [ -n "$AS" ]; then
  "$ZA" -p -f 4 "$OUT" "$TMP/aligned.apk" >/dev/null
  "$AS" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey \
    --out "$TMP/signed.apk" "$TMP/aligned.apk"
  mv "$TMP/signed.apk" "$OUT"
  echo "signed: $OUT"
else
  echo "zipalign/apksigner not found; $OUT is unsigned"
fi
