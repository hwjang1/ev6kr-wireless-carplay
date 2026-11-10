#!/system/bin/sh
# EV6 KR wireless CarPlay - preflight check before installing HMG-API and the packages.
# READ ONLY: changes nothing. Writes EV6KR-PREFLIGHT.txt on this USB drive.
# No passwords, VIN, serials or MAC addresses are written.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
R=$(pwd)/EV6KR-PREFLIGHT.txt
: > "$R" || exit 1
say() { echo "$1" >> "$R"; }
verdict() { say "[$1] $2"; }

say "ev6kr-preflight 2"
say "date $(date)"
P=$(getprop ro.build.product)
say "ro.build.product=$P"
say "ro.mobis.onebindir=$(getprop ro.mobis.onebindir)"
say ""

case "$P" in
    CVEV.KOR.*.260902) verdict OK "Korean EV6 on 260902 (the firmware the packages and the map are made for)" ;;
    CVEV.KOR.*) verdict WARN "Korean EV6 but not 260902: the map and the patches were made from 260902; map this car on the unit" ;;
    *) verdict STOP "not a Korean EV6: these packages are for CVEV.KOR only" ;;
esac

_m=$(md5 /system/bin/app_process 2>/dev/null); _m=${_m%% *}
if [ -f /system/bin/app_process.hmgapi-stock ]; then
    verdict OK "HMG-API's app_process wrapper is already in place"
elif [ "$_m" = 33f798115689d1859e8d2159dc88e7dc ]; then
    verdict OK "app_process $_m is a build HMG-API knows (US EV6 260507): installs without FORCE"
else
    verdict WARN "app_process $_m isn't a build HMG-API knows: its installer needs an empty HMGAPI/FORCE on the stick (own risk; send this md5 to the HMG-API maintainers)"
fi
[ -f /system/bin/app_process.leafia-stock ] && verdict STOP "a Leafia dev build's app_process wrapper is in place: uninstall it first (sh /data/leafia/uninstall.sh)"

_pk=$(nemesis pkg-list 2>/dev/null)
say ""
say "--- NEMESIS packages"
echo "$_pk" | while IFS='|' read -r _id _name _locked _types _ver _rest; do [ -n "$_id" ] && say "$_id $_ver ($_name)"; done
case "$_pk" in *"wireless.carplay.aa|"*) verdict STOP "HMG Leafia Plus (wireless.carplay.aa) is installed: uninstall it in NEMESIS Manager and restart the head unit first" ;; esac
for _old in wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio carplay.session; do
    case "$_pk" in *"$_old|"*) verdict STOP "$_old is installed: it changes the same apps, uninstall it first" ;; esac
done
case "$_pk" in
    *"usbwifi.hotspot|"*) verdict OK "usbwifi.hotspot is installed" ;;
    *) verdict STOP "usbwifi.hotspot (USB Wi-Fi Hotspot Enabler) is not installed" ;;
esac
case "$_pk" in *"hmgapi|"*) verdict OK "HMG-API is installed" ;; *) verdict INFO "HMG-API is not installed yet" ;; esac
[ -x /system/bin/hmgapid ] || [ -x /system/xbin/hmgapid ] && say "hmgapid: $(hmgapid ping 2>&1)"

say ""
_c=/data/nemesis/apps/usbwifi.hotspot/config/hotspot.conf
[ -f "$_c" ] || _c=/data/nemesis/packages/usbwifi.hotspot/config/hotspot.conf
if [ -f "$_c" ]; then
    while IFS= read -r _l; do
        case "$_l" in WIFI_MODE=*|AP_SSID=*|AP_HW_MODE=*|AP_CHANNEL=*|MODULE_ARGS=*|FORCE_SUBNET=*) say "hotspot.conf $_l" ;; esac
    done < "$_c"
    case "$(grep '^WIFI_MODE=' "$_c")" in *sta*) verdict WARN "the USB Wi-Fi is in client (STA) mode: wireless CarPlay needs its hotspot (AP) mode" ;; esac
else
    verdict INFO "no hotspot.conf yet (the USB Wi-Fi package uses its defaults)"
fi
say "USB Wi-Fi interfaces: $(ls /sys/class/net 2>/dev/null | grep -E 'rtwlan|wlan' | while read i; do echo -n "$i($(cat /sys/class/net/$i/operstate 2>/dev/null)) "; done)"
[ -f /data/local/tmp/usbwifi_hotspot/hostapd.pid ] && [ -d "/proc/$(cat /data/local/tmp/usbwifi_hotspot/hostapd.pid 2>/dev/null)" ] \
    && verdict OK "the USB Wi-Fi hotspot (hostapd) is running" || verdict WARN "the USB Wi-Fi hotspot isn't running now (dongle in? AP mode?)"

if [ -f /data/misc/wifi/softap.conf ]; then
    verdict OK "stock hotspot settings present ($(ls -l /data/misc/wifi/softap.conf 2>/dev/null))"
else
    verdict WARN "no /data/misc/wifi/softap.conf: the stock CarPlay SSID/password haven't been made yet"
fi
grep -l 'security.unece' /system/etc/permissions/*.xml >/dev/null 2>&1 && verdict STOP "this unit encrypts the hotspot passwords (security.unece): the sync package can't read them"

# free space on /data (toolbox df: "/data  9.2G  2.3G  6.9G  4096"). The packages' logs take ~7 MB
# at most; the sync package's debug logging stops under 100 MB free.
set -- $(/system/bin/df /data 2>/dev/null | grep '^/data ')
_low="free some space first: the sync package's debug logging stops under 100 MB free"
case "$4" in
    *G) verdict OK "/data: $4 free of $2" ;;
    *M) _n=${4%M}; _n=${_n%%.*}
        if [ "${_n:-0}" -ge 100 ]; then verdict OK "/data: $4 free of $2"; else verdict WARN "/data: only $4 free of $2: $_low"; fi ;;
    *K) verdict WARN "/data: only $4 free of $2: $_low" ;;
    *) verdict INFO "/data free space unknown (no toolbox df)" ;;
esac

say ""
say "--- props"
for p in persist.ium.support persist.sys.iap2.wifi persist.iap2.iden.wireless persist.service.adb.tcp.enable ro.product.opt.stepofspec; do
    say "$p=$(getprop $p)"
done
say ""
say "end (STOP lines must be fixed first; WARN lines need a decision)"
sync
exit 0
