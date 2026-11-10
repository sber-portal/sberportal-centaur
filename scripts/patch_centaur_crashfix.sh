#!/usr/bin/env bash
# Фикс SIGABRT Centaur после голосовой команды.
#
# Диагностика (tombstone, Frida):
#   Fatal signal 6 (SIGABRT), tid VoiceService
#   #01 libquasar_daemons.so + 0x24fffb8   (abort)
#   #02 libquasar_daemons.so + 0x24f9fec
#   #03 libquasar_daemons.so + 0x38ec088
# На входе в 0x24f9e90 Frida видит строки "getValue" и "hasValue()",
# ключ поиска "time": нативный код делает CHECK(getValue().hasValue())
# и вызывает fatal-хелпер (0x24f9e90), если в ответе/директе нет поля time.
# Для голосовых ответов поле отсутствует -> abort.
#
# Что делает патч: заменяет первую инструкцию fatal-хелпера
# (libquasar_daemons.so, offset 0x24f9e90) на `bx lr`.
# Тогда проверка не убивает процесс: вызывающая функция штатно
# доходит до своей очистки и возвращается.
#
# ВАЖНО: offset привязан к этой версии libquasar_daemons.so
# (Centaur 4.16.1, sha256 85d5f1ff214ce81117b180e345473a2b8bac3f773b8fff5e818e06c5d4e3fe22).
#
# Использование:
#   scripts/patch_centaur_crashfix.sh in.apk out.apk
set -euo pipefail

IN="${1:?input apk}"
OUT="${2:?output apk}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$IN" "$TMP" <<'PY'
import sys, zipfile, hashlib, struct, os
src, tmp = sys.argv[1], sys.argv[2]
LIB='lib/armeabi-v7a/libquasar_daemons.so'
OFF=0x24f9e90
EXPECTED='85d5f1ff214ce81117b180e345473a2b8bac3f773b8fff5e818e06c5d4e3fe22'

z=zipfile.ZipFile(src)
data=bytearray(z.read(LIB))
sha=hashlib.sha256(data).hexdigest()
if sha != EXPECTED:
    raise SystemExit(f'unexpected lib sha256: {sha}\nupdate OFF for this build')
if bytes(data[OFF:OFF+4]) != bytes.fromhex('00482de9'):
    raise SystemExit('unexpected bytes at patch offset: '+data[OFF:OFF+4].hex())
data[OFF:OFF+4]=bytes.fromhex('1eff2fe1')  # bx lr
open(os.path.join(tmp,'lib.so'),'wb').write(data)
print('patched lib at', hex(OFF))
PY

python3 - "$IN" "$OUT" "$TMP/lib.so" <<'PY'
import sys, zipfile
src, dst, libpath = sys.argv[1], sys.argv[2], sys.argv[3]
LIB='lib/armeabi-v7a/libquasar_daemons.so'
lib=open(libpath,'rb').read()
zin=zipfile.ZipFile(src)
zout=zipfile.ZipFile(dst,'w',zipfile.ZIP_DEFLATED)
for it in zin.infolist():
    data = lib if it.filename==LIB else zin.read(it.filename)
    zout.writestr(it, data)
zout.close()
print('built', dst)
PY

ZA=$(ls ~/Library/Android/sdk/build-tools/*/zipalign 2>/dev/null | tail -1)
AS=$(ls ~/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | tail -1)
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
