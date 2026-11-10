# Command spotter: «стоп/хватит/пауза/громче» без «Алисы»

Проверено на SberPortal, Centaur 4.16.1
(`2000008757.212.71.202401070835`, `armeabi-v7a`).

## Итог

Команды работают без активационного слова, во время воспроизведения музыки:

| команда | лог | результат |
|---|---|---|
| «стоп» | `Command phrase spotted: стоп`, `phrase_passed: true` | `AudioClientEvent state: STOPPED` |
| «хватит» | `phrase_passed: true` | `state: STOPPED` |
| «пауза» | `phrase_passed: true` | плеер остановлен |
| «громче» | `phrase_passed: true` | `STREAM_MUSIC` +1 |
| «тише» | `phrase_passed: true` | `STREAM_MUSIC` −1 |

## Почему не работало

В Quasar два независимых споттера:

- `ActivationSpotterCapability` — «Алиса»;
- `CommandSpotterCapability` — «стоп/хватит/пауза/громче/тише/…».

На порте не работал второй, по двум причинам:

1. **Нет пути к модели.** `VoiceServiceState::createCommandSpotter` писал
   `Do not create command spotter. Spotter path is empty.` — штатный
   `SpotterConfigurer` в этой сборке не стартует.
2. **Command spotters выключены в конфиге.** В `assets/quasar/quasar.cfg`
   было `"enableCommandSpotters": false` (и
   `"ENABLE_COMMAND_SPOTTERS": false`). Фраза распознавалась, но
   отбрасывалась:

   ```json
   {"disabled_reason":"Command spotters disabled",
    "phrase_passed":false,
    "spotter_phrase":"стоп"}
   ```

Модель уже лежит в APK:
`assets/quasar/spotter_models/command` (`acoustic_model.nnet`, `flags.txt`,
`words.txt`). В `words.txt` есть `стоп` (15), `хватит` (16), `пауза` (17),
`громче` (33), `тише` (35).

## Что делает фикс

### 1. APK-ассет

`scripts/patch_centaur_command_spotter.sh in.apk out.apk`

- меняет в `assets/quasar/quasar.cfg`:
  `enableCommandSpotters=true`, `ENABLE_COMMAND_SPOTTERS=true`;
- кладёт `spotterfix/libspotterfix.so` в `lib/armeabi-v7a/`;
- zipalign + apksigner (debug key).

APK должен уже содержать голосовой патч (`Native.ensure()`,
`extractNativeLibs=true`) — см. [patch/README.md](patch/README.md).

Установка с сохранением данных:

```bash
adb install -r out.apk
```

### 2. `libspotterfix.so`

Исходник — `spotterfix/spotterfix.cpp`. Кроме activation-споттера
(«Алиса») библиотека теперь настраивает command-споттер:

- командный прокси в `YandexIOSDK` — **`+0xd0`**
  (activation — `+0xc8`); найден по совпадению vtable с activation-прокси
  и строке `remote_object_id = "CommandSpotterCapability"` (поле `+0x28`);
- путь задаётся тем же
  `SpotterCapabilityProxy::setModelPaths` (`libquasar_daemons.so + 0x32cb360`):
  `{"command": ".../files/system/spotter_models/command"}`;
- запуск — `SpotterCapabilityProxy::start` (`+0x32cb7c0`).

`VoiceServiceState` при старте диалога «Алисы» штатно делает
`stopCommandSpotter`. Библиотека раз в 2 с смотрит последние события
`commandSpotter started/stopped` в
`files/data/daemons_logs/android_app.log` и возвращает споттер только
после остановки. Читается хвост 4 МБ: лог очень шумный, 128 КБ не
всегда содержали последний `stop`.

Смещения (только для 4.16.1, `libquasar_daemons.so`):

| что | смещение |
|---|---|
| `YandexIO::getSDKSingleton()` | `0x312db64` |
| `SpotterCapabilityProxy::setModelPaths(map)` | `0x32cb360` |
| `SpotterCapabilityProxy::start()` | `0x32cb7c0` |
| `activationSpotterProxy_` в `YandexIOSDK` | `+0xc8` |
| `commandSpotterProxy_` в `YandexIOSDK` | `+0xd0` |

## Проверка

```bash
adb logcat | grep -E "SpotterFix|commandSpotter|Command phrase spotted"
adb shell 'grep -E "Command phrase spotted|phrase_passed" \
  /data/data/ru.yandex.quasar.centaur_app/files/data/daemons_logs/android_app.log | tail'
```

Ожидаемо:

```text
Command phrase spotted: стоп
... "disabled_reason":"","phrase_passed":true,"spotter_phrase":"стоп" ...
```

и следом `AudioClientEvent state: STOPPED` / изменение `STREAM_MUSIC`.

## Ограничения

- Проверять живым голосом или внешним динамиком: Centaur вычитает
  собственный динамик через AEC, TTS с портала не считается проверкой.
- Команды имеют смысл во время воспроизведения; в полной тишине часть
  из них не имеет контекста.
- Фикс привязан к APK 4.16.1. После обновления Centaur нужно перепроверить
  asset `quasar.cfg` и смещения `+0xd0`, `0x32cb360`, `0x32cb7c0`.
- `libspotterfix.so` держит поток проверки лога; после перезапуска
  приложения он загружается заново.
