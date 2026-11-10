#!/system/bin/sh
# usb-hotspot-kr (HMG-API mod, root service): the hotspot wireless CarPlay joins on a Korean EV6,
# which has no Wi-Fi chip, on a USB Wi-Fi dongle. Standalone: no usbwifi.hotspot, no
# ev6kr.usbap.sync. The stock CarPlay hotspot settings (ConnectivitySSID/PSK and the channel in
# /data/misc/wifi/softap.conf, what the iAP2 server hands the iPhone) go straight into hostapd.
#
#   driver   modules/88x2bu_<ro.board.platform>.ko (driver/build.sh), loaded as soon as the service
#            starts at boot, before the dongle shows up: the driver then takes the dongle as it
#            appears, before the head unit's projection stack opens it to ask for accessory
#            (AOA) mode (loaded 2 s after the dongle, its chip didn't answer: "Chip id is
#            undefined", 8th car test). Power saving and NAPI/GRO off, interfaces rtwlan%d
#   AP       the stock /system/bin/hostapd (nl80211) on the newest rtwlan interface, 192.168.43.1/24
#   DHCP     the stock /system/bin/dnsmasq, DHCP only (no DNS, no gateway: the phone keeps its
#            own mobile data), 192.168.43.10-100
#   watch    every 3 s: dongle pulled or plugged, hostapd/dnsmasq gone, settings changed
#   extras   the shared dongle side (scripts/rtwlan.sh): receive backlog, network sampler, debug
#            logcat, TX path/power tuning; left to ev6kr.usbap.sync when that is installed
#
# Files: $DATA (HMGAPI_DATA): usbap.log(.old), usbap.tune, usbap.netsample.txt, usbap.logcat.txt,
# usbap.debug (debug logging on, from the trylog stick's EV6KR-DEBUG-ON), backup/.
# $RUN (/data/local/tmp/ev6kr_usbap, readable by DiPO, where the CarPlay mod looks):
# hostapd.conf (600), hostapd.pid/.log, iface, insmod.log, dhcp/ (dnsmasq's).
# The unit's shell is mksh with toolbox only (see scripts/rtwlan.sh).
MOD_DIR=${MOD_DIR:-${HMGAPI_MOD_DIR:-/data/hmgapi/mods/usb-hotspot-kr}}
DATA=${DATA:-${HMGAPI_DATA:-/data/hmgapi/run/usb-hotspot-kr/usbap}}
RUN=${RUN:-/data/local/tmp/ev6kr_usbap}
NEMESIS_DIR=${NEMESIS_DIR:-/data/nemesis}
SOFTAP=${SOFTAP:-/data/misc/wifi/softap.conf}
USB_DEVICES=${USB_DEVICES:-/sys/bus/usb/devices}
SYSMODULE=${SYSMODULE:-/sys/module}
HOSTAPD=${HOSTAPD:-/system/bin/hostapd}
DNSMASQ=${DNSMASQ:-/system/bin/dnsmasq}
SLEEP_BIN=${SLEEP_BIN:-/system/bin/sleep}
HOOK_DIR=${HOOK_DIR:-/data/hmgapi/hook}
# the stock hostapd drops to the wifi user (AID_WIFI 1010) as it starts: what it reads or writes
# after that (its settings, the entropy file, the control socket folder) belongs to that user
HOSTAPD_UID=${HOSTAPD_UID:-1010}
export PATH=${EV6KR_TEST_PATH:+$EV6KR_TEST_PATH:}/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
LOG=$DATA/usbap.log
BACKUP_DIR=$DATA/backup
RT_BASE=$DATA/usbap
SAY_TAG=EV6KR-USBAP
. "$MOD_DIR/scripts/rtwlan.sh"
JAR=$MOD_DIR/bin/softapconf.jar
DRV=88x2bu
AP_NET=192.168.43
AP_IP=$AP_NET.1
MODULE_ARGS="rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0 rtw_en_napi=0 rtw_en_gro=0 ifname=rtwlan%d if2name=rtwlan%d"
INTERVAL=${INTERVAL:-3}

# --- what else might run the hotspot ---------------------------------------------------------
other_hotspot() {   # usbwifi.hotspot runs its own: this mod stays off while it's installed
    [ -d "$NEMESIS_DIR/apps/usbwifi.hotspot" ] || [ -d "$NEMESIS_DIR/packages/usbwifi.hotspot" ]
}
apsync_installed() {   # ev6kr.usbap.sync (for usbwifi.hotspot) already runs the shared extras
    [ -d "$NEMESIS_DIR/apps/ev6kr.usbap.sync" ] || [ -d "$NEMESIS_DIR/packages/ev6kr.usbap.sync" ]
}

