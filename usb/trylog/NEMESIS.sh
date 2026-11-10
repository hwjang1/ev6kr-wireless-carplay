#!/system/bin/sh
# EV6 KR wireless CarPlay - collect what happened in a connection attempt. READ ONLY, apart from the
# dongle settings files below (EV6KR-TUNE.txt and friends).
# Run it soon after trying (unplug the dongle, plug this stick in). Writes EV6KR-TRYLOG/; the one
# before is kept as EV6KR-TRYLOG.1, .2, ... (the highest number is the newest of those).
# Leave the stick in until the head unit shows "EV6KR 로그 수집 완료" (about a minute): the head unit
# writes to the stick only at each "stage" line, and a stick pulled earlier keeps empty files.
# The dongle settings go first, so even a stick pulled early has set them.
# The logs can hold your phone's name and Bluetooth/Wi-Fi addresses: share them privately only.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib ANDROID_ROOT=/system ANDROID_DATA=/data
[ -n "$BOOTCLASSPATH" ] || export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
H=$(pwd)
O=$H/EV6KR-TRYLOG
if [ -d "$O" ]; then
    N=1
    while [ -e "$O.$N" ]; do N=$((N + 1)); done
    mv "$O" "$O.$N" 2>/dev/null || rm -r "$O" 2>/dev/null
fi
mkdir -p "$O" || exit 1
S=$O/summary.txt
# usb-hotspot-kr (the standalone hotspot mod): its data folder and its runtime folder
HS_MOD=/data/hmgapi/mods/usb-hotspot-kr
HS_DATA=/data/hmgapi/run/usb-hotspot-kr/usbap
HS_RUN=/data/local/tmp/ev6kr_usbap
UT=/data/local/tmp/usbwifi_hotspot
SYSMOD=/sys/module
: > "$S"
say() { echo "$1" >> "$S"; }
grab() { [ -f "$1" ] && cat "$1" > "$O/$2" 2>/dev/null; true; }
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
    true
}
stage() { say "[stage $1 done $(date)]"; sync; }
# putl <line>: the line as it is (mksh's echo would read backslashes in a password line)
if print -r -- "" >/dev/null 2>&1; then
    putl() { print -r -- "$1"; }
else
    PF=printf
    putl() { "$PF" '%s\n' "$1"; }
fi
# (never the kernel command line, which carries the unit's serial number, nor USB serial numbers:
# the kernel logs and every logcat copy go through this)
NOSERIAL='serialno|command line|SerialNumber'

say "ev6kr-trylog 15"
say "date $(date)"
say "stick: $H"
toast "EV6KR 로그 수집 중: '수집 완료' 메시지가 뜰 때까지 스틱을 빼지 마세요"

# ---- 1: dongle settings for the next attempt
# EV6KR-DEBUG-ON / EV6KR-DEBUG-OFF next to this script: turn the debug logcat and sampler on or
# off (ev6kr.usbap.sync's, and usb-hotspot-kr's when that's installed), from the service's next
# round (30 s). Off by default since ev6kr.usbap.sync 0.2.0 / usb-hotspot-kr 0.1.3, which read
# <base>.debug; the 0.1.x versions had it on unless <base>.nodebug: both files are set, so
# either version follows the stick.
DEBUGF=/data/nemesis/ev6kr.usbap.sync.debug
[ -d "$HS_DATA" ] && [ ! -d /data/nemesis/apps/ev6kr.usbap.sync ] && DEBUGF=$HS_DATA/usbap.debug
NODEBUG=${DEBUGF%.debug}.nodebug
[ -f "$H/EV6KR-DEBUG-ON" ] && { : > "$DEBUGF"; rm -f "$NODEBUG"; }
[ -f "$H/EV6KR-DEBUG-OFF" ] && { rm -f "$DEBUGF"; : > "$NODEBUG"; }
# EV6KR-TUNE.txt next to this script: the dongle link settings (key=value lines, see
# ev6kr.usbap.sync scripts/common.sh); EV6KR-TUNE-RESET: back to the package defaults
# (ev6kr.usbap.sync's file, or usb-hotspot-kr's when that runs without it)
TUNEF=/data/nemesis/ev6kr.usbap.sync.tune
[ -d "$HS_DATA" ] && [ ! -d /data/nemesis/apps/ev6kr.usbap.sync ] && TUNEF=$HS_DATA/usbap.tune
TXPG=${TUNEF%.tune}.txp-guard
say "--- dongle settings the last attempt ran with ($TUNEF; package defaults where not set)"
if [ -f "$TUNEF" ]; then
    while read -r TL || [ -n "$TL" ]; do say "$TL"; done < "$TUNEF"
