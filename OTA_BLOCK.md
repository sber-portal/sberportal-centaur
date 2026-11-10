# Блокировка OTA/обновлений прошивки SberPortal

Цель: не дать штатному StarOS-обновлятору Сбера скачать и применить обновление
прошивки/StarOS. На устройстве стоят пропатченные `services.odex`/`services.vdex`,
Pipka и Centaur; OTA может заменить system/vendor и сломать это состояние.

Блокировка **не** трогает сеть, ассистента, жесты и споттер Сбера: обновлятор
отключается точечно.

## Что именно блокируется

Обновления в StarOS обслуживает `ru.sberdevices.services:stardroid_updater`.
Он ходит в `https://staros-api-md.devices.sberbank.ru`, получает оттуда
подписанный update-скрипт, кладёт его в `/data/updateScript.sh` и выполняет.
Штатный `update.sh` вызывает `/system/bin/update_engine_client`, который
применяет payload через демон `update_engine` и делает `reboot ota`.

`ota_guard.sh` закрывает три независимых места:

1. **Конфиг обновлятора** — `/data/data/ru.sberdevices.services/files/staros/localOverrideStar.json`.
   Это штатный local override StarOS (`common.localOverridableConfig` в
   `assets/updater.json`, схема — `assets/localRulesStar.json`).
   Выставляется:
   - `nightUpdatesEnabled: false`
   - `skipAndUpdateOnBoot.enabled: false`
   - `skipAndUpdateOnSuw.enabled: false`
   - `installNonCriticalUpdateOnFirstSetup: false`
   - `handleUpdateOnDeviceWakeUp: false`
   - `showInstallNotification: false`

   Файл принадлежит `system:system`, режим `600`, стоит `chattr +i`.
   Override проверен по логу самого updater-процесса:
   `[updater_config] Merged config:` содержит `"nightUpdatesEnabled":false`.

2. **Хранилище update-скрипта** — `/data/updateScript.sh`
   (`services.update.updateScriptStorePath` из `assets/updater.json`).
   Файл создаётся пустым, `root:root`, режим `000`, `chattr +i`.
   Обновлятор работает под uid 1000 (`system`) и не может ни записать,
   ни удалить, ни снять immutable-флаг. Без скрипта обновление не запускается.

3. **Демон application** — `update_engine` останавливается
   (`setprop ctl.stop update_engine`). Даже если payload/скрипт появится
   другим путём, применять его нечем: `update_engine_client` не подключится
   к остановленному сервису.

## Файлы

| файл | где | назначение |
|---|---|---|
| `ota_guard.sh` | репозиторий + `/data/local/tmp/ota_guard.sh` | device-side блокировка, идемпотентная |
| `ota_block_setup.sh` | репозиторий (Mac) | установка/статус/откат с хоста |
| `sber_guard.sh` | `/data/local/tmp/sber_guard.sh` | при старте вызывает `ota_guard.sh` |
| `scripts/install_top_sheet.sh` | Mac | при установке пушит `ota_guard.sh` и применяет блок |
| host-watchdog (`centaur_autosetup.sh` в рабочем наборе `sberportal3`) | Mac | синхронизирует `ota_guard.sh` и добивает блок, если `update_engine` поднялся |

## Установка

```sh
cd $HOME/Dev/sberportal
./ota_block_setup.sh
```

Скрипт:
- находит stargate по `adb devices` (или `SBERPORTAL_ADB=host:port`);
- делает `adb root`;
- кладёт `ota_guard.sh` в `/data/local/tmp`;
- применяет блок и один раз перезапускает `ru.sberdevices.services`, чтобы
  override подхватился сразу;
- печатает статус.

Применение без перезапуска сервиса:

```sh
OTA_GUARD_RESTART=0 ./ota_block_setup.sh
```

`scripts/install_top_sheet.sh` при установке уже пушит `ota_guard.sh` и
применяет блок. Если используется host-watchdog из рабочего набора
`sberportal3`, `./centaur_autosetup.sh` синхронизирует `ota_guard.sh` и
добивает блок после ребута.

## Статус

```sh
./ota_block_setup.sh status
```

Ожидаемый вывод:

```text
override: /data/data/ru.sberdevices.services/files/staros/localOverrideStar.json
  nightUpdatesEnabled: false
-----i------- /data/data/.../localOverrideStar.json
  -rw------- system:system 346 bytes
update script: /data/updateScript.sh
-----i------- /data/updateScript.sh
  ---------- root:root 0 bytes
update_engine: stopped
update_engine pid:
updater process: 2315
pending payloads: none
```

Ручные проверки:

```sh
adb shell 'getprop init.svc.update_engine'          # stopped
adb shell 'lsattr /data/updateScript.sh'            # -----i-------
adb shell 'cat /data/data/ru.sberdevices.services/files/staros/localOverrideStar.json'
adb shell 'echo x > /data/updateScript.sh'          # Operation not permitted

# эффективный конфиг самого updater-процесса:
adb shell 'grep -A1 "\[updater_config\] Merged config:" \
  /data/data/ru.sberdevices.services/files/staros/service_logs/updater.log |
  tail -1 | grep -o "\"nightUpdatesEnabled\":[a-z]*"'
# "nightUpdatesEnabled":false
```

## Как переживает ребут

- `RavnBootStarter` поднимает `CentaurSwipeWatcher`;
- watcher запускает `sber_guard.sh`;
- `sber_guard.sh` при старте вызывает `ota_guard.sh`;
- в рабочем наборе `sberportal3` тот же вызов есть в `centaur_device_setup.sh`.

`localOverrideStar.json` и `/data/updateScript.sh` лежат на `/data`, поэтому
immutable-флаги сохраняются между ребутами. `update_engine` после ребута
стартует, но `ota_guard.sh` снова его останавливает.

## Откат

```sh
./ota_block_setup.sh unblock
```

Или вручную:

```sh
adb shell 'chattr -i /data/data/ru.sberdevices.services/files/staros/localOverrideStar.json; \
  rm -f /data/data/ru.sberdevices.services/files/staros/localOverrideStar.json; \
  chattr -i /data/updateScript.sh; rm -f /data/updateScript.sh; \
  setprop ctl.start update_engine'
adb shell 'kill -9 $(pidof ru.sberdevices.services)'   # перечитать конфиг
```

Если при установке уже был чужой `localOverrideStar.json`, он сохранён в
`/data/data/ru.sberdevices.services/files/staros/localOverrideStar.json.ota-guard.bak`
и восстанавливается командой `unblock`.

## Ограничения

- Путь `/data/updateScript.sh` и набор override-ключей взяты из
  `assets/updater.json` / `assets/localRulesStar.json` версии StarOS 1.102.34.
  Если Sber поменяет путь или вынесет обновлятор из `ru.sberdevices.services`,
  `ota_guard.sh` нужно обновить.
- Между стартом `update_engine` на ребуте и запуском `ota_guard.sh` есть
  короткое окно. Оно не страшно: без update-скрипта и с остановленным
  демоном применять нечего; уже скачанных payload'ов сейчас нет.
- Скрипт не удаляет старые payload'ы из `/cache`. Если там когда-то окажется
  `*.bin`, удалите вручную и проверьте `/data/ota_package` и `/data/ota`.
- Это блокирует обновления через StarOS-обновлятор (прошивка и StarOS APK).
  Умный дом, музыка, ассистент и прочие облачные функции Сбера работают.
- `SBER_GUARD.md` — отдельный механизм (тихий споттер); они не конфликтуют.
