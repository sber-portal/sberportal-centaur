#!/usr/bin/env bash
# Ночной режим Centaur на SberPortal.
#
# Проблема: приложение ждёт секцию конфига `system.centaur` от бэкенда
# (в ней `brightness_settings`: пороги lux, окно усреднения, таймауты).
# Яндекс для нашего `device_id` (platform wk7y) эту секцию не отдаёт:
#   Config observer native/c++ subscription to system [centaur]
#   Config observer received system - appmetrikaReportEnvironment   (только это)
# Поэтому:
#   * BrightnessReadingService никогда не регистрирует датчик света,
#   * lux = null,
#   * NightModeController остаётся в дефолтном состоянии «день»,
#   * часы на чёрном фоне не появляются.
#
# Что делает скрипт:
#   1. BrightnessReadingService$b: вместо IO-конфига подставляет
#      `CentaurConfig.e0` (значения по умолчанию).
#   2. q40/f (NightModeController): то же самое для combine-потока.
#   3. CentaurConfig$e(): разумные дефолты brightness_settings —
#      период чтения 1000 мс, окно усреднения 5 (в стоке -1 и 0,
#      из-за чего lux всегда 0).
#
# Использование:
#   APKTOOL_DIR=/tmp/centaur_dec scripts/patch_centaur_night_mode.sh [out.apk]
set -euo pipefail

DIR="${APKTOOL_DIR:?set APKTOOL_DIR to an apktool project dir with classes4 smali}"
OUT="${1:-centaur_night.apk}"

python3 - "$DIR" <<'PY'
import os, sys

root = sys.argv[1]

# 1) BrightnessReadingService$b: default CentaurConfig instead of IO config
p = os.path.join(root, 'smali/ru/yandex/quasar/centaur_app/brightness/BrightnessReadingService$b.smali')
s = open(p).read()
old = '''    iget-object v1, v1, Lb10/a;->f:Le10/r0;

    .line 33
    .line 34
    iget-object v1, v1, Le10/r0;->l:Lkotlinx/coroutines/flow/j1;
'''
new = '''    # patched: backend doesn't send the "centaur" config section, use defaults
    sget-object v1, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig;->e0:Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig;

    invoke-static {v1}, Lcom/yandex/passport/internal/j;->a(Ljava/lang/Object;)Lkotlinx/coroutines/flow/v1;

    move-result-object v1

    new-instance v4, Lkotlinx/coroutines/flow/j1;

    invoke-direct {v4, v1, v3}, Lkotlinx/coroutines/flow/j1;-><init>(Lkotlinx/coroutines/flow/m1;Lkotlinx/coroutines/e2;)V

    move-object v1, v4
'''
if old not in s:
    raise SystemExit('BrightnessReadingService$b: config flow pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched BrightnessReadingService$b')

# 2) NightModeController: default CentaurConfig flow
p = os.path.join(root, 'smali/q40/f.smali')
s = open(p).read()
old = '''    iget-object p3, p4, Lb10/a;->f:Le10/r0;

    .line 37
    .line 38
    iget-object p3, p3, Le10/r0;->l:Lkotlinx/coroutines/flow/j1;
'''
new = '''    # patched: use default CentaurConfig when backend has no "centaur" section
    sget-object p3, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig;->e0:Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig;

    invoke-static {p3}, Lcom/yandex/passport/internal/j;->a(Ljava/lang/Object;)Lkotlinx/coroutines/flow/v1;

    move-result-object p3
'''
if old not in s:
    raise SystemExit('q40/f: config flow pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched q40/f (NightModeController)')

# 3) sane BrightnessSettings defaults
p = os.path.join(root, 'smali/ru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig$e.smali')
s = open(p).read()
old = '''    const-wide/16 v0, -0x1

    .line 3
    iput-wide v0, p0, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig$e;->a:J

    const/4 p1, 0x0

    .line 4
    iput p1, p0, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig$e;->b:I
'''
new = '''    const-wide/16 v0, 0x3e8

    .line 3
    iput-wide v0, p0, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig$e;->a:J

    const/4 p1, 0x0

    .line 4
    # patched: sane defaults when backend has no brightness_settings
    const/4 v0, 0x5

    iput v0, p0, Lru/yandex/quasar/centaur_app/ioservice/utils/config/CentaurConfig$e;->b:I
'''
if old not in s:
    raise SystemExit('CentaurConfig$e: defaults pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched CentaurConfig$e defaults (1000ms, window 5)')
PY

cd "$(dirname "$DIR")"
apktool b "$(basename "$DIR")" -o "$OUT"

echo "Готово: $OUT"
echo "Дальше: zipalign -p -f 4 $OUT aligned.apk && apksigner sign ... aligned.apk"
