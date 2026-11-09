#!/system/bin/sh
# ev6kr.usbap.sync - shared by the service, the app and the install scripts.
#
# Keeps the USB Wi-Fi package's hotspot (usbwifi.hotspot, config/hotspot.conf) on the
# stock CarPlay hotspot settings: ConnectivitySSID / ConnectivityPSK and the channel from
# /data/misc/wifi/softap.conf, which the iAP2 server hands to the iPhone for wireless
# CarPlay. Only AP_SSID, AP_PASS, AP_HW_MODE, AP_CHANNEL and ENABLE_LTE_NAT are touched; the
# first values found are saved and put back at uninstall.
#
# ENABLE_LTE_NAT=1 (usbwifi.hotspot's default) shares the car's LTE with the hotspot: NAT to
# rmnet+ and a gateway plus DNS in the DHCP lease, so the iPhone takes the CarPlay Wi-Fi for
# internet and sends its own traffic over the car's modem. The stock CarPlay hotspot has no
# internet: the phone keeps its cellular data and uses the Wi-Fi for CarPlay only. 0 here, as stock
# (lte_share=1 in the tune file shares it again).
#
# The unit's shell is mksh with toolbox only: no printf, sed, awk, head, tail, cut, tr.
# (EV6KR_TEST_PATH: the off-car test's stand-ins, tests/apsync-test.sh; unset on the unit)
export PATH=${EV6KR_TEST_PATH:+$EV6KR_TEST_PATH:}/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar

PKG=ev6kr.usbap.sync
if [ -z "$APP_DIR" ]; then
    if [ -d "/data/nemesis/apps/$PKG" ]; then APP_DIR=/data/nemesis/apps/$PKG; else APP_DIR=/data/nemesis/packages/$PKG; fi
fi
NEMESIS_DIR=${NEMESIS_DIR:-/data/nemesis}
JAR=$APP_DIR/bin/softapconf.jar
LOG=$NEMESIS_DIR/$PKG.log
BACKUP_DIR=$NEMESIS_DIR/backup/$PKG
DISABLED=$NEMESIS_DIR/$PKG.disabled
# the stock projection passphrase is replaced by letters and digits when it has symbols (the
# original is kept here and put back at uninstall); an empty .keeppsk file leaves it as it is
PSK_BACKUP=$BACKUP_DIR/projection.psk
KEEPPSK=$NEMESIS_DIR/$PKG.keeppsk
USB_PKG=usbwifi.hotspot
USB_TMP=${USB_TMP:-/data/local/tmp/usbwifi_hotspot}
SOFTAP=${SOFTAP:-/data/misc/wifi/softap.conf}
KEYS="AP_SSID AP_PASS AP_HW_MODE AP_CHANNEL ENABLE_LTE_NAT"
PROC=${PROC:-/proc}
NL='
'
RT_BASE=$NEMESIS_DIR/$PKG
RT_BIN=$APP_DIR/bin
SAY_TAG=EV6KR-APSYNC
. "$APP_DIR/scripts/rtwlan.sh"
# block ack from the phone left to usbwifi.hotspot's v5.8.7.1 driver (it runs fine with it and the
# screen stream gets more through: rtwlan.sh's tuning notes); rx_ampdu=0 in the tune file refuses it
TUNE_DEFAULTS="rx_ampdu=auto txpath=driver lte_share=0"

# the USB Wi-Fi package's config file (it may not exist yet)
usb_conf() {
    local _d
    for _d in "$NEMESIS_DIR/apps/$USB_PKG" "$NEMESIS_DIR/packages/$USB_PKG"; do
        if [ -d "$_d" ]; then
            putline "$_d/config/hotspot.conf"
            return 0
        fi
    done
    return 1
}

# conf_value <file> <key>: the last "<key>=" value (as the daemon and the dashboard both
# end up using it), one layer of quotes taken off
conf_value() {
    local _l _v _hit=1
    [ -f "$1" ] || return 1
    while IFS= read -r _l || [ -n "$_l" ]; do
        case "$_l" in
            "$2="*)
                _v=${_l#*=}
                case "$_v" in
                    \"*\") _v=${_v#\"}; _v=${_v%\"} ;;
                    \'*\') _v=${_v#\'}; _v=${_v%\'} ;;
                esac
                _hit=0
                ;;
        esac
    done < "$1"
    [ $_hit = 0 ] && putline "$_v"
    return $_hit
}