else
    say "(defaults)"
fi
if [ -f "$TXPG" ]; then
    if [ "$(cat "$TXPG")" = "$(cat /proc/sys/kernel/random/boot_id)" ]; then
        say "TX path crash guard: set by this boot (a TX path change less than a minute ago)"
    else
        say "TX path crash guard: left by an earlier boot, which went down within a minute of a TX path change (the test turns itself off when the dongle is back; EV6KR-TUNE-RESET allows it again)"
    fi
fi
# A TX path test the service turned off after the head unit went down during it ("#txpath-off" in
# the tune file) stays off: EV6KR-TUNE.txt is taken without its txpath lines until an
# EV6KR-TUNE-RESET (read first, so both files on the stick = reset, then the new settings).
[ -f "$H/EV6KR-TUNE-RESET" ] && rm -f "$TUNEF" "$TXPG" && say "EV6KR-TUNE-RESET: settings back to the package defaults"
tune_kept_off() {   # the stick's settings, txpath left off
    local _l
    while read -r _l || [ -n "$_l" ]; do
        case "$_l" in txpath=*|'#txpath-off'*) ;; *) echo "$_l" ;; esac
    done < "$H/EV6KR-TUNE.txt"
    while read -r _l; do case "$_l" in '#txpath-off'*) echo "$_l" ;; esac; done < "$TUNEF"
    echo "txpath=driver"
}
if [ -f "$H/EV6KR-TUNE.txt" ]; then
    TXPOFF=""
    if [ -f "$TUNEF" ]; then
        while read -r TL; do case "$TL" in '#txpath-off'*) TXPOFF=1 ;; esac; done < "$TUNEF"
    fi
    if [ -n "$TXPOFF" ]; then
        TK=$(tune_kept_off)
        echo "$TK" > "$TUNEF"
        say "EV6KR-TUNE.txt taken without txpath: the TX path test was turned off after the head unit went down during it (EV6KR-TUNE-RESET on this stick allows it again)"
    else
        cat "$H/EV6KR-TUNE.txt" > "$TUNEF"
        rm -f "$TXPG"
    fi
fi
say "--- dongle settings for the next attempt"
if [ -f "$TUNEF" ]; then
    while read -r TL || [ -n "$TL" ]; do say "$TL"; done < "$TUNEF"
else
    say "(defaults)"
fi
# EV6KR-RFPATH.txt next to this script ("1T2R" or "default"): the 88x2bu dongle's transmit chains:
# the driver's rtw_rf_path parameter now (the driver reads it each time the dongle is plugged in, so
# the dongle plugged in after this stick has it) and usbwifi.hotspot's MODULE_ARGS (config/hotspot.conf)
# for later boots.
# 1T2R = the driver's rtw_rf_path=1: everything goes out on chain A, both chains still receive (the
# 13th attempt: frames sent on chain B were lost, received ones weren't). "default" takes it out.
# usbwifi.hotspot retries without its arguments if the driver refuses one.
UA=/data/nemesis/apps/usbwifi.hotspot
[ -d "$UA" ] || UA=/data/nemesis/packages/usbwifi.hotspot
HC=$UA/config/hotspot.conf
if [ -f "$H/EV6KR-RFPATH.txt" ] && [ -f "$HC" ]; then
    RFW=""
    while read -r TL || [ -n "$TL" ]; do case "$TL" in 1T2R|1t2r) RFW=1 ;; default|DEFAULT) RFW=d ;; esac; done < "$H/EV6KR-RFPATH.txt"
    if [ -n "$RFW" ]; then
        [ -f "$HC.ev6kr-orig" ] || cat "$HC" > "$HC.ev6kr-orig"
        : > "$HC.ev6kr-tmp"
        RFSEEN=""
        while IFS= read -r TL || [ -n "$TL" ]; do
            case "$TL" in
                MODULE_ARGS=*)
                    RFSEEN=1
                    RFV=${TL#MODULE_ARGS=}
                    case "$RFV" in \"*\") RFV=${RFV#\"}; RFV=${RFV%\"} ;; \'*\') RFV=${RFV#\'}; RFV=${RFV%\'} ;; esac
                    RFO=""
                    for RFA in $RFV; do case "$RFA" in rtw_rf_path=*) ;; *) RFO="$RFO${RFO:+ }$RFA" ;; esac; done
                    [ "$RFW" = 1 ] && RFO="$RFO rtw_rf_path=1"
                    putl "MODULE_ARGS=\"$RFO\"" >> "$HC.ev6kr-tmp" ;;
                *) putl "$TL" >> "$HC.ev6kr-tmp" ;;
            esac
        done < "$HC"
        RFP=$SYSMOD/88x2bu/parameters/rtw_rf_path
        RFNOW="not loaded"
        if [ -f "$RFP" ]; then
            if [ "$RFW" = 1 ]; then echo 1 > "$RFP" 2>/dev/null; else echo 8 > "$RFP" 2>/dev/null; fi   # 8: RF_TYPE_MAX, the chip's own
            RFNOW=$(cat "$RFP" 2>/dev/null)
        fi
        if [ -n "$RFSEEN" ]; then
            cat "$HC.ev6kr-tmp" > "$HC"
            if [ "$RFW" = 1 ]; then
                say "EV6KR-RFPATH.txt: 88x2bu dongle set to 1T2R: driver parameter rtw_rf_path now $RFNOW (the dongle plugged in after this stick takes it, no reboot needed) and rtw_rf_path=1 in MODULE_ARGS for later boots"
            else
                say "EV6KR-RFPATH.txt: 88x2bu dongle back to its own transmit chains: driver parameter rtw_rf_path now $RFNOW, rtw_rf_path left out of MODULE_ARGS"
            fi
        else
            say "EV6KR-RFPATH.txt: no MODULE_ARGS line in $HC, nothing changed"
        fi
        rm -f "$HC.ev6kr-tmp"
    fi
