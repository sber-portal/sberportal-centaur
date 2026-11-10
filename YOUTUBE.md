# YouTube в Centaur через StarTube

Кнопка YouTube в Centaur открывает **StarTube** (`ru.sberdevices.startube`), а не
встроенный WebView Centaur. На этом портале StarTube работает через собственный
туннель, без NetFix, DoH и правок DNS.

## Почему это вообще нужно

StarTube умеет обходить блокировки сам: `stunnel` на `127.0.0.1:11085`
поднимает TLS/PSK-туннель к `star.edgehaul.xyz:4433`, а удалённая сторона сама
резолвит YouTube. Проблема в том, что приложение запускает свой stunnel и
**сразу его убивает** (гонка в `ProxyUpdater`: `Stunnel started` ->
`Terminated`), после чего прокси отвечает `ECONNREFUSED`, и YouTube не грузится.

Дополнительно на этом провайдере `youtube.com` отдаёт NXDOMAIN (DNS
фильтруется), поэтому NetFix, DoH и обычная смена DNS не помогают.

Решение: держать такой же stunnel запущенным отдельно, из конфига и PSK самого
приложения. Тогда StarTube подключается через него и видео играет.

## Файлы

| файл | что |
|---|---|
| `scripts/stube_stunnel_start.sh` | поднимает stunnel на 11085 из PSK/таргета StarTube |
| `scripts/stube_stunnel_watchdog.sh` | держит туннель живым (проверка каждые 3 с) и один раз за загрузку сбрасывает зависший StarTube |
| `scripts/install_stube_stunnel.sh` | ставит оба скрипта на портал и цепляет watchdog к `sber_guard.sh` |
| `scripts/remap_youtube_button.sh` | оставляет StarTube единственным обработчиком ссылок YouTube |
| `sber_guard.sh` | в начале запускает watchdog (строка с `stube_stunnel_watchdog.sh`) |

## Как работает

1. `stube_stunnel_start.sh` берёт из данных StarTube (`APP_PREFS.xml`) PSK
   (`startube3:<hex>`), target и localPort, собирает `stunnel.conf` в
   `/data/local/tmp/stube/` и запускает бинарник `libstunnel.so` под именем
   `stube_tunnel`. Имя важно: приложение убивает процесс `libstunnel.so`, а
   чужое имя не трогает.
2. `stube_stunnel_watchdog.sh` каждые 3 с проверяет, что слушает 11085, и
   перезапускает туннель, если его нет. Pid-файл привязан к `boot_id`, чтобы
   после перезагрузки не принять чужой pid за свой.
3. После того как порт поднялся, watchdog **один раз за загрузку** делает
   `am force-stop ru.sberdevices.startube`. Иначе процесс, стартовавший при
   загрузке до готовности туннеля, остаётся в состоянии ошибки и игнорирует
   ссылки. После сброса кнопка YouTube запускает свежий процесс, и он сразу
   видит рабочий прокси.
4. `remap_youtube_button.sh` отключает обработчик ссылок Chromium
   (`org.chromium.chrome/...IntentDispatcher`), оставляя StarTube единственным
   обработчиком `https://m.youtube.com` — без диалога выбора приложения.

## Как открыть StarTube с портала

Кнопка YouTube внутри Centaur открывает **встроенный WebView** Centaur (действие
DIV `open_smart_device_external_app_frame`), а не ссылку — переназначить её
обработчиком ссылок нельзя, для этого нужен патч APK Centaur.

Кнопка таба открывает встроенный WebView Centaur. Патч APK перехватывает
загрузку URL в этом WebView: `p60.h.j(String url)` при URL, содержащем
`youtube.com`, запускает `ru.sberdevices.startube/.ui.StarTubeActivity` и не
загружает страницу (см. `scripts/patch_centaur_youtube_tab.sh`).

Двойной свайп сверху оставлен за NetFix.

## Установка

```sh
D=<IP>:5555 ./scripts/install_stube_stunnel.sh
D=<IP>:5555 ./scripts/remap_youtube_button.sh
```

Проверка:

```sh
adb shell 'pidof stube_tunnel'           # туннель
adb shell 'grep -c ":2B4D" /proc/net/tcp' # 11085 слушает
adb shell 'cmd package query-activities --brief -a android.intent.action.VIEW -d https://m.youtube.com'
```

## Мёртвые адреса сервиса

`star.edgehaul.xyz` multi-homed, часть адресов не отвечает, а порядок DNS
меняется. Если туннель перестал подключаться, можно закрепить рабочий адрес:

```sh
adb shell 'echo "203.0.113.10:4433" > /data/local/tmp/stube/target'
adb shell 'kill $(pidof stube_tunnel)'
```

Файл `target` имеет приоритет над адресом из конфига приложения.

## Ограничения

- PSK, target и порт берутся из данных StarTube. После обновления StarTube
  скрипт подхватит новые значения при следующем запуске; при смене схемы
  конфиг может потребовать правки.
- Если Centaur когда-нибудь начнёт открывать YouTube во встроенном WebView, а
  не ссылкой, переназначение обработчика перестанет влиять — тогда нужен патч
  Centaur.
- StarTube не входит в NetFix: ему это не нужно, туннель отдельный.

## Патч APK Centaur (таб YouTube)

```sh
./scripts/patch_centaur_youtube_tab.sh /path/to/centaur.apk
adb -s <IP>:5555 install -r centaur-youtube-tab-patched.apk
```

Скрипт декодирует APK, правит `smali_classes5/p60/h.smali` (метод `j`),
собирает, выравнивает и подписывает тем же debug-ключом, поэтому `adb install -r`
сохраняет данные приложения (device_id, private.pem, привязки).

Проверка после установки: нажать YouTube в табе Centaur — должен открыться
StarTube, а не WebView с `m.youtube.com`.

Откат: переустановить исходный `centaur-voice-patched-v2.apk` тем же способом.

## Откат

```sh
adb shell 'kill $(pidof stube_tunnel)'
adb shell 'rm -rf /data/local/tmp/stube /data/local/tmp/stube_stunnel_start.sh /data/local/tmp/stube_stunnel_watchdog.sh'
adb shell 'sed -i "/stube_stunnel_watchdog/d" /data/local/tmp/sber_guard.sh'
D=<IP>:5555 ./scripts/remap_youtube_button.sh --rollback
```
