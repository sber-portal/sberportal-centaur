#!/bin/sh
# Make the YouTube button in Centaur open StarTube (ru.sberdevices.startube)
# instead of offering a chooser or another handler.
#
# Usage: D=<IP>:5555 ./scripts/remap_youtube_button.sh
#        D=<IP>:5555 ./scripts/remap_youtube_button.sh --rollback
#
# How it works: youtube.com links are an implicit ACTION_VIEW intent. Two
# packages handle it on the portal: StarTube and Chromium's IntentDispatcher.
# While both are enabled Android shows a chooser, so we disable just Chromium's
# link activity (the WebView library used by Centaur is untouched) and leave
# StarTube as the only handler.
#
# Limitation: this only remaps *link* intents. If Centaur opens its own
# internal WebView (Centaur has its own YouTube module), the button does not go
# through an intent and this script has no effect.
set -e

D=${D:?укажи адрес портала: D=192.168.1.x:5555}
MODE=${1:-apply}

adb connect "$D" >/dev/null 2>&1 || true
adb -s "$D" wait-for-device

CHROME=org.chromium.chrome/com.google.android.apps.chrome.IntentDispatcher

if [ "$MODE" = "--rollback" ]; then
    adb -s "$D" shell "pm enable $CHROME" >/dev/null 2>&1 || true
    echo "Chromium link handler restored"
    exit 0
fi

echo "[1/2] StarTube enabled"
adb -s "$D" shell 'pm enable ru.sberdevices.startube' >/dev/null 2>&1 || true

echo "[2/2] Chromium link handler disabled"
adb -s "$D" shell "pm disable $CHROME" >/dev/null 2>&1 || true

echo "handlers for https://m.youtube.com:"
adb -s "$D" shell 'cmd package query-activities --brief -a android.intent.action.VIEW -d https://m.youtube.com' 2>/dev/null | sed -n 's/^ *\([a-z0-9_.]*\/[A-Za-z0-9_.$]*\)$/  \1/p'
