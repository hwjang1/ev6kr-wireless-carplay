#!/system/bin/sh
# Car info for porting this project to another Hyundai/Kia/Genesis head unit (Gen5W): is it the
# same platform, does it have a stock Wi-Fi module, and are its CarPlay files the same as the
# Korean EV6's on 260902 (the ones the mod's patches and hooks are made for).
# READ ONLY: changes nothing on the car. Writes CARINFO-<model>-<region>.txt on this USB drive.
# No passwords, SSIDs, VIN, serials, phone names, or MAC/Bluetooth addresses are written.
# An empty file CARINFO-FILES next to this script also copies the CarPlay files that differ from
# the EV6's into CARINFO-FILES-<model>-<region>/: those are the car maker's files, for private
# analysis only. Don't publish them.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin   # KitKat toolbox: no head, tail, awk or cp
H=$(pwd)
P=$(getprop ro.build.product)
case "$P" in
    *.*) M=${P%%.*}; _r=${P#*.}; G=${_r%%.*} ;;
    *) M=unknown; G=unknown ;;
esac
case "$M$G" in ""|*[!A-Za-z0-9_]*) M=unknown; G=unknown ;; esac
R="$H/CARINFO-$M-$G.txt"
: > "$R" || exit 1
say() { echo "$1" >> "$R"; }
verdict() { say "[$1] $2"; }
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
    true
}
md5of() { _h=$(md5 "$1" 2>/dev/null); echo "${_h%% *}"; }
toast "차량 정보 수집 중: '수집 완료' 메시지가 뜰 때까지 USB를 빼지 마세요"

say "carinfo 3"
say "date $(date)"
say "up $(cat /proc/uptime 2>/dev/null)"
say ""

# ---- the car and its software
say "--- car"
for p in ro.build.product ro.mobis.onebindir ro.product.locale.region ro.board.platform ro.product.board \
         ro.build.version.release ro.product.opt.stepofspec; do
    say "$p=$(getprop $p)"
done
case "$(getprop ro.board.platform)" in
    tcc803x|tcc897x) verdict OK "Telechips $(getprop ro.board.platform): a Gen5W head unit, the platform NEMESIS and HMG-API run on" ;;
    *) verdict STOP "platform '$(getprop ro.board.platform)' isn't a Gen5W one (tcc803x/tcc897x)" ;;
esac
case "$P" in
    CVEV.KOR.*.260902) verdict INFO "this is the Korean EV6 on 260902: everything below should be the same as the reference" ;;
    *.KOR.*) verdict OK "a Korean firmware" ;;
    *) verdict INFO "not a Korean firmware: this project is made for Korean units" ;;
esac
say ""

# ---- NEMESIS and HMG-API
say "--- NEMESIS packages"
_pk=$(nemesis pkg-list 2>/dev/null)
echo "$_pk" | while IFS='|' read -r _id _name _locked _types _ver _rest; do [ -n "$_id" ] && say "$_id $_ver ($_name)"; done
_m=$(md5of /system/bin/app_process)
say "app_process md5 $_m"
if [ -f /system/bin/app_process.hmgapi-stock ]; then
    verdict INFO "HMG-API's app_process wrapper is in place (stock md5 $(md5of /system/bin/app_process.hmgapi-stock))"
elif [ "$_m" = 33f798115689d1859e8d2159dc88e7dc ]; then
    verdict OK "app_process is a build HMG-API knows (US EV6 260507)"
else
    verdict INFO "app_process isn't a build HMG-API knows: its installer would need HMGAPI/FORCE (own risk)"
fi
say ""

# ---- stock Wi-Fi module: with one, the car's own wireless CarPlay (or Korea Projection) fits
# better than a USB dongle. The car's WifiService knows the board's module variant (3 = no module
# on the EV6) and prints it in its dump; only that line is kept (the dump also lists networks).
# Its boot log line is the fallback, but the log keeps only about the last 30 s.
say "--- stock Wi-Fi"
# (KitKat's toolbox has no head or tail: shell loops pick the line)
first_feature() { while read -r _l; do case "$_l" in *"[Feature]"*) echo "$_l"; return ;; esac; done; }
last_feature() { _f=""; while read -r _l; do case "$_l" in *WifiService*"[Feature]"*) _f=$_l ;; esac; done; echo "$_f"; }
_w=$(dumpsys wifi 2>/dev/null | first_feature)
[ -n "$_w" ] || _w=$(logcat -d -v time 2>/dev/null | last_feature)
if [ -n "$_w" ]; then
    say "${_w#*: }"
    case "$_w" in
        *"HW Variant(3)"*) verdict OK "Wi-Fi module variant 3: no stock Wi-Fi module (as the EV6): the USB dongle way fits" ;;
        *"Hardware(supported)"*) verdict WARN "the board reports a stock Wi-Fi module: stock wireless CarPlay or Korea Projection may fit better than a dongle" ;;
        *) verdict INFO "Wi-Fi module variant line above: compare with the EV6's 'Hardware(not supported), HW Variant(3)'" ;;
    esac
else
    verdict INFO "the car's Wi-Fi service didn't report its module variant (no [Feature] line in its dump or the log)"
