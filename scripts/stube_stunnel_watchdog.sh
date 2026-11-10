#!/system/bin/sh
# Restart the StarTube stunnel if it dies.
#
# StarTube's ProxyUpdater can kill a stunnel instance (it does that to its own
# one right after starting it, and may also kill ours), and at boot the network
# is not ready yet. This watchdog keeps re-starting the tunnel until it stays
# up. Started detached by sber_guard.sh at boot.
#
# Safe to run multiple times: a pid file keeps a single instance.

DIR=/data/local/tmp/stube
PIDFILE=$DIR/watchdog.pid
mkdir -p "$DIR"
BOOT=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -f "$PIDFILE" ]; then
    read OLD OLD_BOOT < "$PIDFILE" 2>/dev/null
    # Ignore a pid from a previous boot: the number may be reused.
    [ "$OLD_BOOT" = "$BOOT" ] && [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$ $BOOT" > "$PIDFILE"

WARM="$DIR/warm_$BOOT"

while true; do
    if ! pidof stube_tunnel >/dev/null 2>&1 && ! pidof libstunnel.so >/dev/null 2>&1; then
        if [ "$(getprop sys.boot_completed)" = "1" ]; then
            sh /data/local/tmp/stube_stunnel_start.sh
            sleep 2
        fi
    fi
    # An app instance started at boot before the tunnel was ready keeps its
    # failed state and ignores later links. Drop it once per boot; the YouTube
    # button then starts a fresh process with the tunnel already listening.
    if [ ! -f "$WARM" ] && grep -q ':2B4D' /proc/net/tcp 2>/dev/null; then
        am force-stop ru.sberdevices.startube >/dev/null 2>&1
        touch "$WARM"
    fi
    sleep 3
done
