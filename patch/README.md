# Патч APK Centaur: что именно менялось

Ниже — точный список правок, из которых состоит рабочий APK
(`centaur-voice-patched`, релиз в репозитории **sberportal**).

База: официальный `ru.yandex.quasar.centaur_app` 4.16.1 (armeabi-v7a),
`AndroidManifest.xml` + `classes7.dex` + нативная либа.

## 1. Аудио-путь: канал по умолчанию (главное)

`yw/e.smali`, метод `b(ByteBuffer, yw/f, int)`.

Было (список каналов пустой → в натив уходила тишина):

```smali
if-nez p3, :cond_2
sget-object p3, Lkotlin/collections/w;->b:Lkotlin/collections/w;
```

Стало:

```smali
if-nez p3, :make_default
goto :cond_2

:make_default
new-instance p3, Ljava/util/ArrayList;
invoke-direct {p3}, Ljava/util/ArrayList;-><init>()V
sget-object v0, Lvoicetech/ChannelTypes$AudioInputChannelType;->RAW_MIC:Lvoicetech/ChannelTypes$AudioInputChannelType;
invoke-interface {p3, v0}, Ljava/util/List;->add(Ljava/lang/Object;)Z
```

Готовый файл: `yw_e.audio.smali`.

## 2. Родной споттер: setModelPaths при старте

`ru/yandex/io/sdk/YandexIoService.smali`, метод `o(...)` — сразу после
`sput-object p3, Lru/yandex/io/sdk/BridgeHolder;->sdk`:

```smali
invoke-static {}, Lcom/anonym/bridge/Native;->ensure()V
```

`com/anonym/bridge/Native.smali` — `System.loadLibrary("spotterfix")`
(файл в `spotterfix/Native.smali`).

`libspotterfix.so` (исходник `spotterfix/spotterfix.cpp`) в `JNI_OnLoad`
ждёт `getSDKSingleton()`, берёт прокси активационного споттера (`sdk+0xc8`) и
вызывает `setModelPaths({"activation": ".../spotter_models/activation/alisa"})`
(`libquasar_daemons.so + 0x32cb360`). Заодно создаёт `flags.txt` из
`multiflags.txt`, если его нет.

## 3. Приёмник команд (необязателен, но удобен для отладки)

`com/anonym/bridge/TextReceiver` — слушает
`com.anonym.alicebridge.SEND_TEXT` (текстовый запрос в Яндекс) и
`com.anonym.alicebridge.START_VOICE` (открыть голосовой диалог).
Файл: `TextReceiver.smali`. В манифесте — `<receiver>` с этими action'ами.

## 4. Манифест

```xml
<application ... android:extractNativeLibs="true" ...>
```

Без этого `System.loadLibrary("spotterfix")` не находит библиотеку
(ищет только `/system/lib`).

## 5. Сборка

```bash
# 0) инструменты
#    apktool 3.x, zipalign, apksigner, NDK r26

# 1) libspotterfix.so
$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/armv7a-linux-androideabi30-clang++ \
  -shared -fPIC -O2 -std=c++17 -static-libstdc++ \
  -o libspotterfix.so spotterfix/spotterfix.cpp

# 2) достать classes7.dex и AndroidManifest.xml из стокового APK,
#    декодировать только dex:
#    (apktool d -r на мини-APK из AndroidManifest.xml + classes7.dex)

# 3) применить правки из patch/*.smali, собрать dex обратно

# 4) положить libspotterfix.so в lib/armeabi-v7a/, classes7.dex на место,
#    выставить extractNativeLibs=true, собрать APK:
apktool b /tmp/centaur_dec -o raw.apk
zipalign -p -f 4 raw.apk al.apk
apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android \
  --key-pass pass:android --ks-key-alias androiddebugkey --out signed.apk al.apk
adb install -r signed.apk
```

Подпись — debug (`CN=Android Debug`). Если ставите поверх другого APK с иной
подписью, Android потребует удалить приложение (данные потеряются).

## 6. Смещения (только для этой версии `libquasar_daemons.so`)

| что | смещение |
|---|---|
| `YandexIO::getSDKSingleton()` | `0x312db64` |
| `SpotterCapabilityProxy::setModelPaths(map)` | `0x32cb360` |
| `activationSpotterProxy_` в `YandexIOSDK` | `+0xc8` |

При обновлении Centaur смещения надо перепроверять.
