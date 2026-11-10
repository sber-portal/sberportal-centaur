# SberPortal — Centaur (Дуо Макс): голос, top sheet, подавление Sber

Патчи и on-device обвязка, которые превращают **SberPortal** (`stargate`, Amlogic A311D,
Android 9, StarOS 1.102.34) в колонку с **Алисой Яндекса**: wake word «Алиса»,
диалог через uniproxy, музыка и ответы в **Centaur**, шторка по свайпу сверху,
ассистент Sber молчит.

Требуется постоянный root (`adb root` → `uid=0`) — см.
**[sberportal-root](https://github.com/sber-portal/sberportal-root)**.
Пошаговая установка с нуля — **[sberportal](https://github.com/sber-portal/sberportal)**.

## Версия Centaur

Используется **4.16.1** (`2000008757.212.71.202401070835`, `armeabi-v7a`,
сборка 07.01.2024) — последняя 32-битная версия, которая запускается на портале.

Новая **3.368.55** (Duo Max, Android 11) не подходит: только `arm64-v8a`,
versionCode 1795 (ниже), другая архитектура приложения (набор модулей) и другие
смещения нативных библиотек.

## Что внутри

| путь | что |
|---|---|
| `patch/` | точные smali-правки APK: аудио-путь (RAW_MIC), `Native.ensure()`, `TextReceiver`, `extractNativeLibs` |
| `spotterfix/` | `libspotterfix.so` + исходник: включает споттеры Centaur — «Алиса» и команды «стоп/хватит/пауза/громче» |
| `scripts/patch_centaur_command_spotter.sh` | включает command spotter в APK: `enableCommandSpotters=true`, кладёт `libspotterfix.so` |
| `scripts/patch_centaur_top_sheet.sh` | патч Centaur: `onNewIntent` → открыть `CentaurDrawerLayout` (`q(0x30)`), кнопки шторки |
| `scripts/patch_centaur_volume.sh` | громкость 0..10 + защита тоста от `BadTokenException` |
| `scripts/patch_centaur_night_mode.sh` | ночной режим: дефолтный конфиг яркости и датчик света |
| `scripts/patch_centaur_crashfix.sh` | фикс SIGABRT после голосового ответа (TTS) |
| `scripts/patch_sber_pipka.sh` | патч `ru.sberdevices.services`: Pipka не рисуется поверх Centaur |
| `centaur_fix/` | `CentaurSwipeWatcher` (root, `app_process`): свайп → шторка, boot-setup, Pipka-mount, запуск guard |
| `bootstarter/` | `RavnBootStarter`: автозапуск watcher и guard после загрузки через localhost adbd |
| `homeproxy/` | `RavnHomeProxy`: невидимый HOME, резюмирует `MainActivity` вместо `ChironSplashActivity` |
| `sber_guard.sh`, `sber_silent_config.cfg` | подавление споттера Sber через пороги классов |
| `ota_guard.sh`, `ota_block_setup.sh` | блокировка OTA/обновлений прошивки: local override, immutable update-скрипт, остановленный `update_engine` |
| `scripts/install_top_sheet.sh` | установка всей связки на устройство |
| `scripts/build_*.sh` | пересборка dex/APK из исходников |
| `scripts/find_portal.sh` | поиск портала в подсети (IP по DHCP) |

Подробно: [TOP_SHEET.md](TOP_SHEET.md), [VOICE.md](VOICE.md),
[COMMAND_SPOTTER.md](COMMAND_SPOTTER.md), [SBER_GUARD.md](SBER_GUARD.md),
[OTA_BLOCK.md](OTA_BLOCK.md),
[patch/README.md](patch/README.md).

## Установка

```bash
# 0) root уже работает (см. sberportal-root)
adb root && adb shell id          # uid=0

# 1) APK Centaur с голосом и шторкой — из релиза репозитория sberportal:
#    centaur-voice-patched.apk  (или собрать самому, см. patch/README.md)

# 2) патчи под свою версию APK (если собираете сами)
./scripts/patch_centaur_top_sheet.sh original.apk
./scripts/patch_centaur_volume.sh patched.apk
./scripts/patch_centaur_night_mode.sh patched.apk
./scripts/patch_centaur_crashfix.sh patched.apk
./scripts/patch_centaur_command_spotter.sh patched.apk command-spotter.apk

# 3) установка обвязки + патченного APK
D=<IP>:5555 ./scripts/install_top_sheet.sh command-spotter.apk
```

`install_top_sheet.sh` делает всё остальное: `WRITE_SETTINGS` для яркости, watcher,
bootstarter, homeproxy (HOME), патч Pipka, запуск и проверку.

## Как это работает

```
микрофон
  └─ Centaur (AudioRecord 16 кГц, моно) → SDK AudioSource (RAW_MIC)
       ├─ ActivationSpotterCapability → модель activation/alisa → «Алиса»
       └─ Vins.VoiceInput → uniproxy Яндекса → музыка/ответы в Centaur

свайп сверху
  → WindowManager (system logcat, SWIPE_GESTURE_TYPE: 2)
     → CentaurSwipeWatcher (root)  → am start MainActivity --ez open_top_sheet true
        → MainActivity.onNewIntent (патч) → CentaurDrawerLayout.q(0x30)
```

- **Голос.** В этой сборке Java-слой SDK отдавал в натив пустой список каналов
  (`yw.e.b`), поэтому в Яндекс уходила тишина. Патч подставляет `RAW_MIC` — см.
  [patch/README.md](patch/README.md) и [VOICE.md](VOICE.md).
- **Споттер.** Родной activation-споттер Centaur включается `libspotterfix.so`
  (`setModelPaths`), модель «Алиса» — из прошивки Дуо Макс.
- **Команды.** Тот же `libspotterfix.so` задаёт путь командной модели
  (`spotter_models/command`) и возвращает `CommandSpotterCapability` после
  диалога «Алисы». В APK-ассете `quasar.cfg` включён
  `enableCommandSpotters`; без него фраза распознаётся, но отбрасывается.
- **Шторка.** `ru.sberdevices.services` забирает `ACTION_SWIPE_GESTURE` и уводит HOME;
  receiver Centaur этот broadcast не получает (signature-permission). Поэтому
  watcher читает system-буфер logcat и открывает шторку сам.
- **HOME.** `RavnHomeProxy` резюмирует уже существующую `MainActivity`; штатный
  `ChironSplashActivity` пересоздаёт её и теряет кэш шторки.
- **Pipka.** Белая «таблетка» Sber рисуется поверх всех приложений, кроме allowlist;
  патч vendor APK добавляет в allowlist Centaur и homeproxy (bind-mount).
- **Sber молчит.** Пороги классов споттера Sber подняты до `100000`; модель и сервис
  не трогаются. Подробно — [SBER_GUARD.md](SBER_GUARD.md).

## Требования и ограничения

- Нужен постоянный root; почти все шаги выполняются под `uid=0`.
- После обновления Centaur (переустановки APK) патчи нужно применять заново —
  автообновления на устройстве нет.
- После обновления `centaur_watcher.dex` удалять `/data/local/tmp/oat`
  (иначе `Dex checksum does not match`).
- `device_id` для регистрации в Яндексе задаётся файлом
  `/sdcard/Download/centaur_device_id` (см. [VOICE.md](VOICE.md)); в репозитории
  он не хранится.
- Ничего из Sber-платформы не удаляется «в лоб»: `ru.sberdevices.services` отключать
  нельзя (bootloop).