# conf_line <file> <key>: the first "<key>=" line as written, or nothing
conf_line() {
    local _l
    [ -f "$1" ] || return 1
    while IFS= read -r _l || [ -n "$_l" ]; do
        case "$_l" in "$2="*) putline "$_l"; return 0 ;; esac
    done < "$1"
    return 1
}

# read_wanted: WANT = the AP_* lines for the stock CarPlay hotspot, read the way the iAP2 server
# reads them (WifiManager.getWifiApConfiguration; softap.conf if that's not up yet). WANT_RC: 0 the
# live settings, 7 softap.conf only (read again next pass), 8 the passphrase was just replaced
read_wanted() {
    local _bk=""
    if [ ! -f "$KEEPPSK" ]; then
        mkdir -p "$BACKUP_DIR" 2>/dev/null
        _bk=$PSK_BACKUP
    fi
    WANT=$(CLASSPATH="$JAR" app_process /system/bin ev6kr.cpw.SoftApConf usbconf "$SOFTAP" $_bk 2>>"$LOG")
    WANT_RC=$?
    [ -f "$PSK_BACKUP" ] && chmod 600 "$PSK_BACKUP" 2>/dev/null
    case "$WANT" in AP_SSID=*) return 0 ;; esac
    WANT=""
    return 1
}

# rewrite_conf <file> <set lines> <drop keys>: each "<KEY>=..." line in <set lines> replaces
# the file's first line for that key (later duplicates dropped) or is added; keys in <drop
# keys> are removed. Other lines stay as they are. Returns 0 when the file changed, 1 when
# it already matched, 2 on a write error.
rewrite_conf() {
    local _f="$1" _set="$2" _drop="$3" _tmp="$1.ev6kr.tmp" _l _w _k _out _seen=" " _changed=1 _ifs="$IFS"
    : > "$_tmp" || return 2
    set -f
    if [ -f "$_f" ]; then
        while IFS= read -r _l || [ -n "$_l" ]; do
            _out=$_l
            IFS=$NL
            for _w in $_set; do
                _k=${_w%%=*}
                case "$_l" in
                    "$_k="*)
                        case "$_seen" in
                            *" $_k "*) _out="" ;;
                            *) _out=$_w; _seen="$_seen$_k " ;;
                        esac
                        ;;
                esac
            done
            IFS=$_ifs
            for _k in $_drop; do
                case "$_l" in "$_k="*) _out="" ;; esac
            done
            if [ -z "$_out" ] && [ -n "$_l" ]; then
                _changed=0
                continue
            fi
            [ "$_out" = "$_l" ] || _changed=0
            putline "$_out" >> "$_tmp" || { IFS=$_ifs; set +f; rm -f "$_tmp"; return 2; }
        done < "$_f"
    fi
    IFS=$NL
    for _w in $_set; do
        _k=${_w%%=*}
        case "$_seen" in
            *" $_k "*) ;;
            *) putline "$_w" >> "$_tmp"; _seen="$_seen$_k "; _changed=0 ;;
        esac
    done
    IFS=$_ifs
    set +f
    if [ $_changed = 0 ]; then
        chmod 644 "$_tmp" 2>/dev/null
        mv "$_tmp" "$_f" || { rm -f "$_tmp"; return 2; }
        return 0
    fi
    rm -f "$_tmp"
    return 1
}

# backup_once <file>: the first time, save each managed key's line (or that it was absent); a key a
# later version added (ENABLE_LTE_NAT in 0.1.12) is saved as it is then, before it's first changed
backup_once() {
    local _k _l _have=" "
    if [ -f "$BACKUP_DIR/hotspot.keys" ]; then
        while IFS= read -r _l || [ -n "$_l" ]; do
            case "$_l" in "#absent "*) _have="$_have${_l#\#absent } " ;; ?*=*) _have="$_have${_l%%=*} " ;; esac
        done < "$BACKUP_DIR/hotspot.keys"
        for _k in $KEYS; do
            case "$_have" in *" $_k "*) continue ;; esac
            if _l=$(conf_line "$1" "$_k"); then
                putline "$_l" >> "$BACKUP_DIR/hotspot.keys" || return 1
            else
                putline "#absent $_k" >> "$BACKUP_DIR/hotspot.keys" || return 1
            fi
            say "saved the USB hotspot's own $_k for uninstall"
        done
        return 0
    fi
    mkdir -p "$BACKUP_DIR" || return 1
    : > "$BACKUP_DIR/hotspot.keys.tmp" || return 1
    for _k in $KEYS; do
        if _l=$(conf_line "$1" "$_k"); then
            putline "$_l" >> "$BACKUP_DIR/hotspot.keys.tmp"
        else
            putline "#absent $_k" >> "$BACKUP_DIR/hotspot.keys.tmp"
        fi
    done
    mv "$BACKUP_DIR/hotspot.keys.tmp" "$BACKUP_DIR/hotspot.keys" || { rm -f "$BACKUP_DIR/hotspot.keys.tmp"; return 1; }
    say "saved the USB hotspot's own settings for uninstall"
}

