#!/bin/zsh
# Host-side installer for the SberPortal OTA/firmware block.
#
# Pushes ota_guard.sh to /data/local/tmp and applies it.  The device-side
# script is idempotent and is also called after every boot by sber_guard.sh
# and centaur_device_setup.sh.
#
# Usage:
#   ./ota_block_setup.sh           install / refresh the block
#   ./ota_block_setup.sh status    show current state
#   ./ota_block_setup.sh unblock   remove the block
#
# Env:
#   SBERPORTAL_ADB=host:port   force a device (default: auto-detect stargate)
#   OTA_GUARD_RESTART=0        do not restart ru.sberdevices.services after
#                              installing the override (default 1)

export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
set -u

HERE=${0:A:h}
ACTION=${1:-install}

if [ -n "${SBERPORTAL_ADB:-}" ]; then
    D=$SBERPORTAL_ADB
else
    D=$(adb devices | awk '/product:stargate/ {print $1; exit}')
fi
if [ -z "$D" ]; then
    for cand in 192.168.1.50:5555 192.168.2.50:5555; do
        adb connect "$cand" >/dev/null 2>&1
        if [ "$(adb -s "$cand" get-state 2>/dev/null)" = "device" ]; then
            D=$cand
            break
        fi
    done
fi
if [ -z "$D" ]; then
    echo "SberPortal not found. Set SBERPORTAL_ADB=host:port." >&2
    exit 1
fi

adb connect "$D" >/dev/null 2>&1
[ "$(adb -s "$D" get-state 2>/dev/null)" = "device" ] || {
    echo "device $D is not available" >&2
    exit 1
}

adb -s "$D" root >/dev/null 2>&1 || true
sleep 2
adb connect "$D" >/dev/null 2>&1

ID=$(adb -s "$D" shell id 2>/dev/null | tr -d '\r')
case "$ID" in
    *uid=0*) ;;
    *) echo "warning: adb shell is not root ($ID); ota_guard.sh needs root" >&2 ;;
esac

adb -s "$D" push "$HERE/ota_guard.sh" /data/local/tmp/ota_guard.sh >/dev/null || exit 1
adb -s "$D" shell chmod 755 /data/local/tmp/ota_guard.sh >/dev/null

case "$ACTION" in
    status)
        adb -s "$D" shell "sh /data/local/tmp/ota_guard.sh status"
        exit 0
        ;;
    unblock)
        adb -s "$D" shell "sh /data/local/tmp/ota_guard.sh unblock"
        exit 0
        ;;
    install|"")
        RESTART=${OTA_GUARD_RESTART:-1}
        echo "installing OTA block on $D (restart=$RESTART)"
        adb -s "$D" shell "OTA_GUARD_RESTART=$RESTART sh /data/local/tmp/ota_guard.sh"
        sleep 6
        echo
        adb -s "$D" shell "sh /data/local/tmp/ota_guard.sh status"
        ;;
    *)
        echo "unknown action: $ACTION (expected install, status or unblock)" >&2
        exit 2
        ;;
esac
