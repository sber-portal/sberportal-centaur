# Top sheet и HOME на SberPortal

Верхний свайп открывает шторку Centaur; HOME открывает Centaur без пустого экрана.
`ru.sberdevices.services` остаётся включённым, `device_id`/ключи Centaur не меняются.

## Архитектура

```
свайп от верхней кромки
  → WindowManager (system logcat): sendSwipeRealizedBroadcast SWIPE_GESTURE_TYPE: 2
     → ru.sberdevices.services: HOME (остаётся, не мешает)
  → CentaurSwipeWatcher (root, app_process): ждёт ~250 мс
     → am start ru.yandex.quasar.centaur_app/.MainActivity --ez open_top_sheet true
        → MainActivity.onNewIntent (патч APK)
           → topSheetFragment → getParent()… → CentaurDrawerLayout.q(0x30)   // open
```

HOME идёт через `com.ravn.homeproxy/.HomeActivity` — невидимую activity, которая
резюмирует существующую `MainActivity` и сразу `finish()`. Это важно: штатный
`ChironSplashActivity` уничтожает и пересоздаёт `MainActivity` (1.5–3 с), из-за чего
шторка открывается пустой.

## Компоненты

| файл | роль |
|---|---|
| `centaur_fix/CentaurSwipeWatcher.java`, `centaur_fix/centaur_watcher.dex` | root-watcher: ловит свайп, поднимает/резюмирует Centaur, открывает шторку; boot-setup: `/dev/rtc0` → 666, яркость, HOME, память, Pipka-mount, `sber_guard` |
| `bootstarter/` | `RavnBootStarter`: `BOOT_COMPLETED` → foreground service → локальный adbd → `adb root` → запуск watcher; `GuardThread` держит `sber_guard.sh` |
| `homeproxy/` | `RavnHomeProxy`: HOME без splash; ждёт доступный `/dev/rtc0` перед стартом Centaur |
| `scripts/patch_centaur_top_sheet.sh` | патч APK: `onNewIntent` + кнопки шторки |
| `scripts/patch_sber_pipka.sh` | патч vendor APK: Pipka не рисуется поверх Centaur/homeproxy |
| `scripts/install_top_sheet.sh` | установка всего |

## Патч APK Centaur

`MainActivity.onNewIntent`: если пришёл `open_top_sheet` (или wi-fi/настройки), найти
`topSheetFragment` (id `0x7f0b04fe`), подняться по `getParent()` до
`CentaurDrawerLayout` и вызвать **`q(0x30)`** — open. `c(0x30)` — close.

Кнопки шторки: в `fragment_top_sheet.xml` две панели с одинаковыми id (скрытая
`TopSheetAdvancedButtons` и видимая `buttons`), а генератор binding-а `hz.u` брал
первые совпадения — кнопки скрытой панели. В конструкторе `hz.u` поля
`c/e/i/j/m` перепривязываются к дочерним view видимой панели:

| кнопка | id |
|---|---|
| home | `0x7f0b0250` |
| settings | `0x7f0b043e` |
| auto brightness | `0x7f0b0085` |
| brightness | `0x7f0b00ae` |
| volume | `0x7f0b0543` |

Используется `Landroid/view/View;->findViewById` (не `LinearLayout.findViewById`):
в `classes4.dex` ровно 65536 методов, и новый method reference ломает smali-сборку
(`Unsigned short value out of range: 65536`).

## Pipka

`PipkaViewContainer` (160×8 dp, по центру сверху) — белая «таблетка» Sber поверх
приложений. `GestureNavigationImpl` показывает её всем, кроме allowlist
(`ru.sberdevices.starlauncher`, `ru.sberdevices.app.setup`).

Патч `u90/e.smali` добавляет в allowlist `ru.yandex.quasar.centaur_app` и
`com.ravn.homeproxy`. APK системный, поэтому не устанавливается, а bind-mount'ится
поверх `/vendor/priv-app/StarDroidStarServices/StarDroidStarServices.apk`
(watcher, `ensurePipkaPatch`), после чего сервис один раз перезапускается.

