#!/bin/sh
# Install and start the StarTube stunnel keep-alive on SberPortal.
#
# Usage: D=<IP>:5555 ./scripts/install_stube_stunnel.sh
#
# What it does:
#   * pushes stube_stunnel_start.sh to /data/local/tmp
#   * hooks it into /data/local/tmp/sber_guard.sh (started at boot by
#     CentaurSwipeWatcher), so it survives reboots
#   * starts stunnel now and checks that 127.0.0.1:11085 is listening
set -e

D=${D:?укажи адрес портала: D=192.168.1.x:5555}
HERE=$(cd "$(dirname "$0")/.." && pwd)

adb connect "$D" >/dev/null 2>&1 || true
adb -s "$D" wait-for-device

echo "[1/3] push scripts"
adb -s "$D" push "$HERE/scripts/stube_stunnel_start.sh" /data/local/tmp/stube_stunnel_start.sh >/dev/null
adb -s "$D" push "$HERE/scripts/stube_stunnel_watchdog.sh" /data/local/tmp/stube_stunnel_watchdog.sh >/dev/null
adb -s "$D" shell 'chmod 755 /data/local/tmp/stube_stunnel_start.sh /data/local/tmp/stube_stunnel_watchdog.sh'

echo "[2/3] hook watchdog into sber_guard.sh"
adb -s "$D" shell '
  G=/data/local/tmp/sber_guard.sh
  [ -f "$G" ] || exit 0
  grep -q stube_stunnel_watchdog "$G" && exit 0
  sed -i "/stube_stunnel_start/d" "$G" 2>/dev/null || true
  sed -i "2i [ -x /data/local/tmp/stube_stunnel_watchdog.sh ] && (nohup sh /data/local/tmp/stube_stunnel_watchdog.sh >/dev/null 2>&1 \&)" "$G"
'

echo "[3/3] start watchdog and verify"
adb -s "$D" shell 'nohup sh /data/local/tmp/stube_stunnel_watchdog.sh >/dev/null 2>&1 &'
sleep 8
PID=$(adb -s "$D" shell 'pidof stube_tunnel' | tr -d '\r')
[ -n "$PID" ] || { echo "stunnel did not start; see /data/local/tmp/stube/stunnel.log" >&2; exit 1; }
adb -s "$D" shell 'grep -i ":2B4D" /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -1'
echo "stunnel is running (pid $PID), 127.0.0.1:11085 is listening"