fi
_s=""; for _i in $(ls /sys/bus/sdio/devices 2>/dev/null); do _s="$_s$_i "; done
say "sdio devices: ${_s:-none}"
say "bcmdhd loaded: $(grep -c '^bcmdhd ' /proc/modules 2>/dev/null)"
say "network interfaces: $(ls /sys/class/net 2>/dev/null | while read -r i; do echo -n "$i "; done)"
say "feature files (com.hkmc.software.*, Wi-Fi and projection):"
ls /system/etc/permissions 2>/dev/null | grep -E 'com\.hkmc\.software\..*(wifi|hotspot|carplay|androidauto|connectivity)' | while read -r f; do say "  $f"; done
_fx=/system/onebin/$(getprop ro.mobis.onebindir)/featurexml.cfg
if [ -f "$_fx" ]; then
    say "variant feature list $_fx (md5 $(md5of "$_fx")), Wi-Fi and projection lines:"
    grep -E 'wifi|hotspot|carplay|androidauto|connectivity' "$_fx" 2>/dev/null | while read -r l; do say "  $l"; done
fi
if grep -l 'security.unece' /system/etc/permissions/*.xml >/dev/null 2>&1; then
    verdict WARN "this unit encrypts the hotspot passwords (security.unece): the hotspot sync package can't read them as it is"
fi
[ -f /data/misc/wifi/softap.conf ] && say "stock hotspot settings file present (not read)" \
    || say "no stock hotspot settings file yet (/data/misc/wifi/softap.conf)"
for p in persist.ium.support persist.sys.iap2.wifi persist.iap2.iden.wireless; do say "$p=$(getprop $p)"; done
say ""

# ---- CarPlay files against the Korean EV6 on 260902
say "--- CarPlay files (md5; 'same' = identical to the Korean EV6 on 260902)"
FL=$H/CARINFO-FILES
FD=$H/CARINFO-FILES-$M-$G
REF="2d2e2116fc9a30ab2e435c3b8cafc695 /system/lib/libCarPlay.so
ea0ca708efa1379d48e8bbffe3183f52 /system/lib/libCarPlayAndroid.so
2b748bf85652b683abfbc4ce55db3efa /system/lib/libCarPlayAudio.so
ef49c09b7ab5eb72298f9973443b66b3 /system/lib/libCarPlayCore.so
cf3cc23dad25b181a9fc12d606468715 /system/lib/libCarPlayCoreUtils.so
e85385d70194efe82cc8a6d0f66f5115 /system/lib/libCarPlayUtils.so
3573b51da6d4407466594226d9368c2e /system/app/HKMC_DiPO.apk
caf67d3b49d8f8e5cbed4d46062bdf62 /system/app/HKMC_DiPO.odex
fde208439f993986a60396e759797a01 /system/app/Iap2ServerApp.apk
a44a337b979f2af5251d7d30b75fe5e4 /system/app/Iap2ServerApp.odex
9b7645e0ce8558e344b1884639823955 /system/app/PhoneProjection.apk
1078375074db0aed687af6704bcf56a1 /system/app/PhoneProjection.odex
9202e545a5483b77ae033a13743d9a84 /system/app/HKMC_BtSettings.apk
22363be5ef257cf78a9947f758b4899f /system/app/HKMC_BtSettings.odex
e5466f2107142aa276b72c1241507710 /system/framework/automotive-service.jar
80ee7af3692f393da1ed6d8fefa26108 /system/framework/automotive-service.odex
8154687c0d0a5f13cf3a664db2b802ea /system/framework/com.tcc.iap2.jar
71b4490695e60e6d8c4a8c52f107c098 /system/framework/com.tcc.iap2.odex"
echo "$REF" | while read -r _ref _f; do
    [ -n "$_f" ] || continue
    if [ ! -f "$_f" ]; then say "missing  $_f"; continue; fi
    _h=$(md5of "$_f")
    if [ "$_h" = "$_ref" ]; then
        say "same     $_h  $_f"
    else
        say "differs  $_h  $_f"
        if [ -f "$FL" ]; then
            mkdir -p "$FD" 2>/dev/null && cat "$_f" > "$FD/${_f##*/}" 2>/dev/null || say "         (copy failed)"
        fi
    fi
done
_n=$(grep -c '^same ' "$R"); _d=$(grep -c '^differs ' "$R"); _x=$(grep -c '^missing ' "$R")
if [ "$_d" = 0 ] && [ "$_x" = 0 ]; then
    verdict OK "all $_n CarPlay files are the same as the EV6's: the mod's patches and DiPO hooks should fit as they are"
else
    verdict INFO "$_n same, $_d different, $_x missing: the different ones need their own analysis before the mod can run"
    [ -f "$FL" ] && say "the different files are in ${FD##*/}/ on this USB drive (car maker's files: don't publish them)"
fi
say "other CarPlay-related files on this car:"
ls /system/lib 2>/dev/null | grep -i -E 'carplay|airplay|iap2' | while read -r f; do
    case "$REF" in *"/system/lib/$f"*) ;; *) say "  /system/lib/$f $(md5of /system/lib/$f)" ;; esac
done
ls /system/app 2>/dev/null | grep -i -E 'dipo|iap2|projection|carplay' | while read -r f; do
    case "$REF" in *"/system/app/$f"*) ;; *) say "  /system/app/$f $(md5of /system/app/$f)" ;; esac
done
say ""

# ---- USB ports and space
say "--- USB (vendor:product, no serials)"
for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] && say "${d##*/} $(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null) $(cat $d/product 2>/dev/null)"
done
say ""
say "--- disk"
df /data 2>/dev/null | while read -r l; do say "$l"; done
say ""
say "end"
sync
toast "차량 정보 수집 완료: USB를 빼도 됩니다"
exit 0