restart_usb_hotspot() {
    [ -d "$USB_TMP" ] || return 0
    putline 1 > "$USB_TMP/force_restart" 2>/dev/null
    true
}

# sync_once: 0 in sync (or nothing to do), 1 not possible now
sync_once() {
    local _conf _mode _rc _ssid _nat0 _nat
    _conf=$(usb_conf) || { note "usbwifi.hotspot is not installed"; return 1; }
    _mode=$(conf_value "$_conf" WIFI_MODE)
    if [ "$_mode" = sta ]; then
        note "usbwifi.hotspot is in client (STA) mode: left alone (wireless CarPlay needs its AP mode)"
        return 0
    fi
    if [ -z "$WANT" ] || [ "$SOFTAP_SIG" != "$(ls -l "$SOFTAP" 2>/dev/null)" ]; then
        SOFTAP_SIG=$(ls -l "$SOFTAP" 2>/dev/null)
        read_wanted || { note "can't read the stock CarPlay hotspot settings ($SOFTAP)"; return 1; }
        case $WANT_RC in
            7) SOFTAP_SIG="" ;;
            8) say "stock CarPlay passphrase replaced by letters and digits (the phone gets it on its next connection)"
               SOFTAP_SIG=$(ls -l "$SOFTAP" 2>/dev/null) ;;
        esac
    fi
    mkdir -p "${_conf%/*}" 2>/dev/null
    backup_once "$_conf" || { note "can't save a backup in $BACKUP_DIR"; return 1; }
    _nat0=$(conf_value "$_conf" ENABLE_LTE_NAT)
    rewrite_conf "$_conf" "$(tune_want)" ""
    _rc=$?
    _ssid=$(conf_value "$_conf" AP_SSID)
    _nat=$(conf_value "$_conf" ENABLE_LTE_NAT)
    if [ "$_nat" != "$_nat0" ]; then
        case "$_nat" in
            0) say "car LTE sharing on the USB hotspot off (ENABLE_LTE_NAT ${_nat0:-unset} -> 0): the phone keeps its own cellular data, as with the stock CarPlay hotspot" ;;
            *) say "car LTE sharing on the USB hotspot on (ENABLE_LTE_NAT ${_nat0:-unset} -> $_nat, lte_share=1 in the tune file)" ;;
        esac
    fi
    case $_rc in
        0) say "USB hotspot set to the stock CarPlay hotspot (SSID $_ssid), restarting it"
           LAST_NOTE=""
           restart_usb_hotspot ;;
        1) note "USB hotspot already on the stock CarPlay hotspot (SSID $_ssid)" ;;
        *) note "can't write $_conf"; return 1 ;;
    esac
    return 0
}

# usb_hotspot_check: usbwifi.hotspot's daemon doesn't notice a USB bus reset or a quick replug:
# hostapd stays on the interface that went away (it lingers, still holding 192.168.43.1) and the
# new rtwlanN never gets the hotspot. Its driver build has no netdev parent (no
# /sys/class/net/rtwlanN/device), so a dongle on the bus is a USB interface bound to a Realtek
# driver (/sys/bus/usb/drivers/rtl*/<bus-port:config.if>), and the live interface is the one the
# daemon itself picks: the rtwlan with the highest ifindex. In AP mode, with a dongle bound but
# hostapd not running on that interface, HEALTH_THRESHOLD checks in a row (3: ~1.5 min, longer
# than the daemon's own bring-up) -> the other rtwlan interfaces lose their addresses and the
# daemon is asked to restart; then HEALTH_COOLDOWN checks (4: ~2 min) of rest.
USB_WORK=${USB_WORK:-/data/misc/wifi/usbwifi_hotspot}
HEALTH_THRESHOLD=${HEALTH_THRESHOLD:-3}
HEALTH_COOLDOWN=${HEALTH_COOLDOWN:-4}
HEALTH_BAD=0
HEALTH_COOL=0