# --- the driver ---------------------------------------------------------------------------------
PLATFORM=""; KO=""; IDS=""
drv_files() {
    PLATFORM=$(getprop ro.board.platform 2>/dev/null)
    [ -n "$PLATFORM" ] || PLATFORM=tcc803x
    KO=$MOD_DIR/modules/${DRV}_$PLATFORM.ko
    IDS=${KO%.ko}.ids
}
dongle_id() {   # a dongle the driver takes is on the bus: its vendor:product
    local _d _v _p
    [ -f "$IDS" ] || return 1
    for _d in "$USB_DEVICES"/*; do
        [ -f "$_d/idVendor" ] && [ -f "$_d/idProduct" ] || continue
        read -r _v < "$_d/idVendor"
        read -r _p < "$_d/idProduct"
        grep -q -x "$_v:$_p" "$IDS" 2>/dev/null && { putline "$_v:$_p"; return 0; }
    done
    return 1
}
dongle_intfs() {   # the USB interfaces (e.g. 4-1:1.0) of the dongle on the bus
    local _d _v _p _i
    [ -f "$IDS" ] || return 0
    for _d in "$USB_DEVICES"/*; do
        [ -f "$_d/idVendor" ] && [ -f "$_d/idProduct" ] || continue
        read -r _v < "$_d/idVendor"
        read -r _p < "$_d/idProduct"
        grep -q -x "$_v:$_p" "$IDS" 2>/dev/null || continue
        for _i in "$_d"/*:*; do [ -d "$_i" ] && putline "${_i##*/}"; done
    done
}
UNBOUND=0
dongle_taken() {   # the driver has the dongle; if not, after ~12 s ask it once more, then say so
    local _i
    usb_dongle_bound && { UNBOUND=0; return 0; }
    UNBOUND=$((UNBOUND + 1))
    if [ "$UNBOUND" = 4 ]; then
        for _i in $(dongle_intfs); do
            putline "$_i" > "$USB_DRIVERS/rtl88x2bu/bind" 2>/dev/null
        done
        say "the driver hasn't taken the dongle (its start failed, see dmesg): asked it to try again"
    elif [ "$UNBOUND" = 8 ]; then
        say "the dongle still isn't running: unplug it and plug it back in (the driver is loaded now and takes it as it appears)"
    fi
    return 1
}
lastline() {   # lastline <file>
    local _l _last=""
    [ -f "$1" ] || return 0
    while read -r _l || [ -n "$_l" ]; do [ -n "$_l" ] && _last=$_l; done < "$1"
    putline "$_last"
}
driver_ready() {   # 0: this mod's driver is in the kernel (loaded now if need be)
    local _ours _now _boot
    _ours=$(cat "${KO%.ko}.srcversion" 2>/dev/null)
    if grep -q "^$DRV " "$PROC/modules" 2>/dev/null; then
        _now=$(cat "$SYSMODULE/$DRV/srcversion" 2>/dev/null)
        if [ -n "$_ours" ] && [ "$_now" != "$_ours" ]; then
            note "another $DRV driver is loaded (srcversion $_now, this mod's $_ours; usbwifi.hotspot's?): reboot the head unit to use this mod's"
            return 1
        fi
        return 0
    fi
    [ -f "$KO" ] || { note "no driver for $PLATFORM in this mod (${KO##*/})"; return 1; }
    _boot=$(cat "$PROC/sys/kernel/random/boot_id" 2>/dev/null)
    if [ -n "$_boot" ] && [ "$(cat "$RUN/insmod.failed" 2>/dev/null)" = "$_boot" ]; then
        note "the driver didn't load this boot ($(lastline "$RUN/insmod.log")): not tried again before a reboot"
        return 1
    fi
    say "loading ${KO##*/} ($MODULE_ARGS)"
    insmod "$KO" $MODULE_ARGS >> "$RUN/insmod.log" 2>&1
    if grep -q "^$DRV " "$PROC/modules" 2>/dev/null; then
        say "driver loaded: $DRV $(cat "$SYSMODULE/$DRV/version" 2>/dev/null)"
        return 0
    fi
    say "the driver didn't load: $(lastline "$RUN/insmod.log")"
    putline "$_boot" > "$RUN/insmod.failed"
    return 1
}