fi
[ -f "$HC" ] && while IFS= read -r TL || [ -n "$TL" ]; do case "$TL" in MODULE_ARGS=*|AUTO_UPDATE=*|ENABLE_LTE_NAT=*) say "usbwifi.hotspot $TL" ;; esac; done < "$HC"
if [ -f "$DEBUGF" ]; then
    say "debug logging: on (an EV6KR-DEBUG-OFF file on this stick turns it off)"
elif [ -f "$NODEBUG" ]; then
    say "debug logging: off (an EV6KR-DEBUG-ON file on this stick turns it on)"
else
    say "debug logging: off from 0.2.0 on (0.1.x: on) (an EV6KR-DEBUG-ON file on this stick turns it on)"
fi
stage 1
say ""

# ---- 2: the state now
say "ro.build.product=$(getprop ro.build.product)"
for p in persist.ium.support persist.sys.iap2.wifi persist.iap2.iden.wireless persist.service.adb.tcp.enable sys.usb.config; do
    say "$p=$(getprop $p)"
done
say "up $(cat /proc/uptime)"
say ""
# disk space (toolbox df: sizes only) and the log files the packages keep, with their sizes
say "--- disk"
{ /system/bin/df /data /cache /system || df /data; } >> "$S" 2>&1
ls -l /data/nemesis/ev6kr.usbap.sync.* /data/hmgapi/logs/hmgapi >> "$S" 2>&1
say ""
say "--- NEMESIS packages"
nemesis pkg-list >> "$S" 2>&1
say ""
say "--- usbwifi.hotspot"
if [ -f "$UA/config/hotspot.conf" ]; then
    say "== $UA/config/hotspot.conf"
    while read -r _l || [ -n "$_l" ]; do
        case "$_l" in AP_PASS=*|STA_*=*) say "${_l%%=*}=(hidden)" ;; *) say "$_l" ;; esac
    done < "$UA/config/hotspot.conf"
fi
ls -l "$UT" >> "$S" 2>&1
# the daemons by their pid files (alive or not, and what each one waits on) and every process stuck on
# the disk (state D: a hung sync or a USB device that went away under it)
for pf in "$UT"/*.pid /data/nemesis/ev6kr.usbap.sync.logcat.pid; do
    [ -f "$pf" ] || continue
    _p=$(cat "$pf" 2>/dev/null)
    if [ -n "$_p" ] && [ -d "/proc/$_p" ]; then
        say "${pf##*/}: $_p alive, waits on $(cat /proc/$_p/wchan 2>/dev/null), $(cat /proc/$_p/cmdline 2>/dev/null)"
    else
        say "${pf##*/}: ${_p:-empty} NOT running"
    fi