usb_hotspot_check() {
    local _conf _mode _if _new="" _pid="" _hif=""
    if [ "$HEALTH_COOL" -gt 0 ]; then
        HEALTH_COOL=$((HEALTH_COOL - 1))
        return 0
    fi
    _conf=$(usb_conf) || return 0
    _mode=$(conf_value "$_conf" WIFI_MODE)
    if [ -n "$_mode" ] && [ "$_mode" != ap ]; then
        HEALTH_BAD=0
        return 0
    fi
    if ! usb_dongle_bound; then
        HEALTH_BAD=0
        return 0
    fi
    _new=$(newest_rtwlan)
    [ -f "$USB_TMP/hostapd.pid" ] && read -r _pid < "$USB_TMP/hostapd.pid"
    _hif=$(conf_value "$USB_WORK/hostapd.conf" interface)
    if [ -n "$_new" ] && [ -n "$_pid" ] && [ -d "$PROC/$_pid" ] && [ "$_hif" = "$_new" ]; then
        HEALTH_BAD=0
        return 0
    fi
    HEALTH_BAD=$((HEALTH_BAD + 1))
    [ "$HEALTH_BAD" -ge "$HEALTH_THRESHOLD" ] || return 0
    HEALTH_BAD=0
    HEALTH_COOL=$HEALTH_COOLDOWN
    for _if in "$SYSNET"/rtwlan*; do
        [ -e "$_if" ] || continue
        [ "${_if##*/}" = "$_new" ] && continue
        ip addr flush dev "${_if##*/}" >/dev/null 2>&1
    done
    say "USB hotspot isn't running on the dongle's interface (newest ${_new:-none}, hostapd ${_pid:-none} on ${_hif:-none}): other rtwlan addresses cleared, asking usbwifi.hotspot to restart it"
    restart_usb_hotspot
}

tune_want() {   # tune_want: $WANT with the tuned channel and the LTE sharing (call it in $(...): it sets -f and IFS)
    local _c _l _out="" _n
    _n=$(tune_get lte_share)
    case "$_n" in 1) ;; *) _n=0 ;; esac
    _c=$(tune_get channel)
    case "$_c" in 36|40|44|48|149|153|157|161|165) ;; *) putline "$WANT${NL}ENABLE_LTE_NAT=$_n"; return 0 ;; esac
    set -f
    IFS=$NL
    for _l in $WANT; do
        case "$_l" in
            AP_CHANNEL=*) _l="AP_CHANNEL=$_c" ;;
            AP_HW_MODE=*) _l="AP_HW_MODE=a" ;;
        esac
        _out="$_out$_l$NL"
    done
    putline "${_out}ENABLE_LTE_NAT=$_n"
}

# is_update: NEMESIS unpacks the new version into its stage folder before it runs the old
# version's preuninstall, and gives the hook no other sign of an update. Seen there, the old
# version leaves the hotspot as it is: putting the USB package's own SSID back only for the new
# version to set the CarPlay one again restarted the hotspot twice and showed phones both names.
NEMESIS_STAGE=${NEMESIS_STAGE:-/data/local/tmp/nemesis/stage}
is_update() {
    local _f
    for _f in "$NEMESIS_STAGE/$PKG/NEMESIS.data" "$NEMESIS_STAGE/$PKG"/*/NEMESIS.data; do
        [ -f "$_f" ] && return 0
    done
    return 1
}

# restore_psk: put the stock projection passphrase back (uninstall)
restore_psk() {
    [ -f "$PSK_BACKUP" ] || return 0
    if CLASSPATH="$JAR" app_process /system/bin ev6kr.cpw.SoftApConf restore "$SOFTAP" "$PSK_BACKUP" >>"$LOG" 2>&1; then
        say "stock CarPlay passphrase put back"
    else
        say "FAIL: couldn't put the stock CarPlay passphrase back (saved in $PSK_BACKUP)"
        return 1
    fi
}

# restore_usb_conf: put the saved lines back (uninstall)
restore_usb_conf() {
    local _conf _l _set="" _drop=""
    [ -f "$BACKUP_DIR/hotspot.keys" ] || { say "no saved USB hotspot settings: nothing to put back"; return 0; }
    _conf=$(usb_conf) || return 0
    while IFS= read -r _l || [ -n "$_l" ]; do
        case "$_l" in
            "#absent "*) _drop="$_drop ${_l#\#absent }" ;;
            ?*=*) _set="$_set$_l$NL" ;;
        esac
    done < "$BACKUP_DIR/hotspot.keys"
    rewrite_conf "$_conf" "$_set" "$_drop"
    case $? in
        0) say "put the USB hotspot's own settings back"; restart_usb_hotspot ;;
        1) say "USB hotspot settings were already its own" ;;
        *) say "FAIL: can't write $_conf"; return 1 ;;
    esac
    return 0
}
