#!/system/bin/sh
# Optional: keep StarTube's stunnel tunnel running (YouTube button in Centaur).
[ -x /data/local/tmp/stube_stunnel_watchdog.sh ] && (nohup sh /data/local/tmp/stube_stunnel_watchdog.sh >/dev/null 2>&1 &)
# SberPortal: keep the native Sber assistant silent while Centaur (Alice) is
# the active assistant.
#
# The StarOS service ru.sberdevices.services runs its own always-on StarDroid
# spotter.  It accepts the stock `names.stargate` model, but its config has
# per-class thresholds.  Raising them above 1.0 makes the engine load the model
# normally and score it normally, but never report an activation.  This is the
# default mode: the service stays alive (gestures, audio focus, StarOS UI are
# untouched) and no process is killed.
#
# MODE=config (default)
#   Every 2 s check every config_* of the names.stargate spotter and force all
#   per-class thresholds to 100000.0 in place.  The rest of the file (model
#   version, class list, interpreter settings) is left untouched, so this also
#   works after a StarOS update with a different hot-word list.  chattr +i
#   keeps the service from restoring the stock thresholds.  If a config had to
#   be changed, the service is restarted once so it re-reads it (the spotter
#   does not watch the config file).
#
# MODE=kill
#   Fallback: tail spotter.log and kill -9 ru.sberdevices.services on any
#   "Spotter activation".  StarOS then cleans up root/shell processes, which
#   also kills this guard and the app_process watcher; RavnBootStarter and
#   CentaurSwipeWatcher restart them.  Use only if the config mode stops
#   working (e.g. a future StarOS ignores thresholds).
#
# MODE=periodic PERIOD=5
#   Blunt fallback: kill every PERIOD seconds.
#
# Files:
#   log      /data/local/tmp/sber_guard.log
#   pidfile  /data/local/tmp/sber_guard.pid

PKG=ru.sberdevices.services
CFG_DIR=/data/data/$PKG/files/staros
SPOTTER_LOG=$CFG_DIR/service_logs/spotter.log
OUT=/data/local/tmp/sber_guard.log
PIDFILE=/data/local/tmp/sber_guard.pid
MODE=${MODE:-config}
PERIOD=${PERIOD:-5}

log() { echo "$(date '+%F %T') $*" >>"$OUT"; }

# --- one instance ----------------------------------------------------------
if [ -f "$PIDFILE" ]; then
    OLD=$(cat "$PIDFILE" 2>/dev/null)
    # After a reboot PIDs are reused; /proc/<old> may be an unrelated process.
    # Only treat the pidfile as live if that process is actually this script.
    if [ -n "$OLD" ] && [ -d "/proc/$OLD" ] &&
       tr '\0' ' ' <"/proc/$OLD/cmdline" 2>/dev/null | grep -q 'sber_guard\.sh'; then
        exit 0
    fi
fi
echo $$ >"$PIDFILE"
cleanup() { rm -f "$PIDFILE"; }
trap cleanup EXIT
trap 'exit 0' INT TERM

# Firmware/OTA block (see OTA_BLOCK.md).  Idempotent; it only restarts the
# Sber service when localOverrideStar.json actually changed.
if [ -f /data/local/tmp/ota_guard.sh ]; then
    OTA_GUARD_RESTART=1 /system/bin/sh /data/local/tmp/ota_guard.sh >/dev/null 2>&1
fi

kill_sber() {
    P=$(pidof "$PKG" 2>/dev/null)
    [ -z "$P" ] && return 0
    kill -9 $P 2>/dev/null
    log "kill $PKG [$P] ($1)"
}

# --- mode: config ----------------------------------------------------------
config_mode() {
    log "start: mode=config (thresholds in place)"
    while :; do
        # A new config can appear under a different config_<hash> name, so
        # scan the directory instead of hard-coding one file name.
        RESTORED=
        for f in "$CFG_DIR"/config_*; do
            [ -f "$f" ] || continue
            grep -qE '^hotword = (salut|sber|afina|joy)$' "$f" 2>/dev/null || continue

            # Count threshold lines that are not already 100000.0.  Keep the
            # rest of the config (model_version, class list, interpreter) as
            # the service wrote it, so a new StarOS version still parses.
            BAD=$(grep -E '^(high_threshold|threshold|sub_threshold) = ' "$f" 2>/dev/null | grep -vc '= 100000\.0$')
            if [ "${BAD:-0}" -gt 0 ]; then
                chattr -i "$f" 2>/dev/null
                sed -i \
                    -e 's/^high_threshold = .*/high_threshold = 100000.0/' \
                    -e 's/^threshold = .*/threshold = 100000.0/' \
                    -e 's/^sub_threshold = .*/sub_threshold = 100000.0/' \
                    "$f"
                chown system:system "$f" 2>/dev/null
                chmod 600 "$f" 2>/dev/null
                chattr +i "$f" 2>/dev/null
                log "silenced config: $(basename "$f") ($BAD non-silent thresholds)"
                RESTORED=1
            elif ! lsattr "$f" 2>/dev/null | cut -d' ' -f1 | grep -q 'i'; then
                chattr +i "$f" 2>/dev/null && log "immutable: $(basename "$f")"
            fi
        done

        # The service reads the config only when it starts the spotter (it does
        # not watch the file), so a changed config needs one service restart.
        # This is the only case where config mode kills anything.
        if [ "$RESTORED" = "1" ]; then
            log "restarting $PKG to load the silent config"
            kill_sber "silent config restored"
            sleep 5
        fi
        sleep 2
    done
}

# --- mode: kill (fallback) -------------------------------------------------
kill_mode() {
    log "start: mode=kill log=$SPOTTER_LOG"
    LAST=
    while :; do
        SIZE=$(stat -c %s "$SPOTTER_LOG" 2>/dev/null)
        case "$SIZE" in
            ''|*[!0-9]*) sleep 1; continue ;;
        esac
        if [ -z "$LAST" ]; then
            LAST=$SIZE
            sleep 0.2
            continue
        fi
        [ "$SIZE" -lt "$LAST" ] && LAST=0
        if [ "$SIZE" -gt "$LAST" ]; then
            tail -c +$((LAST + 1)) "$SPOTTER_LOG" 2>/dev/null |
            while IFS= read -r line; do
                case "$line" in
                    *"Spotter activation"*) kill_sber "$line" ;;
                esac
            done
            LAST=$SIZE
        fi
        sleep 0.2
    done
}

periodic_mode() {
    log "start: mode=periodic period=${PERIOD}s"
    while :; do
        kill_sber periodic
        sleep "$PERIOD"
    done
}

case "$MODE" in
    kill)     kill_mode ;;
    periodic) periodic_mode ;;
    *)        config_mode ;;
esac
