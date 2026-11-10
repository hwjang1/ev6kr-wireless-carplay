#!/system/bin/sh
# ev6kr.usbap.sync service: keep the USB Wi-Fi hotspot on the stock CarPlay hotspot settings.
# Checks every 30 s (the stock settings are re-read only when softap.conf changes).
# An empty /data/nemesis/ev6kr.usbap.sync.disabled pauses it. Debug logging (a logcat file and
# the network sampler) is off unless /data/nemesis/ev6kr.usbap.sync.debug exists (since 0.2.0;
# the trylog stick's EV6KR-DEBUG-ON makes it, shared/rtwlan.sh debug_logcat).
# Every file it writes has a cap (shared/rtwlan.sh): the debug logcat 1 MB x (1 + 4), the sampler
# two files of 30 min, its own log 256 KB (and .old). Under 100 MB free on /data the debug
# logging stops and its files go (disk_check). With debug logging off, a start (a boot)
# removes the debug files left from before (debug_start_cleanup).
umask 022
. "${0%/svc/*}/scripts/common.sh"
INTERVAL=${INTERVAL:-30}
[ -f "$LOG" ] && mv "$LOG" "$LOG.old" 2>/dev/null
FREE_MB=$(data_free_mb)
say "apsync start (pid $$), /data free: ${FREE_MB:-unknown} MB"
debug_start_cleanup
net_tune
while true; do
    log_cap
    disk_check
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