# --- the stock CarPlay hotspot settings -----------------------------------------------------------
CP_SSID=""; CP_PASS=""; CP_MODE=""; CP_CHANNEL=""; SOFTAP_SIG="-"
AP_SSID=""; AP_PASS=""; AP_HW_MODE=""; AP_CHANNEL=""
read_settings() {   # SoftApConf prints them shell-quoted: AP_SSID, AP_PASS, AP_HW_MODE, AP_CHANNEL
    local _out
    _out=$(CLASSPATH="$JAR" app_process /system/bin ev6kr.cpw.SoftApConf usbconf "$SOFTAP" 2>>"$LOG")
    case "$_out" in AP_SSID=*) ;; *) return 1 ;; esac
    AP_SSID=""; AP_PASS=""; AP_HW_MODE=""; AP_CHANNEL=""
    eval "$_out"
    [ -n "$AP_SSID" ] && [ -n "$AP_PASS" ] && [ -n "$AP_CHANNEL" ] || return 1
    CP_SSID=$AP_SSID; CP_PASS=$AP_PASS; CP_MODE=${AP_HW_MODE:-a}; CP_CHANNEL=$AP_CHANNEL
}
settings_current() {   # AP_*: the stock settings (read again when softap.conf changes), tuned channel
    local _sig _c
    _sig=$(md5 "$SOFTAP" 2>/dev/null) || _sig=$(ls -l "$SOFTAP" 2>/dev/null)
    if [ -z "$CP_SSID" ] || [ "$_sig" != "$SOFTAP_SIG" ]; then
        if read_settings; then
            SOFTAP_SIG=$_sig
        elif [ -z "$CP_SSID" ]; then
            return 1
        fi
    fi
    AP_SSID=$CP_SSID; AP_PASS=$CP_PASS; AP_HW_MODE=$CP_MODE; AP_CHANNEL=$CP_CHANNEL
    _c=$(tune_get channel)
    case "$_c" in 36|40|44|48|149|153|157|161|165) AP_CHANNEL=$_c; AP_HW_MODE=a ;; esac
    return 0
}

