#!/system/bin/sh
# SberPortal: block Sber firmware/StarOS OTA updates (device-side, root).
#
# Three independent layers:
#
#   1. localOverrideStar.json disables the StarOS updater's scheduled/night
#      checks, skip-and-update-on-boot/SUW and install notifications.  StarOS
#      already has a local override mechanism (localOverridableConfig in
#      assets/updater.json + localRulesStar.json); this is the supported way
#      to change updater behaviour without touching the APK.
#
#   2. /data/updateScript.sh -- the exact path the updater uses for the signed
#      update script it receives from the backend (services.update.
#      updateScriptStorePath).  The file is made immutable, mode 000, root-
#      owned.  The updater runs as uid 1000 (system), so it cannot truncate,
#      unlink or chattr -i it: the script cannot be stored or executed.
#
#   3. update_engine is stopped.  Even if a payload or script appears through
#      another path, there is no daemon to apply it; update_engine_client
#      cannot connect to a stopped service.
#
# Idempotent. Called by sber_guard.sh after each boot, and by
# ota_block_setup.sh / install_top_sheet.sh from the host.
#
# Usage:
#   sh ota_guard.sh            apply / refresh the block
#   sh ota_guard.sh status     print current state
#   sh ota_guard.sh unblock    remove the block (rollback)
#
# Env:
#   OTA_GUARD_RESTART=1  restart ru.sberdevices.services when the override
#                        file actually changed (default 1, 0 = never)

PKG=ru.sberdevices.services
STAROS=/data/data/$PKG/files/staros
OVERRIDE=$STAROS/localOverrideStar.json
OVERRIDE_BAK=$OVERRIDE.ota-guard.bak
SCRIPT=/data/updateScript.sh
LOG=/data/local/tmp/ota_guard.log
LOG_MAX=200000
RESTART=${OTA_GUARD_RESTART:-1}

log() {
    if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null)" -gt "$LOG_MAX" ]; then
        mv -f "$LOG" "$LOG.1" 2>/dev/null
    fi
    echo "$(date '+%F %T') $*" >>"$LOG"
}

status() {
    echo "override: $OVERRIDE"
    if [ -f "$OVERRIDE" ]; then
        if grep -q '"nightUpdatesEnabled": false' "$OVERRIDE" 2>/dev/null; then
            echo "  nightUpdatesEnabled: false"
        else
            echo "  present, but nightUpdatesEnabled is not false"
        fi
        lsattr "$OVERRIDE" 2>/dev/null
        stat -c '  %A %U:%G %s bytes' "$OVERRIDE" 2>/dev/null
    else
        echo "  MISSING"
    fi

    echo "update script: $SCRIPT"
    if [ -e "$SCRIPT" ]; then
        lsattr "$SCRIPT" 2>/dev/null
        stat -c '  %A %U:%G %s bytes' "$SCRIPT" 2>/dev/null
    else
        echo "  MISSING"
    fi

    echo "update_engine: $(getprop init.svc.update_engine)"
    echo "update_engine pid: $(pidof update_engine 2>/dev/null)"
    echo "updater process: $(pidof "$PKG:stardroid_updater" 2>/dev/null)"

    # The updater logs its own merged config at start.  This shows whether the
    # override reached the updater process, not just the config file on disk.
    UPD=$STAROS/service_logs/updater.log
    NIGHT=$(grep -o 'nightUpdatesEnabled[^,]*' "$UPD" 2>/dev/null | tail -1)
    echo "updater config: ${NIGHT:-not logged yet}"

    PENDING=
    for d in /data/ota_package /data/ota; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -e "$f" ] || continue
            PENDING="$PENDING $f"
        done
    done
    echo "pending payloads:${PENDING:- none}"
}