done
DPID=$(cat "$UT/daemon.pid" 2>/dev/null)
for p in /proc/[0-9]*; do
    read -r _st 2>/dev/null < "$p/stat" || continue
    _r=${_st##*\) }
    set -- $_r
    _c=${_st#*\(}; _c=${_c%\)*}
    if [ "$1" = D ] || { [ -n "$DPID" ] && [ "$2" = "$DPID" ]; }; then
        _w=""; read -r _w 2>/dev/null < "$p/wchan"
        say "process ${p##*/} ($_c) state $1 parent $2 waits on $_w"
    fi
done
for f in "$UT"/*lease*; do [ -f "$f" ] && { say "== $f"; cat "$f" >> "$S"; }; done
ps 2>/dev/null | grep -E 'hostapd|dnsmasq|mdnsd|dipo|iap2|logcat|usbwifi|app_process' >> "$S"
say "--- dongle driver (loaded version and build; usbwifi.hotspot loads modules/88x2bu_<platform>.ko before 88x2bu.ko)"
say "88x2bu $(cat /sys/module/88x2bu/version 2>/dev/null) srcversion $(cat /sys/module/88x2bu/srcversion 2>/dev/null) / 8851bu $(cat /sys/module/8851bu/version 2>/dev/null)"
for k in rtw_rf_path rtw_tx_nss rtw_rx_nss rtw_country_code; do
    [ -f "$SYSMOD/88x2bu/parameters/$k" ] && say "88x2bu $k=$(cat "$SYSMOD/88x2bu/parameters/$k" 2>/dev/null)"
done
LASTLOAD=""
[ -f "$UT/daemon.log" ] && while IFS= read -r TL; do case "$TL" in *"kernel module 88x2bu"*|*"insmod 88x2bu"*) LASTLOAD=$TL ;; esac; done < "$UT/daemon.log"
say "last 88x2bu load: $LASTLOAD"
ls -l "$UA/modules" >> "$S" 2>&1
grep -i -E "rtw|88x2bu|8822b|8851" "$UT/insmod.log" >> "$S" 2>/dev/null
say "USB devices now (vendor:product, no serials)"
for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] && say "${d##*/} $(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null) $(cat $d/product 2>/dev/null)"
done
say "USB Wi-Fi driver bindings: $(ls -d /sys/bus/usb/drivers/rtl*/*:* 2>/dev/null)"
# a ZeroCD dongle's CD is ejected through a SCSI generic node (ev6kr.usbap.sync 0.1.11): which ones
# exist now (this stick has one) and what each is
say "SCSI generic nodes: $(ls /dev/sg* 2>/dev/null)"
for g in /sys/class/scsi_generic/sg*; do
    [ -e "$g" ] && say "${g##*/}: $(cat "$g/device/vendor" 2>/dev/null) $(cat "$g/device/model" 2>/dev/null)"
done
grep -a -E "dongle CD-ROM|USB device at" /data/nemesis/ev6kr.usbap.sync.log /data/nemesis/ev6kr.usbap.sync.log.old 2>/dev/null | while read -r TL; do say "$TL"; done
say "--- network"
netcfg 2>/dev/null | while read -r _if _st _ip _rest; do case "$_if" in rmnet*) say "$_if $_st (mobile data)" ;; ''|lo) ;; *) say "$_if $_st $_ip" ;; esac; done
for i in /sys/class/net/rtwlan*; do [ -e "$i" ] && say "${i##*/}: ifindex $(cat $i/ifindex 2>/dev/null), $(cat $i/operstate 2>/dev/null)"; done
grep -E 'Inter|face|rtwlan' /proc/net/dev >> "$S" 2>&1
netstat 2>/dev/null | grep -E 'LISTEN|:5353|:7000|ESTABLISHED' >> "$S"
# did a phone join the hotspot: neighbours, DHCP leases, traffic on the USB Wi-Fi interfaces
say "--- neighbours (IPv4, IPv6)"
ip neigh show >> "$S" 2>&1
ip -6 neigh show >> "$S" 2>&1
say "--- routes"
ip route show >> "$S" 2>&1
if [ -d "$HS_MOD" ]; then
    say "usb-hotspot-kr modules:"
    ls -l "$HS_MOD/modules" >> "$S" 2>&1
    cat "$HS_MOD/modules"/*.srcversion >> "$S" 2>/dev/null
    grep -v '^$' "$HS_RUN/insmod.log" >> "$S" 2>/dev/null
    say "usb-hotspot-kr interface: $(cat "$HS_RUN/iface" 2>/dev/null)"
fi
# the hotspot's hostapd: its version (decides WMM/802.11n defaults) and settings, passphrase hidden
say "--- hostapd"
say "$(/system/bin/hostapd -v 2>&1 | grep -i hostapd)"
for f in "$UT/hostapd.conf" "$HS_RUN/hostapd.conf"; do
    [ -f "$f" ] || continue
    say "== $f"
    while read -r _l; do case "$_l" in wpa_passphrase=*|wpa_psk=*) say "${_l%%=*}=(hidden)" ;; *) say "$_l" ;; esac; done < "$f"
done
[ -f "$HS_RUN/dhcp/dnsmasq.leases" ] && { say "== $HS_RUN/dhcp/dnsmasq.leases"; cat "$HS_RUN/dhcp/dnsmasq.leases" >> "$S"; }
say ""
say "--- HMG-API"
say "$(hmgapid ping 2>&1)"
# its boot guard: 3 zygote starts in a row that didn't last 2 minutes (quick reboots) turn the hooks
# off until hook/starts goes back to 0. EV6KR-HOOKS-RESET next to this script resets it (the reset
# HMG-API's troubleshooting page gives), for the next boot.
say "hooks: enable $([ -e /data/hmgapi/hook/enable ] && echo yes || echo no), disable file $([ -e /data/hmgapi/hook/disable ] && echo yes || echo no), starts $(cat /data/hmgapi/hook/starts 2>/dev/null)"
dmesg 2>/dev/null | grep 'hmgapi-hook' | grep -v -i -E "$NOSERIAL" >> "$S"
if [ -f "$H/EV6KR-HOOKS-RESET" ]; then
    echo 0 > /data/hmgapi/hook/starts && say "hooks: boot guard reset (starts 0): hooks on from the next boot"
fi
hmgapid engine map >> "$S" 2>&1
hmgapid engine status >> "$S" 2>&1
say "--- HMG-API services"
if [ -f /data/hmgapi/state/services.status ]; then
    cat /data/hmgapi/state/services.status >> "$S" 2>&1
else
    say "none running"
fi
say "--- feature flags"
grep -n -E 'carplay_wireless|androidauto_wireless|wifihotspot' "$(getprop ro.mobis.targetdir)/featurexml.cfg" >> "$S" 2>&1
ls /system/etc/permissions 2>/dev/null | grep -E 'carplay|androidauto|wifihotspot' >> "$S"
stage 2

# ---- 3: the small logs that outlive the attempt
grab /data/nemesis/ev6kr.usbap.sync.log apsync.log
grab /data/nemesis/ev6kr.usbap.sync.log.old apsync.old.log
grab "$UT/daemon.log" usbwifi-daemon.log
grab "$UT/hostapd.log" usbwifi-hostapd.log
grab "$UT/dnsmasq.log" usbwifi-dnsmasq.log
grab "$UT/ui.log" usbwifi-ui.log
grab /data/hmgapi/logs/hmgapi/log.log hmgapi-log.txt
grab /data/hmgapi/logs/hmgapi/log.log.1 hmgapi-log.1.txt
dmesg 2>/dev/null | grep -i -E 'rtw|88x2bu|8851bu|usb|hub|over-current|overcurrent|ehci|vbus|hmgapi-hook|panic|oops|unable to handle|internal error|bug:|hung|blocked for' \
    | grep -v -i -E "$NOSERIAL" > "$O/dmesg-usb.txt"
# the car's hook maps (names only): which points the unit found and which it missed
for f in /data/hmgapi/maps/*/*/*/*/car.json; do
    [ -f "$f" ] || continue
    _m=${f#/data/hmgapi/maps/}; _m=${_m%/car.json}
    mkdir -p "$O/maps/$_m" && cp "${f%/car.json}"/*.json "$O/maps/$_m/" 2>/dev/null
done
[ -f /data/hmgapi/state/map-check.json ] && cat /data/hmgapi/state/map-check.json > "$O/maps/map-check.json" 2>/dev/null
# routing and firewall as the hotspot sees them (read only), the network counters now
{
    echo "--- softnet_stat (per CPU: processed dropped squeezed ...)"; cat /proc/net/softnet_stat
    echo "--- snmp"; cat /proc/net/snmp
    echo "--- netstat"; cat /proc/net/netstat
    for k in netdev_max_backlog netdev_budget rmem_max wmem_max; do echo "net.core.$k=$(cat /proc/sys/net/core/$k)"; done
    echo "tcp_rmem=$(cat /proc/sys/net/ipv4/tcp_rmem)"
    for k in dirty_expire_centisecs dirty_writeback_centisecs dirty_ratio dirty_background_ratio; do echo "vm.$k=$(cat /proc/sys/vm/$k)"; done
    echo "--- load"; cat /proc/loadavg
    echo "--- mounts (USB)"; grep -i -E 'usb|media_rw|vfat' /proc/mounts
    echo "--- ip rule"; ip rule show
    echo "--- ip route (main, 60, 61)"; ip route show; ip route show table 60; ip route show table 61
    echo "--- udp sockets"; cat /proc/net/udp
    echo "--- iptables"; iptables -S
    echo "--- ip6tables"; ip6tables -S
} > "$O/net-now.txt" 2>&1
# an earlier boot's kernel log, where this unit may keep it (a kernel panic shows there): pstore,
# last_kmsg, Android's dontpanic files, and what the boot receiver put in DropBox from them
mkdir -p "$O/lastboot"
for f in /sys/fs/pstore/* /proc/last_kmsg /data/dontpanic/*; do
    [ -f "$f" ] || continue
    grep -v -i -E "$NOSERIAL" "$f" > "$O/lastboot/${f##*/}.txt" 2>/dev/null
