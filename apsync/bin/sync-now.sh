#!/system/bin/sh
# ev6kr.usbap.sync app (NEMESIS Manager > Launch): sync now and show the result.
umask 022
. "${0%/bin/*}/scripts/common.sh"
if [ -f "$DISABLED" ]; then
    rm -f "$DISABLED"
    say "un-paused from the app"
fi
if sync_once; then
    _c=$(usb_conf)
    toast "CarPlay hotspot: USB Wi-Fi uses SSID $(conf_value "$_c" AP_SSID), $(conf_value "$_c" AP_HW_MODE)/ch $(conf_value "$_c" AP_CHANNEL)"
else
    toast "CarPlay hotspot sync failed: $LAST_NOTE"
    exit 1
fi
exit 0