write_override() {
    TMP=/data/local/tmp/ota_override.json
    cat >"$TMP" <<'JSON'
{
  "services": {
    "update": {
      "nightUpdatesEnabled": false,
      "skipAndUpdateOnBoot": {
        "enabled": false
      },
      "skipAndUpdateOnSuw": {
        "enabled": false
      },
      "installNonCriticalUpdateOnFirstSetup": false,
      "handleUpdateOnDeviceWakeUp": false,
      "showInstallNotification": false
    }
  }
}
JSON

    if cmp -s "$TMP" "$OVERRIDE" 2>/dev/null; then
        # Keep the flag even if the content was already correct (e.g. the
        # first run created the file before chattr was applied).
        chattr +i "$OVERRIDE" 2>/dev/null
        rm -f "$TMP"
        return 1
    fi

    if [ -e "$OVERRIDE" ] && [ ! -e "$OVERRIDE_BAK" ]; then
        chattr -i "$OVERRIDE" 2>/dev/null
        cp -f "$OVERRIDE" "$OVERRIDE_BAK" 2>/dev/null
        log "backed up existing override to $OVERRIDE_BAK"
    fi

    chattr -i "$OVERRIDE" 2>/dev/null
    rm -f "$OVERRIDE" 2>/dev/null
    mkdir -p "$STAROS" 2>/dev/null
    cp "$TMP" "$OVERRIDE" 2>/dev/null
    rm -f "$TMP" 2>/dev/null
    chown system:system "$OVERRIDE" 2>/dev/null
    chmod 600 "$OVERRIDE" 2>/dev/null
    chattr +i "$OVERRIDE" 2>/dev/null
    lsattr "$OVERRIDE" 2>/dev/null | cut -d' ' -f1 | grep -q i ||
        log "WARN: chattr +i failed on $OVERRIDE"
    log "installed update override: $OVERRIDE"
    return 0
}

block_update_script() {
    if [ -d "$SCRIPT" ]; then
        chattr +i "$SCRIPT" 2>/dev/null
        log "update script path is a directory: $SCRIPT"
        return 0
    fi

    if [ -e "$SCRIPT" ]; then
        chattr -i "$SCRIPT" 2>/dev/null
        : >"$SCRIPT" 2>/dev/null
    else
        : >"$SCRIPT" 2>/dev/null
    fi
    chown root:root "$SCRIPT" 2>/dev/null
    chmod 000 "$SCRIPT" 2>/dev/null
    chattr +i "$SCRIPT" 2>/dev/null
    lsattr "$SCRIPT" 2>/dev/null | cut -d' ' -f1 | grep -q i ||
        log "WARN: chattr +i failed on $SCRIPT"
    log "blocked update script path: $SCRIPT"
}

stop_update_engine() {
    setprop ctl.stop update_engine 2>/dev/null
    sleep 1
    P=$(pidof update_engine 2>/dev/null)
    if [ -n "$P" ]; then
        log "update_engine still alive ($P), killing"
        kill -9 $P 2>/dev/null
    fi
    log "update_engine=$(getprop init.svc.update_engine) pid=$(pidof update_engine 2>/dev/null)"
}

restart_service() {
    P1=$(pidof "$PKG" 2>/dev/null)
    P2=$(pidof "$PKG:stardroid_updater" 2>/dev/null)
    [ -n "$P1$P2" ] || return 0
    log "restarting $PKG (main=$P1 updater=$P2) to apply override"
    [ -n "$P1" ] && kill -9 $P1 2>/dev/null
    [ -n "$P2" ] && kill -9 $P2 2>/dev/null
}

unblock() {
    if [ -e "$OVERRIDE" ]; then
        chattr -i "$OVERRIDE" 2>/dev/null
        rm -f "$OVERRIDE" 2>/dev/null
    fi
    if [ -e "$OVERRIDE_BAK" ]; then
        cp -f "$OVERRIDE_BAK" "$OVERRIDE" 2>/dev/null
        chown system:system "$OVERRIDE" 2>/dev/null
        chmod 600 "$OVERRIDE" 2>/dev/null
        log "restored previous override from $OVERRIDE_BAK"
    fi
    if [ -e "$SCRIPT" ]; then
        chattr -i "$SCRIPT" 2>/dev/null
        rm -f "$SCRIPT" 2>/dev/null
    fi
    setprop ctl.start update_engine 2>/dev/null
    log "OTA block removed"
    echo "OTA block removed; update_engine=$(getprop init.svc.update_engine)"
}

case "$1" in
    status)
        status
        exit 0
        ;;
    unblock)
        unblock
        exit 0
        ;;
esac

CHANGED=0
write_override && CHANGED=1
block_update_script
stop_update_engine

if [ "$CHANGED" = "1" ] && [ "$RESTART" = "1" ]; then
    restart_service
fi

log "done: override_changed=$CHANGED restart=$RESTART update_engine=$(getprop init.svc.update_engine)"