# --- hostapd and dnsmasq --------------------------------------------------------------------------
write_conf() {   # write_conf <iface>: hostapd's settings, readable by its wifi user only
    local _f=$RUN/hostapd.conf
    (
        umask 077
        {
            putline "interface=$1"
            putline "driver=nl80211"
            putline "ctrl_interface=$RUN/ctrl"
            putline "ssid=$AP_SSID"
            putline "hw_mode=$AP_HW_MODE"
            putline "channel=$AP_CHANNEL"
            putline "ieee80211n=1"
            putline "wmm_enabled=1"
            putline "ignore_broadcast_ssid=0"
            putline "wpa=2"
            putline "wpa_key_mgmt=WPA-PSK"
            putline "rsn_pairwise=CCMP"
            putline "wpa_passphrase=$AP_PASS"
        } > "$_f.tmp"
    ) && mv "$_f.tmp" "$_f" || return 1
    chown "$HOSTAPD_UID:$HOSTAPD_UID" "$_f" 2>/dev/null
    return 0
}
route_tables() {   # policy routing tables in "ip rule" (not local/main/default): Android sends
    # unmarked traffic through one before main (rule 10000 -> table 60 here), so the hotspot's
    # subnet goes in each of them too
    local _w _next="" _seen=" "
    for _w in $(ip rule show 2>/dev/null); do
        if [ -n "$_next" ]; then
            case "$_w" in ''|*[!0-9]*) ;; *)
                case "$_seen" in *" $_w "*) ;; *) _seen="$_seen$_w "; putline "$_w" ;; esac ;;
            esac
            _next=""
        fi
        [ "$_w" = lookup ] && _next=1
    done
}
udp_port_busy() {   # udp_port_busy <port as 4 hex digits>: a socket bound to it
    local _f _sl _l _rest
    for _f in "$PROC/net/udp" "$PROC/net/udp6"; do
        [ -r "$_f" ] || continue
        while read -r _sl _l _rest; do
            case "$_l" in *:"$1") return 0 ;; esac
        done < "$_f"
    done
    return 1
}
pid_of() {   # pid_of <pid file> <comm>: the pid when that process still runs
    local _p="" _c=""
    [ -f "$1" ] && read -r _p < "$1"
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    [ -f "$PROC/$_p/comm" ] && read -r _c < "$PROC/$_p/comm"
    [ "$_c" = "$2" ] && putline "$_p"
}
stop_pid() {   # stop_pid <pid file> <comm>
    local _p
    _p=$(pid_of "$1" "$2") && kill "$_p" 2>/dev/null
    rm -f "$1"
}
dhcp_start() {   # dhcp_start <iface>
    local _if=$1
    udp_port_busy 0043 && note "UDP port 67 is already taken (another DHCP server?): phones may get no address"
    rm -f "$RUN/dhcp/dnsmasq.pid" "$RUN/dhcp/in.pid"
    # Android's dnsmasq reads netd's commands on stdin and stops serving when it closes: a writer
    # gives it the interface list once (no newline: the name would carry it) and holds the pipe
    sh -c 'echo $$ > "$1"; print -n -- "update_ifaces:$2" 2>/dev/null || printf %s "update_ifaces:$2"; exec "$3" 2000000000' \
        sh "$RUN/dhcp/in.pid" "$_if" "$SLEEP_BIN" | \
        "$DNSMASQ" --keep-in-foreground --no-resolv --no-poll --port=0 --dhcp-broadcast --log-dhcp \
            --interface="$_if" --dhcp-range="$AP_NET.10,$AP_NET.100,12h" --dhcp-option=3 --dhcp-option=6 \
            --dhcp-leasefile="$RUN/dhcp/dnsmasq.leases" --pid-file="$RUN/dhcp/dnsmasq.pid" \
            >> "$RUN/dhcp/dnsmasq.log" 2>&1 &
    sleep 1
}
AP_IF=""; AP_WANT=""; AP_STARTS=0
ap_alive() {
    pid_of "$RUN/hostapd.pid" hostapd >/dev/null && pid_of "$RUN/dhcp/dnsmasq.pid" dnsmasq >/dev/null
}
ap_start() {   # ap_start <iface>
    local _if=$1 _t
    mkdir -p "$RUN/ctrl" "$RUN/dhcp" 2>/dev/null
    chmod 755 "$RUN" 2>/dev/null
    chmod 777 "$RUN/dhcp" 2>/dev/null   # dnsmasq drops to nobody after start
    # hostapd's own: the control socket folder and the entropy file it rewrites (8th test: as
    # root-only files, hostapd couldn't open its settings and never started)
    [ -f "$RUN/entropy.bin" ] || : > "$RUN/entropy.bin"
    chown "$HOSTAPD_UID:$HOSTAPD_UID" "$RUN/ctrl" "$RUN/entropy.bin" 2>/dev/null
    chmod 770 "$RUN/ctrl" 2>/dev/null
    chmod 600 "$RUN/entropy.bin" 2>/dev/null
    write_conf "$_if" || { note "can't write $RUN/hostapd.conf"; return 1; }
    # the link settings (A-MPDU refused, ...) before hostapd lets a phone in
    apsync_installed || tune_rtl
    ip link set "$_if" up >/dev/null 2>&1
    ip -4 addr flush dev "$_if" >/dev/null 2>&1
    ip addr add "$AP_IP/24" broadcast "$AP_NET.255" dev "$_if" >/dev/null 2>&1
    for _t in $(route_tables); do
        ip route replace "$AP_NET.0/24" dev "$_if" table "$_t" >/dev/null 2>&1
    done
    putline "== $(date) hostapd on $_if" >> "$RUN/hostapd.log"
    "$HOSTAPD" -e "$RUN/entropy.bin" "$RUN/hostapd.conf" >> "$RUN/hostapd.log" 2>&1 &
    putline "$!" > "$RUN/hostapd.pid"
    chmod 644 "$RUN/hostapd.pid" 2>/dev/null
    sleep 2
    # hostapd brings the interface up itself and may have taken the address with it
    ip -4 addr show dev "$_if" 2>/dev/null | grep -q "inet $AP_IP/" \
        || ip addr add "$AP_IP/24" broadcast "$AP_NET.255" dev "$_if" >/dev/null 2>&1
    dhcp_start "$_if"
    AP_IF=$_if
    putline "$_if" > "$RUN/iface"
    AP_STARTS=$((AP_STARTS + 1))
    say "hotspot on $_if: SSID $AP_SSID, channel $AP_CHANNEL (802.11$AP_HW_MODE), $AP_IP/24"
}
ap_stop() {   # ap_stop <why>
    stop_pid "$RUN/hostapd.pid" hostapd
    stop_pid "$RUN/dhcp/dnsmasq.pid" dnsmasq
    stop_pid "$RUN/dhcp/in.pid" sleep
    [ -n "$AP_IF" ] && [ -e "$SYSNET/$AP_IF" ] && ip -4 addr flush dev "$AP_IF" >/dev/null 2>&1
    rm -f "$RUN/iface"
    [ -n "$AP_IF" ] && say "hotspot off on $AP_IF ($1)"
    AP_IF=""
    AP_WANT=""
}
stale_cleanup() {   # pid files from before a reboot name other processes now: forget them
    local _boot
    _boot=$(cat "$PROC/sys/kernel/random/boot_id" 2>/dev/null)
    if [ "$(cat "$RUN/boot" 2>/dev/null)" != "$_boot" ]; then
        rm -f "$RUN/hostapd.pid" "$RUN/dhcp/dnsmasq.pid" "$RUN/dhcp/in.pid" "$RUN/iface"
        putline "$_boot" > "$RUN/boot"
    elif pid_of "$RUN/hostapd.pid" hostapd >/dev/null || pid_of "$RUN/dhcp/dnsmasq.pid" dnsmasq >/dev/null; then
        # the same boot, the service restarted: the previous hostapd and dnsmasq are ours
        say "service restarted: stopping the previous hostapd and dnsmasq"
        ap_stop "service restarted"
    fi
}

