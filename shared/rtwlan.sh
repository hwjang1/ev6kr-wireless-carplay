#!/system/bin/sh
# rtwlan.sh - the USB Wi-Fi dongle side shared by ev6kr.usbap.sync (with usbwifi.hotspot) and
# the usb-hotspot-kr HMG-API mod (standalone): output helpers, the debug logcat, which dongle
# interface is live, the receive backlog, the network sampler and the dongle link tuning.
# Sourced after the includer has set:
#   RT_BASE     path prefix of this side's files (<RT_BASE>.log, .tune, .netsample.txt, ...)
#   LOG         the log file          BACKUP_DIR   where first-seen values are kept
#   SAY_TAG     the logcat tag (default EV6KR-APSYNC)
# PROC, NL and putline-only shell rules as in the includer: mksh + Android 4.4 toolbox (no printf,
# sed, awk, head, tail, cut, tr; no heredocs: mksh needs a writable /tmp for them).
PROC=${PROC:-/proc}
NL='
'

# putline <text>: the text and a newline, as it is (no echo escapes). mksh (the unit) has print;
# the off-car tests also run dash and bash, which have printf instead (named through a variable:
# the unit never takes that branch, and HMG-API's script check looks for printf calls)
# putraw <text>: the same without the newline
if print -r -- "" >/dev/null 2>&1; then
    putline() { print -r -- "$1"; }
    putraw() { print -r -n -- "$1"; }
else
    RT_PRINTF=printf
    putline() { "$RT_PRINTF" '%s\n' "$1"; }
    putraw() { "$RT_PRINTF" '%s' "$1"; }
fi

say() {
    putline "$(date) $*" >> "$LOG" 2>/dev/null
    log -t "${SAY_TAG:-EV6KR-APSYNC}" "$*" >/dev/null 2>&1
    true
}

# note: say, but only when the message differs from the last one (the service loops)
LAST_NOTE=""
note() {
    [ "$1" = "$LAST_NOTE" ] && return 0
    LAST_NOTE=$1
    say "$1"
}

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
    true
}

# debug_logcat: unless <RT_BASE>.nodebug exists (or the package is being removed), keep a
# logcat of everything but the CAN status spam (BCMCanManager, NavigationCluster) in
# <RT_BASE>.logcat.txt (1 MB x 4): logcat's own
# buffer only holds seconds on this unit, and the single USB port means no adb while the
# dongle is in. On by default while this is a test release; usb/trylog collects it, and an
# EV6KR-DEBUG-OFF file on that stick turns it off. May hold phone names and Bluetooth
# addresses: for your own debugging.
NODEBUG_FLAG=$RT_BASE.nodebug
DEBUG_PID=$RT_BASE.logcat.pid
DEBUG_LOG=$RT_BASE.logcat.txt
# every level from CarPlay (DiPO, the CarPlay/AirPlay libraries), iAP2, the Bluetooth manager and
# its SPP, the hotspot side and HMG-API; warnings and errors from everything else (all of
# logcat is ~60 KB/s on this unit, mostly Bluetooth audio, MICOM and launcher chatter)
DEBUG_TAGS="CarPlay_:V TccCarPlay:V CarPlayService:V CarPlay:V AirPlay:V DiPOManager:V PhoneProjection:V AAProjection:V Iap2Service:V Iap2Acc:V iAP2:V BTCMService:V BTCMStateMachine:V BTCMListenerManager:V BTCMListenerGenerator:V BTCMStarterReceiver:V BTCMManager:V HfDeviceBTCMSppApi:V bt-rfcomm:V HMG-API:V hostapd:V dnsmasq:V USBWifiHotspot:V EV6KR-APSYNC:V EV6KR-USBAP:V Tethering:V WifiApConfigStore:V WifiService:V WifiStateMachine:V mdnsd:V GalReceiver:V BCMCanManager:S NavigationCluster:S"
debug_logcat() {
    local _p="" _c=""
    [ -f "$DEBUG_PID" ] && read -r _p < "$DEBUG_PID" 2>/dev/null
    # a pid from before a restart may now be another process
    [ -n "$_p" ] && [ -f "$PROC/$_p/comm" ] && read -r _c < "$PROC/$_p/comm"
    [ "$_c" = logcat ] || { _p=""; rm -f "$DEBUG_PID"; }
    if [ ! -f "$NODEBUG_FLAG" ] && [ -z "$DEBUG_STOP" ]; then
        [ -n "$_p" ] && return 0
        logcat -v time -f "$DEBUG_LOG" -r 1024 -n 4 $DEBUG_TAGS '*:W' >/dev/null 2>&1 &
        putline "$!" > "$DEBUG_PID"
        say "debug logcat on ($DEBUG_LOG)"
    elif [ -n "$_p" ]; then
        kill "$_p" 2>/dev/null
        rm -f "$DEBUG_PID"
        say "debug logcat off"
    fi
    return 0
}

SYSNET=${SYSNET:-/sys/class/net}
USB_DRIVERS=${USB_DRIVERS:-/sys/bus/usb/drivers}
# The dongle driver whose /proc entries are read and written here (sampler, tuning, TX path): the
# 88x2bu, whose entries were tried on the car first (reading the driver-wide drv_cfg took the head
# unit down). usbwifi.hotspot's 8851bu driver (RTL8851BU/8831BU) has its own, untried ones: left alone.
RTL_PROC_DIR=${RTL_PROC_DIR:-rtl88x2bu}

