#!/system/bin/sh
# Keep StarTube's own stunnel tunnel alive.
#
# ru.sberdevices.startube has a built-in DPI-bypass path: stunnel client on
# 127.0.0.1:11085 -> star.edgehaul.xyz:4433 (PSK), which the app uses as a
# "blocked resource" proxy. The remote side resolves YouTube itself, so no DNS
# or NetFix is needed for it.
#
# Why this script exists: the app's ProxyUpdater starts its stunnel and then
# terminates it almost immediately (race: "Stunnel started" -> "Terminated"),
# so the proxy answers ECONNREFUSED and YouTube never loads. Here the same
# stunnel is started once, from the app's own config/PSK, and kept running.
#
# Started by sber_guard.sh (CentaurSwipeWatcher) at every boot, as root.
# Re-running is safe: it exits if stunnel is already up.

PKG=ru.sberdevices.startube
DIR=/data/local/tmp/stube
CONF=$DIR/stunnel.conf
LOG=$DIR/stunnel.log

# Wait for boot and for a default route: starting before Wi-Fi is up makes
# stunnel fail to resolve/connect and the app then restarts it anyway.
i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ $i -lt 60 ]; do
    sleep 2; i=$((i + 1))
done
i=0
# The default route lives in per-network tables on Android, so check that the
# Wi-Fi interface has routes at all.
while ! ip route 2>/dev/null | grep -q 'dev wlan0' && [ $i -lt 30 ]; do
    sleep 2; i=$((i + 1))
done

pidof stube_tunnel >/dev/null 2>&1 && exit 0
pidof libstunnel.so >/dev/null 2>&1 && exit 0

BASE=$(pm path $PKG 2>/dev/null | sed 's/^package://; s#/base.apk$##')
[ -n "$BASE" ] || exit 0
[ -x "$BASE/lib/arm/libstunnel.so" ] || exit 0

mkdir -p "$DIR"

# Keep the helper binary in sync with the installed app (it is an ELF exe
# stored as a native library; exec from the app lib dir is not reliable).
if [ ! -x "$DIR/stube_tunnel" ] || [ "$BASE/lib/arm/libstunnel.so" -nt "$DIR/stube_tunnel" ]; then
    cp "$BASE/lib/arm/libstunnel.so" "$DIR/stube_tunnel" 2>/dev/null || exit 0
fi
chmod 755 "$DIR/stube_tunnel"

PREFS=/data/data/$PKG/shared_prefs/APP_PREFS.xml
[ -f "$PREFS" ] || exit 0

# PSK secret (identity:key) and target are stored in the app's cached config.
PSK=$(grep -o 'startube3:[a-f0-9]*' "$PREFS" 2>/dev/null | head -1)
[ -n "$PSK" ] || exit 0
TARGET=$(grep -o '"target":"[^"]*"' "$PREFS" 2>/dev/null | head -1 | sed 's/.*:"//; s/"$//')
PORT=$(grep -o '"localPort":"[0-9]*"' "$PREFS" 2>/dev/null | head -1 | sed 's/.*:"//; s/"$//')
[ -n "$TARGET" ] || TARGET=star.edgehaul.xyz:4433
[ -n "$PORT" ] || PORT=11085
# The service is multi-homed and some addresses are dead; DNS order changes.
# An optional pin in $DIR/target (host:port) overrides the cached target.
[ -f "$DIR/target" ] && TARGET=$(cat "$DIR/target" 2>/dev/null)

printf '%s' "$PSK" > "$DIR/psk.txt" || exit 0
chmod 600 "$DIR/psk.txt"
{
    echo "debug = 3"
    echo "foreground = yes"
    echo "[auto-proxy-0]"
    echo "client = yes"
    echo "accept = $PORT"
    echo "connect = $TARGET"
    echo "PSKSecrets = $DIR/psk.txt"
} > "$CONF" || exit 0
chmod 600 "$CONF"

cd "$DIR" || exit 0
nohup ./stube_tunnel "$CONF" >/dev/null 2>>"$LOG" </dev/null &