# --- one pass, the loop ---------------------------------------------------------------------------
QUIET=0
usbap_pass() {
    local _if _want _why
    if ! dongle_id > /dev/null; then
        [ -n "$AP_IF" ] && ap_stop "dongle gone"
        note "waiting for a USB Wi-Fi dongle"
        return 0
    fi
    driver_ready || return 0
    dongle_taken || { note "dongle on the bus, the driver hasn't taken it yet"; return 0; }
    _if=$(newest_rtwlan)
    [ -n "$_if" ] || { note "dongle on the bus, waiting for its interface"; return 0; }
    settings_current || { note "can't read the stock CarPlay hotspot settings ($SOFTAP)"; return 0; }
    _want="$_if|$AP_SSID|$AP_PASS|$AP_HW_MODE|$AP_CHANNEL"
    if [ "$_want" = "$AP_WANT" ] && ap_alive; then
        return 0
    fi
    # many restarts: every 10th pass only (~30 s)
    if [ "$AP_STARTS" -ge 5 ]; then
        QUIET=$((QUIET + 1))
        [ "$QUIET" -ge 10 ] || return 0
        QUIET=0
    fi
    if [ -n "$AP_IF" ]; then
        if [ "$_want" != "$AP_WANT" ]; then _why="interface or settings changed"; else _why="hostapd or dnsmasq stopped"; fi
        ap_stop "$_why"
    fi
    ap_start "$_if" && AP_WANT=$_want
    return 0
}
guard_check() {   # HMG-API's boot guard: 3 starts in a row that didn't last 2 minutes turn its
    # hooks off (the CarPlay mod's included) until /data/hmgapi/hook/starts is reset
    local _n
    _n=$(cat "$HOOK_DIR/starts" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_n" -ge 3 ] && say "HMG-API's boot guard has its hooks off (hook/starts=$_n, after quick reboots): wireless CarPlay's hooks don't run until it's reset (trylog stick: EV6KR-HOOKS-RESET)"
    return 0
}
usbap_exit() {
    trap - TERM INT HUP
    DEBUG_STOP=1
    ap_stop "service stopped"
    if ! apsync_installed; then
        tune_untune
        net_untune
        debug_logcat
    fi
    say "usb-hotspot-kr stop"
    exit 0
}
usbap_main() {
    local _n=0
    mkdir -p "$DATA" "$RUN" "$RUN/dhcp" "$BACKUP_DIR" 2>/dev/null
    chmod 755 "$RUN" 2>/dev/null
    [ -f "$LOG" ] && mv "$LOG" "$LOG.old" 2>/dev/null
    drv_files
    say "usb-hotspot-kr start (pid $$), driver ${KO##*/}"
    debug_start_cleanup
    guard_check
    stale_cleanup
    # the driver first, so it's there when the dongle shows up
    if ! other_hotspot && [ -f "$KO" ]; then
        driver_ready
    fi
    trap usbap_exit TERM INT HUP
    apsync_installed || net_tune
    while :; do
        if other_hotspot; then
            note "usbwifi.hotspot is installed and runs the hotspot: this mod stays off (remove it, then reboot, to use this one)"
            [ -n "$AP_IF" ] && ap_stop "usbwifi.hotspot is installed"
        else
            if apsync_installed; then
                note "ev6kr.usbap.sync is installed: it runs the sampler and tuning (it's for usbwifi.hotspot: remove it)"
            else
                debug_logcat
                netsample_ctl
                tune_ctl
            fi
            usbap_pass
        fi
        _n=$((_n + 1))
        [ -n "$USBAP_PASSES" ] && [ "$_n" -ge "$USBAP_PASSES" ] && break
        sleep "$INTERVAL"
    done
}