# usb_dongle_bound: a USB interface is bound to a Realtek USB driver now
usb_dongle_bound() {
    local _d _e
    for _d in "$USB_DRIVERS"/rtl*; do
        [ -d "$_d" ] || continue
        for _e in "$_d"/*:*; do
            [ -e "$_e" ] && return 0
        done
    done
    return 1
}

# newest_rtwlan: the rtwlan interface with the highest ifindex
newest_rtwlan() {
    local _if _idx _best="" _bi=-1
    for _if in "$SYSNET"/rtwlan*; do
        [ -e "$_if/ifindex" ] || continue
        read -r _idx < "$_if/ifindex"
        case "$_idx" in ''|*[!0-9]*) continue ;; esac
        if [ "$_idx" -gt "$_bi" ]; then
            _bi=$_idx
            _best=${_if##*/}
        fi
    done
    [ -n "$_best" ] && putline "$_best"
}

# net_tune: a deeper receive backlog. The USB Wi-Fi driver runs without NAPI/GRO
# (usbwifi.hotspot's rtw_en_napi=0 rtw_en_gro=0), so each received frame goes through the
# per-CPU backlog (net.core.netdev_max_backlog, 1000): CarPlay's video bursts overflowed it
# (5th car test: 12368 receive drops for 2358 packets, the screen stream timed out). The first
# values seen are saved and put back at uninstall.
SYSCTL_CORE=${SYSCTL_CORE:-/proc/sys/net/core}
# /proc/sys answers only a read at offset 0 and mksh's read takes one byte at a time, so these
# values are read with cat (0.1.5/0.1.6 saved "1" for 1000 and "3" for 300). The values go back
# to the kernel's at every boot: the one seen before our change is saved again whenever it isn't
# ours, and anything implausible is put back as the kernel default.
NET_TUNE="netdev_max_backlog=5000 netdev_budget=600"
NET_DEFAULTS="netdev_max_backlog=1000 netdev_budget=300"
net_default() {   # net_default <key>
    local _kv
    for _kv in $NET_DEFAULTS; do
        case "$_kv" in "$1="*) putline "${_kv#*=}"; return 0 ;; esac
    done
    return 1
}
net_tune() {
    local _kv _k _v _cur
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    for _kv in $NET_TUNE; do
        _k=${_kv%%=*}
        _v=${_kv#*=}
        [ -f "$SYSCTL_CORE/$_k" ] || continue
        _cur=$(cat "$SYSCTL_CORE/$_k" 2>/dev/null)
        [ "$_cur" = "$_v" ] && continue
        case "$_cur" in ???*) putline "$_cur" > "$BACKUP_DIR/sysctl.$_k" ;; esac
        putline "$_v" > "$SYSCTL_CORE/$_k" 2>/dev/null && say "net.core.$_k $_cur -> $_v"
    done
    return 0
}

net_untune() {
    local _f _k _v
    for _f in "$BACKUP_DIR"/sysctl.*; do
        [ -f "$_f" ] || continue
        _k=${_f##*/sysctl.}
        read -r _v < "$_f"
        case "$_v" in ???*) ;; *) _v=$(net_default "$_k") || continue ;; esac
        putline "$_v" > "$SYSCTL_CORE/$_k" 2>/dev/null && say "net.core.$_k back to $_v"
    done
    return 0
}