done
# DropBox: only kernel panic entries (this unit had none on 2026-11-08, and ~1800 SYSTEM_BOOT ones
# that made trylog 6 take minutes; those aren't touched)
for f in /data/system/dropbox/SYSTEM_LAST_KMSG* /data/system/dropbox/APANIC*; do
    [ -f "$f" ] || continue
    case "$f" in
        *.gz) gzip -d -c "$f" 2>/dev/null | grep -v -i -E "$NOSERIAL" > "$O/lastboot/dropbox-${f##*/}.txt" ;;
        *) grep -v -i -E "$NOSERIAL" "$f" > "$O/lastboot/dropbox-${f##*/}" ;;
    esac
done
for f in /proc/last_kmsg /sys/fs/pstore /data/dontpanic; do [ -e "$f" ] && say "kept kernel log place: $f"; done
stage 3

# ---- 4: the big ones: network samples, the debug logcat (newest first), what logcat holds now
grab /data/nemesis/ev6kr.usbap.sync.netsample.txt netsample.txt
grab /data/nemesis/ev6kr.usbap.sync.netsample.txt.1 netsample.1.txt
logcat -d -v time 2>&1 | grep -v -i -E "$NOSERIAL" > "$O/logcat-now.txt"
D=/data/nemesis/ev6kr.usbap.sync.logcat.txt
for n in "" .1 .2 .3 .4 .5 .6 .7 .8 .9 .10; do
    [ -f "$D$n" ] && grep -v -i -E "$NOSERIAL" "$D$n" > "$O/debug-${D##*/}$n" 2>/dev/null