## Гонка при загрузке: `/dev/rtc0`

Система запускает HOME (`com.ravn.homeproxy`) раньше, чем watcher успевает
сделать `/dev/rtc0` доступным: до этого он `0640 system:system`, а watcher
выставляет `0666`. Centaur в это время падает в нативном старте:

```
java.lang.Error: (quasar::ErrnoException) cannot open device '/dev/rtc0': Permission denied (13)
    at ru.yandex.io.sdk.jni.QuasarLauncher.doNativeStart(Native Method)
```

с диалогом «В приложении Centaur снова произошёл сбой» на экране.

Поэтому `HomeActivity` не ждёт сама, а сразу запускает `WaitService` и
завершается. Сервис в фоновом потоке ждёт, пока `/dev/rtc0` станет
записываемым (`File.canWrite()`, шаг 400 мс, максимум 30 с), и только потом
отправляет `MainActivity`. Ждать в самой activity нельзя: у неё
`Theme.NoDisplay`, и Android требует `finish()` до конца `onResume`
(иначе `IllegalStateException`). После исправления холодная загрузка
проходит без падений.

Если менялся `homeproxy/src/.../HomeActivity.java` — пересобрать APK:

```bash
./scripts/build_homeproxy.sh
adb -s <IP>:5555 install -r -g homeproxy/RavnHomeProxy.apk
adb -s <IP>:5555 shell cmd package set-home-activity com.ravn.homeproxy/.HomeActivity
```

## Установка

```bash
D=<IP>:5555 ./scripts/install_top_sheet.sh centaur_voice_patched.apk
```

Скрипт: `WRITE_SETTINGS` для Centaur → watcher.dex и `ns_mount` в `/data/local/tmp`
→ `sber_guard.sh` → сборка патча Pipka (если нет) и push → установка
`RavnBootStarter.apk` и `RavnHomeProxy.apk`, home = homeproxy → очистка ART-кэша
и запуск watcher.

Требования: `apktool`, `aapt2`, `apksigner`, debug-keystore (`~/.android/debug.keystore`).

## Проверка

```bash
D=<IP>:5555
adb -s $D shell 'ps -A | grep app_process'            # watcher жив
adb -s $D shell 'cat /data/local/tmp/centaur_watcher.log'
adb -s $D shell 'input swipe 640 1 640 500 400'
adb -s $D exec-out screencap -p > top.png             # должен быть шит

# геометрия шторки
adb -s $D shell 'dumpsys activity top | grep app:id/topSheetFragment'
#   открыт: 0,0-1280,617    закрыт: 0,-617-1280,0

# кнопки
adb -s $D shell 'input tap 1122 110'   # settings
adb -s $D shell 'input tap 110 110'    # home

# яркость
adb -s $D shell 'settings get system screen_brightness'
adb -s $D shell 'input swipe 640 110 350 110 500'
adb -s $D shell 'settings get system screen_brightness; cat /sys/class/backlight/aml-bl/brightness'
```

Ожидаемо: `screen_brightness` и `/sys/class/backlight/aml-bl/brightness` меняются
синхронно (например 202 → 60), в logcat `BrightnessManager: setBrightnessImpl <n>`.

## Особенности

- Шторка сама закрывается через 30 с (`TopSheetAutoCloseController`, `0x7530`);
  кнопки надо нажимать до этого.
- После загрузки watcherотправляет `open_top_sheet`; шит надёжно открыт к ~6–7-й секунде.
- `centaur_watcher.dex` обновился → удалить `/data/local/tmp/oat`.
- Home chooser может появиться, если `set-home-activity` не сохранил «always»;
  watcher сам жмёт BACK.
- Яркость: у переподписанного Centaur нет `WRITE_SETTINGS` — установщик выдаёт appop.
- Автономный вариант с патчем `services.odex`/`system_server` существует, но не нужен
  для работы шторки (watcher справляется сам) и по умолчанию выключен.