# netsample <parent pid>: while debug logging is on and the service runs, every 5 s: the USB
# Wi-Fi interfaces' counters, the kernel's per-CPU backlog drops (softnet_stat, 2nd column),
# TCP/UDP counters and the load. Every 30 s: the dongle driver's view of each station (rates,
# QoS/HT/aggregation, signal, its receive drop reasons), TCP extended counters, the established
# TCP connections' queues and a short ping (56 and 1400 bytes) to the hotspot's DHCP clients.
# Into <RT_BASE>.netsample.txt; at start and every 30 min the file moves to
# <RT_BASE>.netsample.txt.1 (the previous one is dropped). The dongle has to come out for the trylog stick
# and its /proc entries go with it, so they're sampled here while it's in.
# Only driver entries already read on the car without harm (6th test: usbwifi.hotspot's v5.8.7.1,
# 7th: v5.13.1), and tpc_settings (read every 3 s by the tuning, v5.13.1 only). Reading the
# driver-wide /proc/net/rtl88x2bu/drv_cfg took the head unit down every time, ~30 s into each
# boot (8th and 9th tests: the 0.1.8 reboot loop and the standalone ones), so the driver's
# version comes from /sys/module instead and nothing else is added without a car test.
NETSAMPLE=$RT_BASE.netsample.txt
NETSAMPLE_EVERY=${NETSAMPLE_EVERY:-5}
SYSMODULE=${SYSMODULE:-/sys/module}
RTL_PROC_NOW="all_sta_info rx_stat tx_stat trx_info rx_signal sta_tp_info rx_ampdu tpc_settings"
RTL_PROC_ONCE="hw_info rate_ctl sec_info wifi_spec chan_plan country_code tx_max_agg_num ps_dbg_info mac_qinfo"
ns_keep() {   # ns_keep <prefix>...: the stdin lines (leading blanks off) starting with one of them
    local _l _p
    while read -r _l; do
        for _p in "$@"; do
            case "$_l" in "$_p"*) putline "$_l"; break ;; esac
        done
    done
}
ns_file() {   # ns_file <file> <prefix>...: those lines of a /proc file
    local _f=$1
    shift
    [ -r "$_f" ] && ns_keep "$@" < "$_f"
    return 0
}
ns_rtl() {    # ns_rtl <names>: those entries of every dongle interface
    local _d _e
    for _d in "$PROC"/net/$RTL_PROC_DIR/rtwlan*; do
        [ -d "$_d" ] || continue
        for _e in $1; do
            [ -r "$_d/$_e" ] || continue
            putline "-- $_d/$_e"
            cat "$_d/$_e" 2>/dev/null
        done
    done
}
ns_tcp() {    # established TCP connections (not loopback): addresses, tx:rx queues, retransmits
    local _f _sl _l _r _st _q _tr _rt _rest
    for _f in "$PROC/net/tcp" "$PROC/net/tcp6"; do
        [ -r "$_f" ] || continue
        while read -r _sl _l _r _st _q _tr _rt _rest; do
            [ "$_st" = 01 ] || continue
            case "$_r" in 0100007F:*|00000000000000000000000001000000:*|0000000000000000FFFF00000100007F:*) continue ;; esac
            putline "tcp $_l $_r q=$_q retr=$_rt"
        done < "$_f"
    done
}
ns_pingsum() {   # the summary lines of ping's output
    local _l
    while read -r _l; do
        case "$_l" in *transmitted*|rtt*|round-trip*) putline "$_l" ;; esac
    done
}
ns_ping() {   # the hotspot clients the head unit has talked to lately (ARP, complete), two at most
    local _ip _hw _fl _mac _mask _dev _n=0
    [ -r "$PROC/net/arp" ] || return 0
    while read -r _ip _hw _fl _mac _mask _dev; do
        case "$_dev" in rtwlan*) ;; *) continue ;; esac
        [ "$_fl" = 0x2 ] || continue
        _n=$((_n + 1))
        [ $_n -gt 2 ] && break
        putline "-- ping $_ip"
        ping -q -c 5 -i 0.2 -w 3 "$_ip" 2>&1 | ns_pingsum
        ping -q -c 5 -i 0.2 -w 3 -s 1400 "$_ip" 2>&1 | ns_pingsum
    done < "$PROC/net/arp"
}
netsample() {
    local _parent=$1 _n=0 _once="" _f
    [ -f "$NETSAMPLE" ] && mv "$NETSAMPLE" "$NETSAMPLE.1" 2>/dev/null
    while kill -0 "$_parent" 2>/dev/null && [ ! -f "$NODEBUG_FLAG" ] && [ -z "$DEBUG_STOP" ]; do
        if [ $_n -ge 360 ]; then
            mv "$NETSAMPLE" "$NETSAMPLE.1" 2>/dev/null
            _n=0
            _once=""
        fi
        {
            putline "== $(date) up $(cat "$PROC/uptime" 2>/dev/null)"
            ns_file "$PROC/net/dev" rtwlan
            putline "softnet: $(cat "$PROC/net/softnet_stat" 2>/dev/null)"
            ns_file "$PROC/net/snmp" Tcp: Udp:
            putline "load: $(cat "$PROC/loadavg" 2>/dev/null)"
            if [ $((_n % 6)) = 0 ]; then
                if [ -z "$_once" ] && ls -d "$PROC"/net/$RTL_PROC_DIR/rtwlan* > /dev/null 2>&1; then
                    for _f in "$SYSMODULE"/88x2bu "$SYSMODULE"/8851bu; do
                        [ -d "$_f" ] && putline "-- driver ${_f##*/} $(cat "$_f/version" 2>/dev/null) srcversion $(cat "$_f/srcversion" 2>/dev/null)"
                    done
                    ns_rtl "$RTL_PROC_ONCE"
                    _once=1
                fi
                ns_rtl "$RTL_PROC_NOW"
                ns_file "$PROC/net/netstat" TcpExt:
                ns_tcp
                ns_ping
            fi
        } >> "$NETSAMPLE" 2>/dev/null
        _n=$((_n + 1))
        sleep "$NETSAMPLE_EVERY"
    done
}