done
stage 4a
# usb-hotspot-kr (only while it's installed): its log, the service output HMG-API keeps, hostapd's
# and dnsmasq's, its sampler, its debug logcat
if [ -d "$HS_MOD" ]; then
    mkdir -p "$O/usbap"
    grab "$HS_DATA/usbap.log" usbap/usbap.log
    grab "$HS_DATA/usbap.log.old" usbap/usbap.old.log
    grab /data/hmgapi/logs/usb-hotspot-kr/usbap.log usbap/service-output.log
    grab "$HS_RUN/hostapd.log" usbap/hostapd.log
    grab "$HS_RUN/dhcp/dnsmasq.log" usbap/dnsmasq.log
    grab "$HS_RUN/insmod.log" usbap/insmod.log
    grab "$HS_DATA/usbap.netsample.txt.1" usbap/netsample.1.txt
    grab "$HS_DATA/usbap.netsample.txt" usbap/netsample.txt
    for f in "$HS_DATA"/usbap.logcat.txt*; do [ -f "$f" ] && grep -v -i -E "$NOSERIAL" "$f" > "$O/usbap/debug-${f##*/}" 2>/dev/null; done
fi
# the kernel's build config (model-wide, no per-car data): driver/build.sh builds the dongle driver for it
[ -f /proc/config.gz ] && cat /proc/config.gz > "$O/kernel-config.gz" 2>/dev/null
say ""
say "end"
stage 4
toast "EV6KR 로그 수집 완료: 스틱을 빼도 됩니다"
exit 0
