# Голос: «Алиса» в Centaur

## Тракт

```
микрофон (ALSA 6×48 кГц, HAL отдаёт моно)
  └─ Centaur: AudioRecord 16 кГц, моно
       └─ SDK AudioSource (RAW_MIC)
            ├─ ActivationSpotterCapability: model activation/alisa → «Алиса»
            └─ Vins.VoiceInput → wss://uniproxy.alice.yandex.net/uni.ws
                 └─ музыка / TTS / ответы → плеер и UI Centaur
```

Sber в контуре не участвует.

## Что было сломано

Java-поток читал микрофон нормально, но в натив уходили пустые буферы:
`AudioSource.doPushAudioBuffer(ByteBuffer, 0)`, `pushAudioData([])`,
`sent_chunk_count: 1`, `NoSpeechDetectedError`.

Причина — `yw.e.b()` собирает список трансформеров каналов из `yw.h.a`
(`ConcurrentHashMap`), который в этой сборке никогда не заполняется. Итог: пустой
`ArrayList` → в натив не уходит ни одного канала.

## Патч

`yw/e.smali`, метод `b(ByteBuffer, yw/f, int)`: если список каналов пуст,
подставляется `ChannelTypes$AudioInputChannelType.RAW_MIC`.

Точный код — [patch/README.md](patch/README.md), готовый файл — `patch/yw_e.audio.smali`.

## Споттер

Штатный `ActivationSpotterCapability` в этой сборке не получает путь к модели
(сервер не присылает `SpotterCapabilityMethod.ModelPath`), поэтому споттер не стартует:
`Do not create activation spotter. Spotter path is empty`, `configured=0`.

`libspotterfix.so` (`spotterfix/spotterfix.cpp`) в `JNI_OnLoad` ждёт
`YandexIO::getSDKSingleton()`, берёт прокси активационного споттера (`sdk + 0xc8`) и
вызывает `setModelPaths({"activation": ".../files/system/spotter_models/activation/alisa"})`.
Заодно создаёт `flags.txt` из `multiflags.txt`, если его нет (без `flags.txt`
`libdecode` молчит).

Вызов подключается из smali: `ru/yandex/io/sdk/YandexIoService` метод `o(...)` →
`com/anonym/bridge/Native.ensure()` → `System.loadLibrary("spotterfix")`.
В манифесте нужен `android:extractNativeLibs="true"`.

Смещения (только для 4.16.1, `libquasar_daemons.so`):

| что | смещение |
|---|---|
| `YandexIO::getSDKSingleton()` | `0x312db64` |
| `SpotterCapabilityProxy::setModelPaths(map)` | `0x32cb360` |
| `SpotterCapabilityProxy::start()` | `0x32cb7c0` |
| `activationSpotterProxy_` в `YandexIOSDK` | `+0xc8` |
| `commandSpotterProxy_` в `YandexIOSDK` | `+0xd0` |

### Command spotter: «стоп/хватит/пауза/громче» без «Алисы»

Тот же `libspotterfix.so` настраивает второй, командный споттер:

- `setModelPaths({"command": ".../files/system/spotter_models/command"})`
  на прокси `YandexIOSDK+0xd0`;
- `start()` через `SpotterCapabilityProxy::start` (`+0x32cb7c0`);
- после диалога «Алисы» SDK штатно вызывает `stopCommandSpotter` —
  библиотека возвращает споттер, когда в логе последнее событие
  `commandSpotter stopped`;
- в APK-ассете `quasar.cfg` обязательно
  `"enableCommandSpotters": true` (иначе фраза распознаётся, но
  отбрасывается с `disabled_reason: "Command spotters disabled"`).
  Патч ассета — `scripts/patch_centaur_command_spotter.sh`, подробности —
  [COMMAND_SPOTTER.md](COMMAND_SPOTTER.md).

## Модель «Алиса»

Берётся из прошивки **Дуо Макс**: `assets/quasar/spotter_models/activation/alisa`
в APK Centaur (`.nnet`, `.mat`, `words.txt`, threshold 0.13). Распаковывается
приложением сама; рабочий путь —
`/data/data/ru.yandex.quasar.centaur_app/files/system/spotter_models/activation/alisa/`.

Если модели в APK нет, её кладут вручную (`duomax-alisa-model.zip` из релиза
репозитория **sberportal**):

```bash
adb push duomax-alisa-model/. /data/local/tmp/alisa/
adb shell '
  M=/data/data/ru.yandex.quasar.centaur_app/files/system/spotter_models/activation/alisa
  OWNER=$(stat -c "%u:%g" /data/data/ru.yandex.quasar.centaur_app)
  am force-stop ru.yandex.quasar.centaur_app
  rm -rf $M && mkdir -p $M && cp /data/local/tmp/alisa/* $M/
  chown -R $OWNER $M; chmod 700 $M; chmod 600 $M/*
'
```

## Регистрация устройства

Centaur регистрируется в Яндексе под `device_id` из аккаунта; к нему привязан
`private.pem` в `/data/data/ru.yandex.quasar.centaur_app/files/system/`.
`DeviceIDProvider` читает `device_id` из `/sdcard/Download/centaur_device_id`
(fallback — `ro.serialno`). Файл нужно создать один раз:

```bash
adb shell 'printf "%s\n" <DEVICE_ID> > /sdcard/Download/centaur_device_id; chmod 644 /sdcard/Download/centaur_device_id'
```

После этого `registration_in_backend_is_completed=true`. В репозитории `device_id`
не хранится.

## Проверка

```bash
adb logcat | grep -E "AliceBridge|configured=|onPhraseSpotterStarted|New spotter config"
# ожидаем:
#   AliceBridge: spotterfix loaded
#   activation_spotter_capability.cpp:40 start, configured=1
#   New spotter config: [activation:...]
#   onPhraseSpotterStarted
```

Живой тест: сказать «Алиса», затем «включи группу Кино» → Centaur показывает
прослушивание, открывает плеер, играет трек; в логе `onStartVoiceInput` и `asrText`.

## Ограничения

- Centaur вычитает собственный динамик (AEC), поэтому команды, поданные с устройства,
  он «не слышит» — проверять только живым голосом.
- `YandexIOSDK` живёт, пока Centaur на переднем плане; уход в фон выгружает SDK.
- Голосовой ответ (TTS) в 4.16.1 вызывал `SIGABRT` в `VoiceService`:
  `CHECK(getValue().hasValue())` для поля `time`. Лечится
  `scripts/patch_centaur_crashfix.sh` (`libquasar_daemons.so + 0x24f9e90`,
  `push {r11,lr}` → `bx lr`).
- Громкость: логическая шкала 0..10 (max 10 = системные 16).
  Патч — `scripts/patch_centaur_volume.sh`.
- Яркость: нужен appop `WRITE_SETTINGS` (выдаёт `install_top_sheet.sh`).
- Ночной режим: патч `scripts/patch_centaur_night_mode.sh` (дефолты
  `brightness_settings` + регистрация датчика света).