# Dongle link tuning (experiments). The 6th car test showed the phone sending at the lowest rate
# (MCS0) with a strong signal (-37 dBm) and re-sending most frames: the phone keeps missing what
# the dongle sends. 0.1.7 refused the phone's A-MPDU sessions (plain acks instead of block acks):
# the 7th test (also with the Realtek v5.13.1 driver) was slower (57-137 kbit/s against 242-622)
# with the same misses. The 8th test's reboots were blamed on block ack at first; the cause was
# the sampler reading the driver-wide drv_cfg entry (0.1.9 dropped it). With usbwifi.hotspot's
# v5.8.7.1 driver and block ack on (12th collection) the screen stream got 1.6-5.5 Mbit/s
# against 0.6-3 with it off, and nothing crashed, so ev6kr.usbap.sync leaves it to the driver
# again (its common.sh); the standalone stack keeps refusing it until its driver is car-tested.
# What the 7th and 12th add: the dongle hears the phone well (-25..-43 dBm) while the phone and
# a 2nd Apple device miss its frames (60% TX retries, 50-93% ping loss even with no traffic,
# EAPOL 1/4 sent 4 times unanswered, the phone re-joining every ~30 s in one attempt).
# The driver sends every 1-stream frame (acks, management, legacy and MCS0-7 data) from antenna
# path A alone (txpath_1ss 0x1), so a weak antenna or feed on path A would explain it; and a
# USB supply sagging under the 2-chain TX current would too. Defaults below;
# <RT_BASE>.tune (key=value lines, the trylog stick's EV6KR-TUNE.txt) overrides them:
#   rx_ampdu=0|auto   0: the dongle refuses the phone's A-MPDU (block ack) sessions -> plain acks
#   channel=36..48|149..165   the 5 GHz channel instead of the stock one (149)
#   country=KR        the dongle driver's country (channel plan, TX power limits)
#   txpath=cycle      once a phone is on the hotspot, 1-stream frames from path A, B and both
#                     (~20 s each, 3 rounds) with a ping to the phone at the end of each step;
#                     then the path with the most replies stays until the dongle is replugged
#   txpath=a|b|ab     that path; txpath=driver (default): the driver's own (path A)
#   txpower=1..6      dB below the driver's TX power (the USB supply test); 0: the driver's power
#   lte_share=0|1     (ev6kr.usbap.sync) 1: the car's LTE shared with the hotspot's phones (usbwifi
#                     ENABLE_LTE_NAT=1); 0 (default): not, the phone keeps its own data as with stock CarPlay
# txpath works on both drivers: usbwifi.hotspot's v5.8.7.1 has the same phydm "trxpath" command
# and 8822B register code as v5.13.1. txpower needs v5.13.1 (tpc_settings).
TUNE=$RT_BASE.tune
TUNE_DEFAULTS="rx_ampdu=0 txpath=driver"
tune_get() {   # tune_get <key>: the tune file's value, else the default
    local _l _v=""
    for _l in $TUNE_DEFAULTS; do
        case "$_l" in "$1="*) _v=${_l#*=} ;; esac
    done
    if [ -f "$TUNE" ]; then
        while read -r _l || [ -n "$_l" ]; do
            case "$_l" in "$1="*) _v=${_l#*=} ;; esac
        done < "$TUNE"
    fi
    putline "$_v"
}
tune_set() {   # tune_set <key> <value>: into the tune file, in place of that key's lines
    local _l _out=""
    if [ -f "$TUNE" ]; then
        while read -r _l || [ -n "$_l" ]; do
            case "$_l" in "$1="*|'') ;; *) _out="$_out$_l
" ;; esac
        done < "$TUNE"
    fi
    putraw "$_out$1=$2
" > "$TUNE"
}
TUNE_DONE=""
tune_rtl() {   # the driver settings, on every dongle interface (again after a replug)
    local _d _w _a _b _rest _cur _cc
    _w=$(tune_get rx_ampdu)
    _cc=$(tune_get country)
    for _d in "$PROC"/net/$RTL_PROC_DIR/rtwlan*; do
        [ -d "$_d" ] || continue
        if [ -w "$_d/rx_ampdu" ]; then
            _cur=""
            while read -r _a _b _rest; do
                [ "$_a" = accept: ] && { _cur=$_b; break; }
            done < "$_d/rx_ampdu"
            case "$_w:$_cur" in
                0:0\(fixed\)|auto:*\(auto\)|:*) ;;
                0:*) putline 0 > "$_d/rx_ampdu" 2>/dev/null && note "dongle ${_d##*/}: A-MPDU from the phone refused (block ack off; was $_cur)" ;;
                auto:*) putline 255 > "$_d/rx_ampdu" 2>/dev/null && note "dongle ${_d##*/}: A-MPDU from the phone back to the driver's choice" ;;
            esac
        fi
        case "$_cc" in
            [A-Z][A-Z])
                case " $TUNE_DONE " in *" $_d "*) ;; *)
                    putline "$_cc" > "$_d/country_code" 2>/dev/null && say "dongle ${_d##*/}: country $_cc"
                    TUNE_DONE="$TUNE_DONE $_d" ;;
                esac ;;
        esac
    done
    txp_tune
    return 0
}

