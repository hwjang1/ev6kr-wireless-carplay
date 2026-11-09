#!/system/bin/sh
# ev6kr.usbap.sync service: keep the USB Wi-Fi hotspot on the stock CarPlay hotspot settings.
# Checks every 30 s (the stock settings are re-read only when softap.conf changes).
# An empty /data/nemesis/ev6kr.usbap.sync.disabled pauses it. It also keeps a debug logcat
# file unless /data/nemesis/ev6kr.usbap.sync.nodebug exists (scripts/common.sh debug_logcat).
umask 022
. "${0%/svc/*}/scripts/common.sh"
INTERVAL=${INTERVAL:-30}
[ -f "$LOG" ] && mv "$LOG" "$LOG.old" 2>/dev/null
say "apsync start (pid $$)"
net_tune
while true; do
    debug_logcat
    netsample_ctl
    tune_ctl
    if [ -f "$DISABLED" ]; then
        note "paused ($DISABLED)"
    else
        sync_once
        usb_hotspot_check
    fi
    [ -n "$APSYNC_ONCE" ] && break
    sleep "$INTERVAL"
done
