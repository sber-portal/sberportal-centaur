# Ассистент Sber молчит

Штатный споттер Сбера не должен просыпаться на «Салют»/«Сбер»/«Афина»/«Джой».
`ru.sberdevices.services` при этом остаётся живым: жесты, аудиофокус, кнопки и
StarOS UI не трогаются.

## Как это сделано

У Сбера и Centaur два независимых always-on споттера на одном микрофоне. Модель
Sber не заменяется — поднимаются **пороги классов** в конфиге споттера:

```
[class1]
high_threshold = 100000
threshold = 100000
sub_threshold = 100000
hotword = salut
```

Движок штатно грузит модель и считает скоры, но никогда не отдаёт активацию.
Модель, `model_version`, `num_classes` и интерпретатор остаются стоковыми.

`chattr +i` на конфиге не даёт сервису вернуть стоковые пороги. Если сервис всё же
перезаписал конфиг (сброс данных, OTA), on-device guard правит пороги **in place** и
один раз перезапускает сервис: споттер читает конфиг только при старте.

## Где живёт guard

`sber_guard.sh` — на устройстве, под root, в `/data/local/tmp`:

* запускается `RavnBootStarter` (`GuardThread`, uid 10024 — переживает cleanup StarOS)
  и `CentaurSwipeWatcher` (если BootStarter ещё не успел);
* в режиме `config` (по умолчанию) каждые 2 с сканирует `config_*` с
  `hotword = salut|sber|afina|joy`, правит не-`100000` пороги `sed` in place,
  ставит `chattr +i`;
* если конфиг пришлось менять — один раз перезапускает сервис;
* если конфиг уже тихий — ничего не делает и никого не убивает.

`install_top_sheet.sh` кладёт `sber_guard.sh` в `/data/local/tmp` вместе с watcher.
`sber_silent_config.cfg` — снимок ожидаемого результата для сверки; guard его не
использует.

## Проверка

```bash
adb shell 'cat /data/local/tmp/sber_guard.pid; ps -A | grep sber_guard'
adb shell 'tail -20 /data/local/tmp/sber_guard.log'
adb shell 'grep -E "^\[class|^threshold|^high_threshold|^sub_threshold" \
  /data/data/ru.sberdevices.services/files/staros/config_*'
```

Ожидаемо: все пороги `100000`; после «Салют» в
`/data/data/ru.sberdevices.services/files/staros/service_logs/spotter.log` нет
`Spotter activation`.

Управление:

```sh
# остановить (BootStarter поднимет снова)
adb shell 'kill -9 $(cat /data/local/tmp/sber_guard.pid)'
# режим «убивать по активации» (если пороги перестанут учитываться)
adb shell 'MODE=kill sh /data/local/tmp/sber_guard.sh'
```

## Откат

```bash
adb shell 'kill -9 $(cat /data/local/tmp/sber_guard.pid); rm -f /data/local/tmp/sber_guard.pid'
# вернуть пороги: снять chattr +i и восстановить стоковый конфиг
CFG=/data/data/ru.sberdevices.services/files/staros/config_<hash>
adb shell "chattr -i $CFG; cp /data/local/tmp/staros_config_orig.cfg $CFG; kill -9 \$(pidof ru.sberdevices.services)"
```

Стоковый конфиг, если бэкапа нет:
`https://cdn-speech.sberdevices.ru/spotter_release/names.stargate.1.13.1/main_and_active.cfg`.

## Ограничения

- Пороги привязаны к формату конфига `names.stargate` (`salut/sber/afina/joy`).
  Смена имён/формата в StarOS требует правки guard.
- После сброса данных сервиса или OTA возможен короткий интервал до восстановления
  конфига (guard проверяет раз в 2 с, затем один раз перезапускает сервис).
- `config_*` с другими хот-вордами не трогаются.
- Если перезапускать zygote с активным Pipka bind-mount, PackageManager может
  выкинуть `ru.sberdevices.services` вместе с привязкой Sber ID; Yandex-аккаунт
  Centaur при этом остаётся.

## OTA/обновления прошивки

Этот guard не блокирует OTA. Обновления прошивки/StarOS отключены отдельно:
`OTA_BLOCK.md`, `ota_guard.sh` и `ota_block_setup.sh`. Кратко: local override
`localOverrideStar.json` выключает ночные проверки/скипы, immutable
`/data/updateScript.sh` не даёт сохранить подписанный update-скрипт, а
`update_engine` остановлен. `scripts/install_top_sheet.sh` применяет блок при
установке; `sber_guard.sh` вызывает его после каждого ребута.