# TX path. "trxpath 1 3 3 <p>" (TX on A+B, RX on A+B, 1-stream frames on p: 1 A, 2 B, 3 both)
# also locks the driver's own radio calls (channel, bandwidth, TX power) until "trxpath 0", so
# the lock is released right away; the setting then lasts until the driver sets up the radio
# again. BB register 0x93c bits 31:20 say where 1-stream frames go (0x001, 0x002, 0x043): read
# back after each change and every pass, so a reset by the driver gets the setting again.
TXP_STEP_TICKS=${TXP_STEP_TICKS:-7}   # tune passes (3 s) per cycle step
TXP_ROUNDS=${TXP_ROUNDS:-3}
TXP_DIR=""; TXP_OK=""; TXP_SET=""; TXP_STEP=0; TXP_TICK=0; TXP_FINAL=""
TXP_SCORE_a=0; TXP_SCORE_b=0; TXP_SCORE_ab=0
txp_live() {   # the live dongle interface's driver folder (a dongle bound, the newest rtwlan)
    local _if _d _last=""
    usb_dongle_bound || return 0
    _if=$(newest_rtwlan)
    for _d in "$PROC"/net/$RTL_PROC_DIR/rtwlan*; do
        [ -d "$_d" ] || continue
        [ -n "$_if" ] && [ "${_d##*/}" = "$_if" ] && { putline "$_d"; return 0; }
        _last=$_d
    done
    [ -z "$_if" ] && [ -n "$_last" ] && putline "$_last"
}
txp_able() {   # txp_able <dir>: the driver has the "1-stream path" form of trxpath (v5.8.7.1 and
    # v5.13.1 for the 8822B; other chips take the 4th number as "2 paths or not") and a register
    # read entry
    [ -w "$1/odm/cmd" ] && [ -w "$1/read_reg" ] || return 1
    # (no newline: phydm strips it only from a one-word command, and "-h\n" isn't "-h")
    putraw "trxpath -h" > "$1/odm/cmd" 2>/dev/null || return 1
    case "$(cat "$1/odm/cmd" 2>/dev/null)" in *1ss_tx_path*) return 0 ;; esac
    return 1
}
txp_decode() {   # txp_decode <"rtw_read32(0x93c)=0x...">: a, b, ab, or the raw value
    local _v=${1##*=} _h   # (as text: the driver prints %x, no leading zeros)
    case "$_v" in 0x*) _h=${_v#0x} ;; *) return 1 ;; esac
    case "$_h" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
    while [ ${#_h} -lt 8 ]; do _h=0$_h; done
    case "${_h%?????}" in
        001) putline a ;; 002) putline b ;; 043) putline ab ;; *) putline "$_v" ;;
    esac
}
txp_map() {   # txp_map <dir>: where 1-stream frames go now
    putline "93c 4" > "$1/read_reg" 2>/dev/null || return 1
    txp_decode "$(cat "$1/read_reg" 2>/dev/null)"
}
txp_set() {   # txp_set <dir> <a|b|ab>: set, unlock, check
    local _p
    case "$2" in a) _p=1 ;; b) _p=2 ;; ab) _p=3 ;; *) return 1 ;; esac
    putline "trxpath 1 3 3 $_p" > "$1/odm/cmd" 2>/dev/null || return 1
    putline "trxpath 0" > "$1/odm/cmd" 2>/dev/null
    [ "$(txp_map "$1")" = "$2" ]
}
# Crash guard. The phydm commands haven't run on the car yet, and a kernel panic here would come
# back on every boot (the phone joins the hotspot again and the test starts again) and trip
# HMG-API's boot guard, as the drv_cfg read did. Before each phydm command this boot's id goes
# into <RT_BASE>.txp-guard (synced to disk); TXP_SETTLE passes (3 s) after the last path change
# the file goes again. A guard from an earlier boot means that boot ended within a minute of a
# path change (a panic, or the car switched off): the test is turned off for good (txpath=driver
# and a "#txpath-off" line in the tune file, which the trylog stick keeps until EV6KR-TUNE-RESET).
TXP_GUARD=$RT_BASE.txp-guard
TXP_SETTLE=${TXP_SETTLE:-20}
TXP_HELD=0
txp_boot() { cat "$PROC/sys/kernel/random/boot_id" 2>/dev/null; }
txp_arm() {
    TXP_HELD=0
    [ -f "$TXP_GUARD" ] && return 0
    txp_boot > "$TXP_GUARD" 2>/dev/null
    sync
}
txp_guard_ok() {   # 1: an earlier boot went down during the test (now turned off)
    [ -f "$TXP_GUARD" ] || return 0
    [ "$(cat "$TXP_GUARD" 2>/dev/null)" = "$(txp_boot)" ] && return 0
    rm -f "$TXP_GUARD"
    tune_set txpath driver
    putline "#txpath-off $(date)" >> "$TUNE"
    say "dongle TX path test turned off: the head unit went down within a minute of a TX path change (earlier boot); txpath=driver in $TUNE (EV6KR-TUNE-RESET on the trylog stick to allow it again)"
    return 1
}
txp_go() { txp_arm; txp_set "$@"; }   # txp_go <dir> <a|b|ab>: txp_set under the guard
txp_clients() {   # txp_clients <iface>: its hotspot clients (ARP, complete), two at most
    local _ip _hw _fl _mac _mask _dev _n=0
    [ -r "$PROC/net/arp" ] || return 0
    while read -r _ip _hw _fl _mac _mask _dev; do
        [ "$_dev" = "$1" ] && [ "$_fl" = 0x2 ] || continue
        putline "$_ip"
        _n=$((_n + 1))
        [ $_n -ge 2 ] && break
    done < "$PROC/net/arp"
}
TXP_R=0; TXP_PINGS=""
txp_ping() {   # txp_ping <ip>...: TXP_R the replies (8 wanted from each, 1000 bytes, 3 s at most),
    local _ip _out _w _p1 _p2 _sum _j   # TXP_PINGS the ping summaries
    TXP_R=0; TXP_PINGS=""
    for _ip in "$@"; do
        _out=$(ping -q -c 8 -i 0.2 -w 3 -s 1000 "$_ip" 2>&1)
        _sum=$(putline "$_out" | ns_pingsum | while read -r _w; do putline "${_w%%, time*}"; done)
        set -f
        _p1=""; _p2=""
        for _w in $_out; do
            case "$_w" in received*)
                [ "$_p1" = packets ] && _p1=$_p2
                case "$_p1" in ''|*[!0-9]*) ;; *) TXP_R=$((TXP_R + _p1)) ;; esac ;;
            esac
            _p2=$_p1; _p1=$_w
        done
        _j=""
        for _w in $_sum; do _j="$_j${_j:+ }$_w"; done
        set +f
        TXP_PINGS="$TXP_PINGS${TXP_PINGS:+; }$_ip: $_j"
    done
}
txp_txstat() {   # txp_txstat <dir>: the driver's TX counters on one line
    local _k _c _v _out=""
    [ -r "$1/tx_stat" ] || return 0
    while read -r _k _c _v; do
        case "$_k" in data_sent_cnt) _out="$_out sent=$_v" ;; success_cnt) _out="$_out ok=$_v" ;;
            failure_cnt) _out="$_out fail=$_v" ;; retry_cnt) _out="$_out retry=$_v" ;; esac
    done < "$1/tx_stat"
    putline "${_out# }"
}
txp_sample() {   # into the netsample file: the receive report per antenna path (phydm bbinfo)
    [ -f "$NODEBUG_FLAG" ] && return 0
    {
        putline "-- $1 txpath $2: phydm bbinfo"
        putline "bbinfo" > "$1/odm/cmd" 2>/dev/null && cat "$1/odm/cmd" 2>/dev/null
    } >> "$NETSAMPLE" 2>/dev/null
}
txp_cycle() {   # one tune pass of the path test on <dir>; prints the path to keep once it's done
    local _d=$1 _ips _n _p _best
    _ips=$(txp_clients "${_d##*/}")
    [ -n "$_ips" ] || return 0   # no phone yet
    case $((TXP_STEP % 3)) in 0) _p=a ;; 1) _p=b ;; *) _p=ab ;; esac
    if [ "$TXP_TICK" = 0 ]; then
        if ! txp_go "$_d" "$_p"; then
            say "dongle ${_d##*/}: TX path $_p not taken (0x93c $(txp_map "$_d")): path test stopped"
            TXP_OK=""
            return 0
        fi
        TXP_SET=$_p
    fi
    TXP_TICK=$((TXP_TICK + 1))
    [ "$TXP_TICK" -ge "$TXP_STEP_TICKS" ] || return 0
    set -- $_ips
    _n=$#
    txp_ping "$@"
    eval "TXP_SCORE_$_p=\$((TXP_SCORE_$_p + TXP_R))"
    say "dongle TX path $_p (step $((TXP_STEP + 1))/$((3 * TXP_ROUNDS))): $TXP_R of $((8 * _n)) ping replies ($TXP_PINGS); $(txp_txstat "$_d")"
    txp_sample "$_d" "$_p"
    TXP_TICK=0
    TXP_STEP=$((TXP_STEP + 1))
    [ "$TXP_STEP" -ge $((3 * TXP_ROUNDS)) ] || return 0
    # the most replies; a tie keeps the earlier one (a: the driver's own)
    _best=a
    [ "$TXP_SCORE_b" -gt "$TXP_SCORE_a" ] && _best=b
    eval "[ \"\$TXP_SCORE_ab\" -gt \"\$TXP_SCORE_$_best\" ]" && _best=ab
    TXP_FINAL=$_best
    say "dongle TX path test: replies a=$TXP_SCORE_a b=$TXP_SCORE_b ab=$TXP_SCORE_ab -> $_best stays"
}
txp_tune() {
    txp_pass
    TXP_HELD=$((TXP_HELD + 1))
    if [ "$TXP_HELD" -ge "$TXP_SETTLE" ] && [ -f "$TXP_GUARD" ] \
        && [ "$(cat "$TXP_GUARD" 2>/dev/null)" = "$(txp_boot)" ]; then
        rm -f "$TXP_GUARD"
    fi
    return 0
}
txp_pass() {
    local _d _w _cur
    _d=$(txp_live)
    [ -n "$_d" ] || return 0
    if [ "$_d" != "$TXP_DIR" ]; then
        TXP_DIR=$_d; TXP_SET=""; TXP_STEP=0; TXP_TICK=0; TXP_FINAL=""; TXP_OK="?"
        TXP_SCORE_a=0; TXP_SCORE_b=0; TXP_SCORE_ab=0
    fi
    txp_power "$_d"
    _w=$(tune_get txpath)
    # the driver's own path (the default): no phydm command at all, unless we moved it before
    case "$_w" in a|b|ab|cycle) ;; *) [ -n "$TXP_SET" ] || return 0 ;; esac
    if [ "$TXP_OK" = "?" ]; then
        TXP_OK=""
        txp_guard_ok || return 0
        txp_arm
        txp_able "$_d" && TXP_OK=1
    fi
    [ -n "$TXP_OK" ] || return 0
    case "$_w" in
        a|b|ab) ;;
        cycle)
            [ -z "$TXP_FINAL" ] && txp_cycle "$_d"
            [ -n "$TXP_FINAL" ] || return 0
            _w=$TXP_FINAL ;;
        *)   # driver, or anything else: the driver's own path, once we've moved it
            [ -n "$TXP_SET" ] && [ "$TXP_SET" != a ] && txp_go "$_d" a && say "dongle ${_d##*/}: TX path back to the driver's (A)"
            TXP_SET=""
            return 0 ;;
    esac
    _cur=$(txp_map "$_d")
    [ "$_cur" = "$_w" ] && { TXP_SET=$_w; return 0; }
    if txp_go "$_d" "$_w"; then
        if [ "$TXP_SET" = "$_w" ]; then
            note "dongle ${_d##*/}: TX path $_w set again (the driver had $_cur)"
        else
            say "dongle ${_d##*/}: 1-stream frames from TX path $_w (was $_cur)"
        fi
        TXP_SET=$_w
    else
        note "dongle ${_d##*/}: TX path $_w not taken (0x93c $(txp_map "$_d"))"
    fi
    return 0
}
# TX power: tpc_settings "1 <mB>" lowers every rate by that much, "0" is the driver's power
txp_power() {
    local _d=$1 _w _m="" _c="" _l _cur=0
    [ -w "$_d/tpc_settings" ] || return 0
    _w=$(tune_get txpower)
    case "$_w" in [0-6]) ;; *) _w=0 ;; esac
    while read -r _l; do
        case "$_l" in mode:MANUAL*) _m=1 ;; mode:*) _m=0 ;; constraint:*) _c=${_l#constraint:}; _c=${_c%% *} ;; esac
    done < "$_d/tpc_settings"
    [ "$_m" = 1 ] && case "$_c" in ''|*[!0-9]*) ;; *) _cur=$((_c / 100)) ;; esac
    [ "$_cur" = "$_w" ] && return 0
    if [ "$_w" = 0 ]; then
        putline 0 > "$_d/tpc_settings" 2>/dev/null && say "dongle ${_d##*/}: TX power back to the driver's"
    else
        putline "1 $((_w * 100))" > "$_d/tpc_settings" 2>/dev/null && say "dongle ${_d##*/}: TX power $_w dB lower"
    fi
    return 0
}
tune_untune() {   # uninstall: the driver's own choice again
    local _d
    for _d in "$PROC"/net/$RTL_PROC_DIR/rtwlan*; do
        [ -w "$_d/rx_ampdu" ] && putline 255 > "$_d/rx_ampdu" 2>/dev/null
    done
    _d=$(txp_live)
    [ -n "$_d" ] || return 0
    case "$(tune_get txpath)" in   # only if the path may have been moved (asked for in the tune file)
        a|b|ab|cycle) txp_able "$_d" && case "$(txp_map "$_d")" in b|ab) txp_set "$_d" a ;; esac ;;
    esac
    [ -w "$_d/tpc_settings" ] && putline 0 > "$_d/tpc_settings" 2>/dev/null
    return 0
}
# Realtek "ZeroCD" dongles. Some, the ipTIME AX900UA's RTL8831BU among them, come up as a CD-ROM
# holding the Windows driver (0bda:1a2b, SCSI "RTK Driver Storage") and become the Wi-Fi device only
# once that CD is ejected (what usb_modeswitch's StandardEject and Linux's eject do). usbwifi.hotspot
# unbinds usb-storage and binds rtl8851bu to the CD's interface instead, which the driver refuses
# (0bda:1a2b isn't in its table), so the dongle stayed a CD (2026-11-08 tries). This kernel has no
# CD-ROM driver (sr), only SCSI generic (sg): ALLOW MEDIUM REMOVAL and START STOP UNIT with LoEj go to
# the CD's /dev/sgN through the sg driver's write interface, a 36-byte struct sg_header (pack_len 42,
# reply_len 36: no data) followed by the 6-byte command, in one write each (<RT_BIN>/sg-allow.bin
# and sg-eject.bin, dd bs=42). usb-storage is bound back first when usbwifi.hotspot took it off. Only
# a USB device with a ZEROCD_IDS id whose SCSI vendor is RTK is touched; ZC_MAX tries per plug-in.
ZEROCD_IDS=${ZEROCD_IDS:-0bda:1a2b}
USB_DEVICES=${USB_DEVICES:-/sys/bus/usb/devices}
DEV_DIR=${DEV_DIR:-/dev}
ZC_NODE_TEST=${ZC_NODE_TEST:--c}
ZC_MAX=${ZC_MAX:-4}
ZC_WAIT=${ZC_WAIT:-3}
ZC_SEEN=""; ZC_TRIES=0; ZC_PORT=""
zerocd_sg() {   # zerocd_sg <usb interface dir>: the CD's sg name once its SCSI side is up
    local _s _v
    for _s in "$1"/host*/target*/*:*:*:*/scsi_generic/sg*; do
        [ -d "$_s" ] || continue
        _v=$(cat "${_s%/scsi_generic/*}/vendor" 2>/dev/null)
        case "$_v" in RTK*) putline "${_s##*/}"; return 0 ;; esac
    done
    return 1
}
zerocd_eject() {   # zerocd_eject <usb interface dir>: one try on that interface
    local _if=$1 _i=${1##*/} _sg _n=0
    _sg=$(zerocd_sg "$_if")
    if [ -z "$_sg" ]; then
        [ -e "$USB_DRIVERS/usb-storage/$_i" ] || putline "$_i" > "$USB_DRIVERS/usb-storage/bind" 2>/dev/null
        while [ -z "$_sg" ] && [ $_n -lt "$ZC_WAIT" ]; do
            sleep 1
            _n=$((_n + 1))
            _sg=$(zerocd_sg "$_if")
        done
    fi
    if [ -z "$_sg" ]; then
        say "dongle CD-ROM at $_i: no SCSI device for it (try $ZC_TRIES of $ZC_MAX)"
        return 1
    fi
    if [ ! $ZC_NODE_TEST "$DEV_DIR/$_sg" ]; then
        say "dongle CD-ROM at $_i: no $DEV_DIR/$_sg node (try $ZC_TRIES of $ZC_MAX)"
        return 1
    fi
    dd if="$RT_BIN/sg-allow.bin" of="$DEV_DIR/$_sg" bs=42 count=1 >/dev/null 2>&1
    if dd if="$RT_BIN/sg-eject.bin" of="$DEV_DIR/$_sg" bs=42 count=1 >/dev/null 2>&1; then
        say "dongle CD-ROM at $_i: eject sent through $_sg (try $ZC_TRIES of $ZC_MAX)"
        return 0
    fi
    say "dongle CD-ROM at $_i: writing to $DEV_DIR/$_sg failed (try $ZC_TRIES of $ZC_MAX)"
    return 1
}
zerocd_check() {   # one pass: eject a ZeroCD dongle's CD; say what came up in its place
    local _d _v _p _key _if _n
    [ -n "$RT_BIN" ] && [ -f "$RT_BIN/sg-allow.bin" ] && [ -f "$RT_BIN/sg-eject.bin" ] || return 0
    for _d in "$USB_DEVICES"/*; do
        [ -f "$_d/idVendor" ] || continue
        read -r _v < "$_d/idVendor"
        read -r _p < "$_d/idProduct"
        _n=${_d##*/}
        if [ "$_n" = "$ZC_PORT" ]; then
            case " $ZEROCD_IDS " in *" $_v:$_p "*) ;; *)
                say "USB device at $_n after the CD: $_v:$_p ($(cat "$_d/product" 2>/dev/null))"
                ZC_PORT="" ;;
            esac
        fi
        case " $ZEROCD_IDS " in *" $_v:$_p "*) ;; *) continue ;; esac
        _key="$_n#$(cat "$_d/devnum" 2>/dev/null)"   # a new plug-in gets a new device number
        if [ "$_key" != "$ZC_SEEN" ]; then
            ZC_SEEN=$_key
            ZC_TRIES=0
            ZC_PORT=$_n
            say "dongle CD-ROM $_v:$_p at $_n (a Realtek ZeroCD dongle): ejecting it for the Wi-Fi device"
        fi
        if [ "$ZC_TRIES" -ge "$ZC_MAX" ]; then
            if [ "$ZC_TRIES" = "$ZC_MAX" ]; then
                say "dongle CD-ROM at $_n: still a CD after $ZC_MAX tries, left alone until it's plugged in again"
                ZC_TRIES=$((ZC_MAX + 1))
            fi
            continue
        fi
        ZC_TRIES=$((ZC_TRIES + 1))
        for _if in "$_d"/"$_n":*; do
            [ -d "$_if" ] && zerocd_eject "$_if"
        done
    done
    return 0
}

# tunewatch <parent pid>: every 3 s, so a dongle plugged in (or the phone's first block ack
# session) gets the settings within seconds, and a dongle that comes up as a CD-ROM is ejected
TUNE_EVERY=${TUNE_EVERY:-3}
tunewatch() {
    while kill -0 "$1" 2>/dev/null && [ -z "$DEBUG_STOP" ]; do
        zerocd_check
        tune_rtl
        sleep "$TUNE_EVERY"
    done
}
TUNEWATCH_PID=""
tune_ctl() {
    [ -n "$TUNEWATCH_PID" ] && kill -0 "$TUNEWATCH_PID" 2>/dev/null && return 0
    tunewatch "$$" &
    TUNEWATCH_PID=$!
    return 0
}

# netsample_ctl: keep one sampler running beside the service while debug logging is on
NETSAMPLE_PID=""
netsample_ctl() {
    [ -f "$NODEBUG_FLAG" ] && return 0
    [ -n "$NETSAMPLE_PID" ] && kill -0 "$NETSAMPLE_PID" 2>/dev/null && return 0
    netsample "$$" &
    NETSAMPLE_PID=$!
    return 0
}
