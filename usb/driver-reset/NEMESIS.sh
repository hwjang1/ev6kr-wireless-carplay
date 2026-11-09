#!/system/bin/sh
# EV6 KR - put usbwifi.hotspot back on its own dongle driver (the one in its package, v5.8.7.1).
# Removes the override modules/88x2bu_<ro.board.platform>.ko (a test driver build put there by
# hand, docs/ANALYSIS.md 21), which usbwifi.hotspot loads before its own 88x2bu.ko, and says
# which driver runs now and which one the next boot loads. Writes DRIVER-RESET.txt next to this
# script. Reboot the head unit afterwards: a loaded driver stays until then.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
H=$(pwd)
R=$H/DRIVER-RESET.txt
NEMESIS_DIR=${EV6KR_NEMESIS_DIR:-/data/nemesis}
SYSMODULE=${EV6KR_SYSMODULE:-/sys/module}
HMGAPI_MODS=${EV6KR_HMGAPI_MODS:-/data/hmgapi/mods}
: > "$R"
say() { echo "$1" >> "$R"; }

say "ev6kr driver-reset 1"
say "date: $(date)"
PLAT=$(getprop ro.board.platform)
say "platform: $PLAT"
APP=$NEMESIS_DIR/apps/usbwifi.hotspot
[ -d "$APP" ] || APP=$NEMESIS_DIR/packages/usbwifi.hotspot
if [ ! -d "$APP/modules" ]; then
    say "usbwifi.hotspot isn't installed (no $APP/modules): install it first"
else
    T=$APP/modules/88x2bu_$PLAT.ko
    if [ -f "$T" ]; then
        rm -f "$T"
        if [ -f "$T" ]; then say "FAIL: can't remove ${T##*/}"; else say "removed ${T##*/}: the next boot loads usbwifi.hotspot's own 88x2bu.ko"; fi
    else
        say "no ${T##*/} override: usbwifi.hotspot loads its own 88x2bu.ko"
    fi
    say "usbwifi.hotspot modules now:"
    ls -l "$APP/modules" >> "$R" 2>&1
fi
[ -d "$HMGAPI_MODS/usb-hotspot-kr" ] && say "NOTE: the usb-hotspot-kr mod is still installed: remove it (it stays off while usbwifi.hotspot is installed, but its driver may be the loaded one until a reboot)"
say ""
say "loaded now: 88x2bu $(cat "$SYSMODULE/88x2bu/version" 2>/dev/null) srcversion $(cat "$SYSMODULE/88x2bu/srcversion" 2>/dev/null)"
say "  (v5.8.7.1_35809... is usbwifi.hotspot's own; v5.13.1-20-... is a test build: reboot to change)"
say "reboot the head unit now, with the dongle in"
sync
exit 0
