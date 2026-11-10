#!/bin/bash
# Install the root top-sheet solution on SberPortal (stargate).
#
# Requires: persistent root (adb root works), the Centaur top-sheet-patched APK
# already installed (or pass it as $1), and the files from this repo.
#
# Usage:
#   ./install_top_sheet.sh [centaur_top_sheet_signed.apk]
#
# What it does:
#   * pushes centaur_fix/centaur_watcher.dex to /data/local/tmp
#   * installs bootstarter/RavnBootStarter.apk (BOOT_COMPLETED -> root watcher)
#   * installs homeproxy/RavnHomeProxy.apk and makes it the HOME activity
#     (avoids ChironSplashActivity recreating MainActivity on every swipe)
#   * bind-mounts the patched Sber service APK (hides Pipka over Centaur)
#   * optionally installs the patched Centaur APK
#   * starts the watcher now and verifies it is running
set -e

HERE=$(cd "$(dirname "$0")/.." && pwd)
D=${D:?укажи адрес портала: D=192.168.1.x:5555}
CENTAUR=${1:-}

adb connect "$D" >/dev/null 2>&1 || true
adb -s "$D" root >/dev/null 2>&1 || true
sleep 3

[ "$(adb -s "$D" shell id -u | tr -d '\r')" = "0" ] || {
  echo "adbd is not root; restore persistent root first (u-boot env)"; exit 1; }

if [ -n "$CENTAUR" ]; then
  adb -s "$D" install -r -g "$CENTAUR"
fi

# Переподписанный Centaur не системный: без WRITE_SETTINGS не работает
# яркость/авто-яркость (Settings.System.putInt -> SecurityException).
adb -s "$D" shell 'cmd appops set ru.yandex.quasar.centaur_app WRITE_SETTINGS allow' || true

adb -s "$D" push "$HERE/centaur_fix/centaur_watcher.dex" /data/local/tmp/centaur_watcher.dex
adb -s "$D" push "$HERE/centaur_fix/ns_mount" /data/local/tmp/centaur_ns_mount
adb -s "$D" shell 'chmod 755 /data/local/tmp/centaur_ns_mount'
adb -s "$D" push "$HERE/sber_guard.sh" /data/local/tmp/sber_guard.sh
adb -s "$D" shell 'chmod 755 /data/local/tmp/sber_guard.sh'
adb -s "$D" push "$HERE/ota_guard.sh" /data/local/tmp/ota_guard.sh
adb -s "$D" shell 'chmod 755 /data/local/tmp/ota_guard.sh'

# The patched vendor APK is generated from the device's StarDroidStarServices
# (not committed as a binary). Build it once if it is missing.
PIPKA="$HERE/centaur_fix/StarDroidStarServices_pipka_patched.apk"
if [ ! -f "$PIPKA" ]; then
  echo "building Sber Pipka patch (needs apktool, aapt2, debug key)..."
  D="$D" "$HERE/scripts/patch_sber_pipka.sh"
fi
adb -s "$D" push "$PIPKA" /data/local/tmp/StarDroidStarServices_patched.apk

adb -s "$D" install -r -g "$HERE/bootstarter/RavnBootStarter.apk"
adb -s "$D" install -r -g "$HERE/homeproxy/RavnHomeProxy.apk"
adb -s "$D" shell 'cmd package set-home-activity com.ravn.homeproxy/.HomeActivity'

# Remove any stale ART cache for the watcher dex and (re)start it now.
adb -s "$D" shell 'killall app_process 2>/dev/null; rm -rf /data/local/tmp/oat; \
  rm -f /data/local/tmp/centaur_watcher.lock /data/local/tmp/centaur_watcher.log; \
  nohup env CLASSPATH=/data/local/tmp/centaur_watcher.dex \
  app_process /system/bin CentaurSwipeWatcher >/dev/null 2>&1 </dev/null &'
sleep 5

# Apply the OTA/firmware block now (sber_guard.sh also calls it on every start).
adb -s "$D" shell 'OTA_GUARD_RESTART=1 sh /data/local/tmp/ota_guard.sh'

adb -s "$D" shell 'chmod 666 /dev/rtc0 2>/dev/null; \
  ps -A | grep app_process | head; \
  echo ---; cat /data/local/tmp/centaur_watcher.log 2>/dev/null'
echo "Done. Swipe down from the top edge to open Centaur's top sheet."
