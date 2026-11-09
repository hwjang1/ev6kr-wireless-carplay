#!/bin/sh
# Off-car test of ev6kr.usbap.sync: a fake /data/nemesis, a softap.conf in the stock format 3,
# app_process stood in by the JVM running the helper's classes.
#   tests/apsync-test.sh            (MOCK_SH=mksh to run the scripts with mksh, as on the unit)
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
SH=${MOCK_SH:-sh}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fails=$((fails + 1)); }

mkdir -p "$W/cls" "$W/bin" "$W/nemesis/apps/usbwifi.hotspot/config" "$W/nemesis/apps/ev6kr.usbap.sync" "$W/usbtmp"
javac --release 8 -Xlint:-options -d "$W/cls" apsync/java/ev6kr/cpw/SoftApConf.java
cp -r apsync/scripts apsync/svc apsync/bin "$W/nemesis/apps/ev6kr.usbap.sync/"
cp shared/rtwlan.sh "$W/nemesis/apps/ev6kr.usbap.sync/scripts/"
# app_process /system/bin <class> <args...>  ->  java
cat > "$W/bin/app_process" <<EOF
#!/bin/sh
shift
exec java -cp "$W/cls" "\$@"
EOF
cat > "$W/bin/am" <<EOF
#!/bin/sh
echo "am \$*" >> "$W/am.log"
EOF
cat > "$W/bin/logcat" <<EOF
#!/bin/sh
echo "logcat \$*" >> "$W/logcat.log"
EOF
# the unit's toolbox mv takes no options (Android 4.4): "mv -f a b" fails there
cat > "$W/bin/mv" <<'EOF'
#!/bin/sh
case "$1" in -*) echo "mv: $1: No such file or directory" >&2; exit 1 ;; esac
[ $# = 2 ] || { echo "usage: mv <source> <destination>" >&2; exit 1; }
exec /bin/mv "$1" "$2"
EOF
chmod 755 "$W/bin/app_process" "$W/bin/am" "$W/bin/logcat" "$W/bin/mv"
mkdir -p "$W/proc"

PSK='p'"'"'a"s$s\ w`d!#&;x'
python3 -I - "$W/softap.conf" "$PSK" <<'EOF'
import struct, sys
def utf(s): b = s.encode('utf-8'); return struct.pack('>H', len(b)) + b
d = (struct.pack('>i', 3) + utf('AndroidAP') + utf('Kia_aB3x') + struct.pack('>i', 4) + utf('hotspotpw')
     + utf(sys.argv[2]) + struct.pack('>i', 149) + struct.pack('>i', 1) + b'\x00' + utf('dd0a0017f2') + struct.pack('>i', 2))
open(sys.argv[1], 'wb').write(d)
EOF
CONF=$W/nemesis/apps/usbwifi.hotspot/config/hotspot.conf
# as the dashboard writes it (KEY=value, no quotes)
printf 'WIFI_MODE=ap\nAP_SSID=EV6_Hotspot\nAP_PASS=12345678\nAP_HW_MODE=g\nFORCE_SUBNET=AUTO\n\n# note\nENABLE_LTE_NAT=1\n' > "$CONF"
cp "$CONF" "$W/orig.conf"
# net.core stand-ins (the unit's values)
mkdir -p "$W/sysctl" && echo 1000 > "$W/sysctl/netdev_max_backlog" && echo 300 > "$W/sysctl/netdev_budget"

run() {   # run <script> [args]: one pass, the unit's paths moved under $W
    env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$W/nemesis/apps/ev6kr.usbap.sync" \
        USB_TMP="$W/usbtmp" SOFTAP="$W/softap.conf" PROC="$W/proc" SYSCTL_CORE="$W/sysctl" NEMESIS_STAGE="$W/stage" APSYNC_ONCE=1 $SH "$@"
}
S=$W/nemesis/apps/ev6kr.usbap.sync

# the passphrase rules (letters and digits only, 12 of them, every class present)
[ "$(java -cp "$W/cls" ev6kr.cpw.SoftApConf selftest)" = "selftest: ok" ] && ok "safe passphrase generator and rules" || no "passphrase selftest"
# off-car there's no wifi service: the file is the source (exit 7: read again next pass), nothing replaced
RC=0; (cd "$W" && java -cp cls ev6kr.cpw.SoftApConf usbconf softap.conf "$W/psk.bak" > /dev/null 2> "$W/usbconf.err") || RC=$?
[ $RC = 7 ] && [ ! -f "$W/psk.bak" ] && grep -q "live settings unavailable" "$W/usbconf.err" && ok "no live settings: softap.conf used, nothing replaced" || no "fallback: rc $RC $(cat "$W/usbconf.err")"

run "$S/svc/apsync.sh"
v() { (. "$CONF"; eval "printf '%s' \"\$$1\""); }
[ "$(v AP_SSID)" = Kia_aB3x ] && ok "SSID from ConnectivitySSID" || no "SSID: $(v AP_SSID)"
[ "$(v AP_PASS)" = "$PSK" ] && ok "password survives sourcing (quotes, \$, \\, backquote)" || no "password: $(v AP_PASS)"
[ "$(v AP_HW_MODE)" = a ] && [ "$(v AP_CHANNEL)" = 149 ] && ok "5 GHz channel 149" || no "band: $(v AP_HW_MODE)/$(v AP_CHANNEL)"
[ "$(v FORCE_SUBNET)" = AUTO ] && grep -q '^# note$' "$CONF" && ok "other lines kept" || no "other lines changed"
# the car's LTE no longer shared (as the stock CarPlay hotspot): ENABLE_LTE_NAT 1 -> 0, the 1 saved
[ "$(v ENABLE_LTE_NAT)" = 0 ] && grep -qx 'ENABLE_LTE_NAT=1' "$W/nemesis/backup/ev6kr.usbap.sync/hotspot.keys" \
    && grep -q 'car LTE sharing on the USB hotspot off (ENABLE_LTE_NAT 1 -> 0)' "$W/nemesis/ev6kr.usbap.sync.log" \
    && ok "car LTE sharing off (ENABLE_LTE_NAT 0), its 1 saved for uninstall" || no "LTE sharing: $(v ENABLE_LTE_NAT)"
[ -f "$W/usbtmp/force_restart" ] && ok "USB hotspot restart requested" || no "no restart request"
[ -f "$W/nemesis/backup/ev6kr.usbap.sync/hotspot.keys" ] && ok "backup saved" || no "no backup"
[ "$(cat "$W/sysctl/netdev_max_backlog")" = 5000 ] && [ "$(cat "$W/sysctl/netdev_budget")" = 600 ] \
    && [ "$(cat "$W/nemesis/backup/ev6kr.usbap.sync/sysctl.netdev_max_backlog")" = 1000 ] \
    && ok "receive backlog raised, the first values kept" || no "net tune: $(cat "$W/sysctl/netdev_max_backlog")"

rm -f "$W/usbtmp/force_restart"
cp "$CONF" "$W/after1.conf"
run "$S/svc/apsync.sh"
cmp -s "$CONF" "$W/after1.conf" && [ ! -f "$W/usbtmp/force_restart" ] && ok "second pass changes nothing" || no "second pass rewrote the file"

# the dashboard's own reader (one layer of quotes off): SSID shows as written
python3 -I - "$CONF" <<'EOF' && ok "dashboard reads the SSID" || no "dashboard reads the SSID wrong"
import sys
kv = {}
for l in open(sys.argv[1]):
    t = l.strip()
    if t and not t.startswith('#') and '=' in t:
        k, v = t.split('=', 1); v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'': v = v[1:-1]
        kv[k.strip()] = v
sys.exit(0 if kv['AP_SSID'] == 'Kia_aB3x' else 1)
EOF

# duplicate key lines (last one wins in the daemon): one line left, ours
printf 'AP_SSID=dup\n' >> "$CONF"
run "$S/svc/apsync.sh"
[ "$(grep -c '^AP_SSID=' "$CONF")" = 1 ] && [ "$(v AP_SSID)" = Kia_aB3x ] && ok "duplicate key removed" || no "duplicate key: $(grep '^AP_SSID=' "$CONF")"

# client mode: left alone
cp "$CONF" "$W/before-sta.conf"
sed 's/^WIFI_MODE=ap$/WIFI_MODE=sta/' "$W/before-sta.conf" > "$CONF"
sed 's/^AP_SSID=.*/AP_SSID=Mine/' "$CONF" > "$W/sta.conf" && cp "$W/sta.conf" "$CONF"
run "$S/svc/apsync.sh"
cmp -s "$CONF" "$W/sta.conf" && ok "STA mode left alone" || no "STA mode changed"
cp "$W/before-sta.conf" "$CONF"

# debug logcat: on by default, once (a running logcat is left alone), off with the nodebug flag
sleep 1
grep -q -- "-f $W/nemesis/ev6kr.usbap.sync.logcat.txt -r 1024 -n 4 CarPlay_:V .*Iap2Service:V .*HfDeviceBTCMSppApi:V .*NavigationCluster:S \*:W\$" "$W/logcat.log" \
    && ok "debug logcat started: CarPlay/iAP2/BT tags, others warnings only" || no "debug logcat: $(cat "$W/logcat.log" 2>/dev/null)"
read -r LPID < "$W/nemesis/ev6kr.usbap.sync.logcat.pid"
mkdir -p "$W/proc/$LPID" && echo logcat > "$W/proc/$LPID/comm"
: > "$W/logcat.log"
run "$S/svc/apsync.sh"; sleep 1
[ ! -s "$W/logcat.log" ] && ok "a running debug logcat isn't started twice" || no "second logcat started"
echo sh > "$W/proc/$LPID/comm"
run "$S/svc/apsync.sh"; sleep 1
[ -s "$W/logcat.log" ] && ok "a reused pid isn't taken for the logcat" || no "reused pid taken for logcat"
# stopping kills the recorded pid: give it one of ours (never a pid the mock left behind)
sleep 60 & DPID=$!
echo "$DPID" > "$W/nemesis/ev6kr.usbap.sync.logcat.pid"; mkdir -p "$W/proc/$DPID" && echo logcat > "$W/proc/$DPID/comm"
: > "$W/nemesis/ev6kr.usbap.sync.nodebug"
run "$S/svc/apsync.sh"; sleep 1
if [ ! -f "$W/nemesis/ev6kr.usbap.sync.logcat.pid" ] && ! kill -0 "$DPID" 2>/dev/null && grep -q "debug logcat off" "$W/nemesis/ev6kr.usbap.sync.log"; then
    ok "nodebug flag stops the logcat"
else
    no "nodebug flag"; kill "$DPID" 2>/dev/null || true
fi
rm -f "$W/nemesis/ev6kr.usbap.sync.nodebug"

# hotspot watchdog: a dongle bound to its driver, the newest interface rtwlan1, hostapd still on the
# gone rtwlan0 (no netdev device links on this driver build: binding and ifindex are what count)
for c in ip ifconfig; do printf '#!/bin/sh\necho "%s $*" >> "%s/net.log"\n' "$c" "$W" > "$W/bin/$c"; chmod 755 "$W/bin/$c"; done
mkdir -p "$W/sysnet/rtwlan0" "$W/sysnet/rtwlan1" "$W/usbwork" "$W/drivers/rtl88x2bu/4-1:1.0"
echo 10 > "$W/sysnet/rtwlan0/ifindex"; echo 12 > "$W/sysnet/rtwlan1/ifindex"
echo "interface=rtwlan0" > "$W/usbwork/hostapd.conf"
sleep 60 & HPID=$!; echo "$HPID" > "$W/usbtmp/hostapd.pid"; mkdir -p "$W/proc/$HPID"
rm -f "$W/usbtmp/force_restart"; : > "$W/net.log"
hc() {   # one service pass with the watchdog acting on its first bad check
    env SYSNET="$W/sysnet" USB_DRIVERS="$W/drivers" USB_WORK="$W/usbwork" HEALTH_THRESHOLD=1 EV6KR_TEST_PATH="$W/bin:$PATH" \
        NEMESIS_DIR="$W/nemesis" APP_DIR="$W/nemesis/apps/ev6kr.usbap.sync" USB_TMP="$W/usbtmp" \
        SOFTAP="$W/softap.conf" PROC="$W/proc" SYSCTL_CORE="$W/sysctl" APSYNC_ONCE=1 $SH "$S/svc/apsync.sh"
}
hc
[ -f "$W/usbtmp/force_restart" ] && grep -q "ip addr flush dev rtwlan0" "$W/net.log" && ! grep -q "rtwlan1" "$W/net.log" \
    && ok "watchdog: hostapd left on the old interface -> its address cleared, restart asked" || no "watchdog: $(cat "$W/net.log" 2>/dev/null)"
# healthy: hostapd alive on the newest interface
rm -f "$W/usbtmp/force_restart"; : > "$W/net.log"
echo "interface=rtwlan1" > "$W/usbwork/hostapd.conf"
hc
[ ! -f "$W/usbtmp/force_restart" ] && [ ! -s "$W/net.log" ] && ok "watchdog: a running hotspot is left alone" || no "watchdog touched a running hotspot"
# hostapd gone while the dongle is bound
kill "$HPID" 2>/dev/null || true; wait "$HPID" 2>/dev/null || true; rm -rf "$W/proc/$HPID"
hc
[ -f "$W/usbtmp/force_restart" ] && ok "watchdog: hostapd not running -> restart asked" || no "watchdog: hostapd down not seen"
# no dongle bound (only lingering interfaces): nothing to do
rm -f "$W/usbtmp/force_restart"; rm -rf "$W/drivers/rtl88x2bu/4-1:1.0"
hc
[ ! -f "$W/usbtmp/force_restart" ] && ok "watchdog: no dongle, no restart" || no "watchdog restarted without a dongle"

# network sampler: interface counters, backlog drops, TCP, the dongle driver's station view, the
# established connections' queues (no loopback) and pings to the hotspot's DHCP clients
mkdir -p "$W/proc/net/rtl88x2bu/rtwlan0"
printf 'Inter-|   Receive\n face |bytes    packets errs drop\n    lo:  1 2 0 0\nrtwlan0: 5083311 2358 0 12368\n' > "$W/proc/net/dev"
echo "00000a1b 0000000c 00000000" > "$W/proc/net/softnet_stat"
printf 'Ip: Forwarding\nTcp: RtoAlgorithm RetransSegs\nTcp: 1 42\nUdp: InDatagrams\nUdp: 7\n' > "$W/proc/net/snmp"
printf 'TcpExt: PruneCalled\nTcpExt: 3\nIpExt: InNoRoutes\n' > "$W/proc/net/netstat"
printf '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt\n   0: 0100007F:1F90 0100007F:C350 01 00000000:00000000 00:00000000 00000000\n   1: 012BA8C0:1B58 7B2BA8C0:D2F0 01 00000000:0001F400 00:00000000 00000002\n   2: 00000000:1B58 00000000:0000 0A 00000000:00000000 00:00000000 00000000\n' > "$W/proc/net/tcp"
echo "qos_en=1, ht_en=1" > "$W/proc/net/rtl88x2bu/rtwlan0/all_sta_info"
echo "chplan 0x20" > "$W/proc/net/rtl88x2bu/rtwlan0/chan_plan"
echo "5.8.7.1_35809.20191129" > "$W/proc/net/rtl88x2bu/ver_info"; echo "crash" > "$W/proc/net/rtl88x2bu/drv_cfg"
mkdir -p "$W/sysmod/88x2bu"; echo "v5.8.7.1_35809.20191129" > "$W/sysmod/88x2bu/version"; echo ABC > "$W/sysmod/88x2bu/srcversion"
echo "only seen" > "$W/proc/net/rtl88x2bu/rtwlan0/tx_power_by_rate"
echo "write only" > "$W/proc/net/rtl88x2bu/rtwlan0/write_reg"
echo "123.45 67.89" > "$W/proc/uptime"
echo "1700000000 bc:9f:58:00:00:01 192.168.43.99 old 01:bc:9f:58:00:00:01" > "$W/usbtmp/dnsmasq.leases"
printf 'IP address       HW type     Flags       HW address            Mask     Device\n192.168.43.123   0x1         0x2         bc:9f:58:00:00:01     *        rtwlan0\n192.168.43.77    0x1         0x0         00:00:00:00:00:00     *        rtwlan0\n10.0.0.1         0x1         0x2         aa:bb:cc:dd:ee:ff     *        rmnet0\n' > "$W/proc/net/arp"
cat > "$W/bin/ping" <<EOF
#!/bin/sh
echo "ping \$*" >> "$W/ping.log"
echo "PING 192.168.43.123 (192.168.43.123) 56(84) bytes of data."
echo ""
echo "--- 192.168.43.123 ping statistics ---"
echo "4 packets transmitted, 3 received, 25% packet loss, time 3002ms"
echo "rtt min/avg/max/mdev = 2.103/3.412/5.630/0.712 ms"
EOF
chmod 755 "$W/bin/ping"
sleep 2 & SPID=$!
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_TMP="$W/usbtmp" PROC="$W/proc" SYSMODULE="$W/sysmod" NETSAMPLE_EVERY=1 \
    $SH -c '. "$1/scripts/common.sh"; netsample "$2"' sh "$S" "$SPID"
NS=$W/nemesis/ev6kr.usbap.sync.netsample.txt
if grep -q '^rtwlan0: 5083311 2358 0 12368$' "$NS" && grep -q '^softnet: 00000a1b 0000000c' "$NS" && grep -q '^Tcp: 1 42$' "$NS" \
    && grep -q '^Udp: 7$' "$NS" && grep -q '^TcpExt: 3$' "$NS" && ! grep -q 'IpExt' "$NS" && ! grep -q '^lo:' "$NS"; then
    ok "sampler: interface, backlog and TCP counters"
else
    no "sampler counters: $(cat "$NS" 2>/dev/null)"
fi
grep -q 'qos_en=1, ht_en=1' "$NS" && grep -q 'chplan 0x20' "$NS" && grep -q '^-- driver 88x2bu v5.8.7.1_35809.20191129 srcversion ABC$' "$NS" && ! grep -q 'write only' "$NS" \
    && ! grep -q -E 'drv_cfg|ver_info|crash|only seen' "$NS" \
    && ok "sampler: the dongle driver's station entries (named ones only)" || no "sampler driver entries"
grep -q '^tcp 012BA8C0:1B58 7B2BA8C0:D2F0 q=00000000:0001F400 retr=00000002$' "$NS" && ! grep -q '0100007F:C350' "$NS" && ! grep -q ' 0A ' "$NS" \
    && ok "sampler: established connections with their queues, no loopback" || no "sampler tcp: $(grep '^tcp' "$NS")"
grep -q -- '-s 1400 192.168.43.123' "$W/ping.log" && ! grep -q -E '192.168.43.(99|77)|10.0.0.1' "$W/ping.log" && grep -q '^4 packets transmitted, 3 received' "$NS" \
    && grep -q '^rtt min' "$NS" && ! grep -q '^PING' "$NS" \
    && ok "sampler: pings the hotspot clients in ARP, keeps the summary" || no "sampler ping: $(cat "$W/ping.log" 2>/dev/null)"
: > "$W/nemesis/ev6kr.usbap.sync.nodebug"
sleep 30 & SPID=$!
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_TMP="$W/usbtmp" PROC="$W/proc" SYSMODULE="$W/sysmod" NETSAMPLE_EVERY=1 \
    $SH -c '. "$1/scripts/common.sh"; netsample "$2"' sh "$S" "$SPID"
kill "$SPID" 2>/dev/null || true
[ -f "$NS.1" ] && [ ! -f "$NS" ] && ok "sampler: the last file kept as .1, nothing sampled with nodebug" || no "sampler nodebug/rotation"
rm -f "$W/nemesis/ev6kr.usbap.sync.nodebug" "$W/usbtmp/dnsmasq.leases"

# dongle tuning: block ack left to the driver by default (usbwifi.hotspot's v5.8.7.1 runs fine
# with it); refused from the tune file, once; back to the driver's choice from the tune file
tn() { env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_TMP="$W/usbtmp" PROC="$W/proc" \
    $SH -c '. "$1/scripts/common.sh"; tune_rtl' sh "$S"; }
R=$W/proc/net/rtl88x2bu/rtwlan0
printf 'accept: 1(auto)\nsize: 64(auto) with conditional limit:\n' > "$R/rx_ampdu"; echo unspecified > "$R/country_code"
cp "$R/rx_ampdu" "$W/ra.before"
tn
cmp -s "$R/rx_ampdu" "$W/ra.before" && [ "$(cat "$R/country_code")" = unspecified ] \
    && ok "tune: block ack left to the driver by default, country left alone" || no "tune default: $(cat "$R/rx_ampdu")"
printf 'rx_ampdu=0\n' > "$W/nemesis/ev6kr.usbap.sync.tune"
tn
[ "$(cat "$R/rx_ampdu")" = 0 ] && grep -q "A-MPDU from the phone refused" "$W/nemesis/ev6kr.usbap.sync.log" \
    && ok "tune file: rx_ampdu=0 -> block ack refused" || no "rx_ampdu=0: $(cat "$R/rx_ampdu")"
printf 'accept: 0(fixed)\nsize: 64(auto)\n' > "$R/rx_ampdu"; cp "$R/rx_ampdu" "$W/ra.before"
tn
cmp -s "$R/rx_ampdu" "$W/ra.before" && ok "tune: already set -> not written again" || no "tune rewrote a set value"
printf 'rx_ampdu=auto\ncountry=KR\nchannel=36' > "$W/nemesis/ev6kr.usbap.sync.tune"
tn
[ "$(cat "$R/rx_ampdu")" = 255 ] && [ "$(cat "$R/country_code")" = KR ] && ok "tune file: block ack back to auto, country KR" || no "tune file: $(cat "$R/rx_ampdu") $(cat "$R/country_code")"
rm -f "$W/usbtmp/force_restart"
run "$S/svc/apsync.sh"
[ "$(v AP_CHANNEL)" = 36 ] && [ "$(v AP_HW_MODE)" = a ] && [ "$(v AP_SSID)" = Kia_aB3x ] && [ "$(v AP_PASS)" = "$PSK" ] && [ -f "$W/usbtmp/force_restart" ] \
    && ok "tune file: channel 36, the rest as before, hotspot restarted" || no "tune channel: $(v AP_CHANNEL)/$(v AP_HW_MODE)"
rm -f "$W/nemesis/ev6kr.usbap.sync.tune" "$W/usbtmp/force_restart"
run "$S/svc/apsync.sh"
[ "$(v AP_CHANNEL)" = 149 ] && [ -f "$W/usbtmp/force_restart" ] && ok "tune file gone: the stock channel again" || no "untuned channel: $(v AP_CHANNEL)"
# lte_share=1 in the tune file shares the car's LTE again; gone -> off again
printf 'lte_share=1\n' > "$W/nemesis/ev6kr.usbap.sync.tune"; rm -f "$W/usbtmp/force_restart"
run "$S/svc/apsync.sh"
[ "$(v ENABLE_LTE_NAT)" = 1 ] && [ -f "$W/usbtmp/force_restart" ] && ok "tune file: lte_share=1 -> car LTE shared, hotspot restarted" || no "lte_share=1: $(v ENABLE_LTE_NAT)"
rm -f "$W/nemesis/ev6kr.usbap.sync.tune"
run "$S/svc/apsync.sh"
[ "$(v ENABLE_LTE_NAT)" = 0 ] && ok "tune file gone: car LTE sharing off again" || no "lte_share gone: $(v ENABLE_LTE_NAT)"
# updated from 0.1.11: its backup has no ENABLE_LTE_NAT -> the value as it is then is added before
# it's changed (and only once); the other saved lines untouched
K=$W/nemesis/backup/ev6kr.usbap.sync/hotspot.keys; cp "$K" "$W/keys.full"
grep -v '^ENABLE_LTE_NAT=' "$W/keys.full" > "$K"; cp "$K" "$W/keys.old"
sed 's/^ENABLE_LTE_NAT=.*/ENABLE_LTE_NAT=1/' "$CONF" > "$W/conf.tmp" && cat "$W/conf.tmp" > "$CONF"
run "$S/svc/apsync.sh"; run "$S/svc/apsync.sh"
if [ "$(grep -c '^ENABLE_LTE_NAT=' "$K")" = 1 ] && grep -qx 'ENABLE_LTE_NAT=1' "$K" && [ "$(head -n "$(wc -l < "$W/keys.old")" "$K")" = "$(cat "$W/keys.old")" ] \
    && [ "$(v ENABLE_LTE_NAT)" = 0 ] && cat "$W/nemesis/ev6kr.usbap.sync.log.old" "$W/nemesis/ev6kr.usbap.sync.log" | grep -q "saved the USB hotspot's own ENABLE_LTE_NAT for uninstall"; then
    ok "update from 0.1.11: ENABLE_LTE_NAT saved once, before it's changed"
else
    no "backup upgrade: $(tr '\n' ' ' < "$K")"
fi
# TX path (v5.13.1 driver): the 0x93c register read decodes to the 1-stream path
td() { env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" $SH -c '. "$1/scripts/common.sh"; txp_decode "$2"' sh "$S" "$1"; }
[ "$(td 'rtw_read32(0x93c)=0x00103c3f')" = a ] && [ "$(td 'rtw_read32(0x93c)=0x00203c3f')" = b ] && [ "$(td 'rtw_read32(0x93c)=0x4303c3f')" = ab ] \
    && ! td 'address not initialized' > /dev/null && ok "tx path: register 0x93c read as a / b / ab" || no "txp_decode"
# the path test: one phone on the live interface; the driver entries stood in (the register and
# the phydm command are read back by the driver, not files), each path answering pings differently
mkdir -p "$W/sysnet2/rtwlan0" "$W/drivers/rtl88x2bu/4-1:1.0" "$R/odm"; echo 7 > "$W/sysnet2/rtwlan0/ifindex"
: > "$R/odm/cmd"; : > "$R/read_reg"; echo a > "$W/txmap"; : > "$W/txset.log"
printf 'data_sent_cnt :\t100\nsuccess_cnt :\t60\nfailure_cnt :\t40\nretry_cnt :\t300\n' > "$R/tx_stat"
cat > "$W/bin/ping" <<EOF
#!/bin/sh
case \$(cat "$W/txmap") in a) n=1 ;; b) n=7 ;; *) n=4 ;; esac
echo "PING x"
echo "8 packets transmitted, \$n received, 50% packet loss, time 3000ms"
echo "rtt min/avg/max/mdev = 1.0/2.0/3.0/0.5 ms"
EOF
chmod 755 "$W/bin/ping"
tx() {   # tx <passes> [able]: tune passes in one service process
    env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_TMP="$W/usbtmp" PROC="$W/proc" \
        SYSNET="$W/sysnet2" USB_DRIVERS="$W/drivers" TXP_STEP_TICKS=1 TXP_ROUNDS=1 TXP_SETTLE="${SETTLE:-20}" TXW="$W" TXABLE="${2:-1}" \
        $SH -c '. "$1/scripts/common.sh"
            [ "$TXABLE" = 1 ] && txp_able() { return 0; }
            txp_map() { cat "$TXW/txmap"; }
            txp_set() { echo "$2" > "$TXW/txmap"; echo "$2" >> "$TXW/txset.log"; }
            i=0; while [ $i -lt "$2" ]; do tune_rtl; i=$((i + 1)); done' sh "$S" "$1"
}
printf 'txpath=cycle\n' > "$W/nemesis/ev6kr.usbap.sync.tune"; : > "$W/nemesis/ev6kr.usbap.sync.log"; rm -f "$NS"
tx 4
if [ "$(cat "$W/txset.log" | tr '\n' ' ')" = "a b ab b " ] && [ "$(cat "$W/txmap")" = b ] \
    && grep -q 'TX path b (step 2/3): 7 of 8 ping replies (192.168.43.123: 8 packets transmitted, 7 received, 50% packet loss rtt min/avg/max/mdev = 1.0/2.0/3.0/0.5 ms); sent=100 ok=60 fail=40 retry=300' "$W/nemesis/ev6kr.usbap.sync.log" \
    && grep -q 'path test: replies a=1 b=7 ab=4 -> b stays' "$W/nemesis/ev6kr.usbap.sync.log" && grep -q -- '-- .*rtwlan0 txpath ab: phydm bbinfo' "$NS"; then
    ok "tx path test: a, b, both in turn with pings; the best (b) stays"
else
    no "tx path test: $(cat "$W/txset.log" | tr '\n' ' ') / $(cat "$W/nemesis/ev6kr.usbap.sync.log")"
fi
# crash guard: this boot's id on disk while the path moves; a guard left by an earlier boot turns
# the test off (txpath=driver in the tune file, the other lines kept); gone once the path has held
G=$W/nemesis/ev6kr.usbap.sync.txp-guard
mkdir -p "$W/proc/sys/kernel/random"; echo boot-A > "$W/proc/sys/kernel/random/boot_id"
rm -f "$G"; : > "$W/txset.log"; echo a > "$W/txmap"
tx 2
[ "$(cat "$G" 2>/dev/null)" = boot-A ] && [ "$(cat "$W/txset.log" | tr '\n' ' ')" = "a b " ] \
    && ok "tx path guard: this boot's id on disk while the path test runs" || no "guard while cycling: '$(cat "$G" 2>/dev/null)' / $(cat "$W/txset.log" | tr '\n' ' ')"
echo boot-B > "$W/proc/sys/kernel/random/boot_id"; : > "$W/txset.log"
printf 'rx_ampdu=auto\ntxpath=cycle' > "$W/nemesis/ev6kr.usbap.sync.tune"
tx 3
TF=$W/nemesis/ev6kr.usbap.sync.tune
if [ ! -s "$W/txset.log" ] && [ ! -f "$G" ] && [ "$(grep -c '^txpath=' "$TF")" = 1 ] && grep -qx 'txpath=driver' "$TF" && grep -qx 'rx_ampdu=auto' "$TF" && grep -q '^#txpath-off ' "$TF" \
    && grep -q 'TX path test turned off: the head unit went down within a minute of a TX path change' "$W/nemesis/ev6kr.usbap.sync.log"; then
    ok "tx path guard: an earlier boot went down during the test -> off for good, txpath=driver"
else
    no "guard from an earlier boot: $(cat "$W/txset.log" | tr '\n' ' ') / $(cat "$W/nemesis/ev6kr.usbap.sync.tune" | tr '\n' ' ')"
fi
printf 'txpath=ab\n' > "$W/nemesis/ev6kr.usbap.sync.tune"; : > "$W/txset.log"; echo a > "$W/txmap"
SETTLE=3; tx 2
[ -f "$G" ] && [ "$(cat "$W/txset.log")" = ab ] && ok "tx path guard: kept for a while after the path changed" || no "guard after a change: $(cat "$W/txset.log")"
tx 3; SETTLE=20
[ ! -f "$G" ] && [ "$(cat "$W/txmap")" = ab ] && ok "tx path guard: gone once the path has held" || no "guard not cleared"
printf 'txpath=cycle\n' > "$W/nemesis/ev6kr.usbap.sync.tune"
# no phone on the hotspot yet: nothing moved
: > "$W/txset.log"; echo a > "$W/txmap"; cp "$W/proc/net/arp" "$W/arp.keep"; head -1 "$W/arp.keep" > "$W/proc/net/arp"
tx 3
[ ! -s "$W/txset.log" ] && ok "tx path test waits for a phone" || no "tx path moved without a phone: $(cat "$W/txset.log")"
cp "$W/arp.keep" "$W/proc/net/arp"
# a fixed path from the tune file, set again after the driver reset it; then back to the driver's
printf 'txpath=ab\n' > "$W/nemesis/ev6kr.usbap.sync.tune"; : > "$W/txset.log"; echo a > "$W/txmap"
tx 1
[ "$(cat "$W/txset.log")" = ab ] && grep -q '1-stream frames from TX path ab (was a)' "$W/nemesis/ev6kr.usbap.sync.log" && ok "tune file: txpath=ab" || no "txpath=ab: $(cat "$W/txset.log")"
printf 'txpath=driver\n' > "$W/nemesis/ev6kr.usbap.sync.tune"; echo ab > "$W/txmap"; : > "$W/txset.log"
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" PROC="$W/proc" SYSNET="$W/sysnet2" USB_DRIVERS="$W/drivers" TXW="$W" \
    $SH -c '. "$1/scripts/common.sh"; txp_able() { return 0; }; txp_map() { cat "$TXW/txmap"; }
        txp_set() { echo "$2" > "$TXW/txmap"; echo "$2" >> "$TXW/txset.log"; }
        TXP_DIR=$(txp_live); TXP_OK=1; TXP_SET=ab; tune_rtl' sh "$S"
[ "$(cat "$W/txset.log")" = a ] && grep -q "TX path back to the driver's (A)" "$W/nemesis/ev6kr.usbap.sync.log" && ok "txpath=driver: path A again" || no "txpath=driver: $(cat "$W/txset.log")"
# the default: the path left to the driver (no test runs)
rm -f "$W/nemesis/ev6kr.usbap.sync.tune"; : > "$W/txset.log"; echo a > "$W/txmap"
tx 3
[ ! -s "$W/txset.log" ] && ok "tx path: left to the driver by default" || no "default tx path moved: $(cat "$W/txset.log")"
printf 'txpath=cycle\n' > "$W/nemesis/ev6kr.usbap.sync.tune"
# an older driver (no 1-stream path form): the path is never written, even with the test asked for
: > "$W/txset.log"; echo a > "$W/txmap"
tx 3 0
[ ! -s "$W/txset.log" ] && ok "tx path: an older driver is left alone" || no "older driver got a path: $(cat "$W/txset.log")"
# TX power: txpower=3 -> 300 mB below; already so -> not written; gone -> the driver's power
printf 'mode:DISABLE(0)\n' > "$R/tpc_settings"; printf 'txpower=3\n' > "$W/nemesis/ev6kr.usbap.sync.tune"
tx 1 0
[ "$(cat "$R/tpc_settings")" = "1 300" ] && grep -q 'TX power 3 dB lower' "$W/nemesis/ev6kr.usbap.sync.log" && ok "tune file: txpower=3" || no "txpower: $(cat "$R/tpc_settings")"
printf 'mode:MANUAL(1)\nconstraint:300 (mB)\n' > "$R/tpc_settings"; cp "$R/tpc_settings" "$W/tpc.before"
tx 1 0
cmp -s "$R/tpc_settings" "$W/tpc.before" && ok "txpower: already so -> not written again" || no "txpower rewrote: $(cat "$R/tpc_settings")"
rm -f "$W/nemesis/ev6kr.usbap.sync.tune"
tx 1 0
[ "$(cat "$R/tpc_settings")" = 0 ] && ok "txpower gone: the driver's power again" || no "txpower reset: $(cat "$R/tpc_settings")"
printf 'mode:DISABLE(0)\n' > "$R/tpc_settings"
rm -rf "$W/drivers/rtl88x2bu/4-1:1.0"

# net.core: a value saved by 0.1.5/0.1.6 (its first byte only) goes back as the kernel default
echo 1 > "$W/nemesis/backup/ev6kr.usbap.sync/sysctl.netdev_max_backlog"
cp "$W/sysctl/netdev_max_backlog" "$W/nb.before"
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" SYSCTL_CORE="$W/sysctl" $SH -c '. "$1/scripts/common.sh"; net_untune' sh "$S"
[ "$(cat "$W/sysctl/netdev_max_backlog")" = 1000 ] && ok "net untune: a one-digit saved value -> the kernel default" || no "net untune wrote $(cat "$W/sysctl/netdev_max_backlog")"
echo 1000 > "$W/nemesis/backup/ev6kr.usbap.sync/sysctl.netdev_max_backlog"; cp "$W/nb.before" "$W/sysctl/netdev_max_backlog"

# ZeroCD dongle (ipTIME AX900UA's RTL8831BU as a CD-ROM, 0bda:1a2b): its CD is ejected through its
# sg node (the sg_header + command files), usb-storage bound back when it was taken off, a few tries
# per plug-in, what comes up afterwards reported; another USB disk and the 8851bu /proc left alone
B=$S/bin
if [ "$(wc -c < "$B/sg-eject.bin" | tr -d ' ')" = 42 ] && [ "$(wc -c < "$B/sg-allow.bin" | tr -d ' ')" = 42 ] \
    && [ "$(od -An -tx1 -j0 -N8 "$B/sg-eject.bin" | tr -d ' \n')" = 2a00000024000000 ] \
    && [ "$(od -An -tx1 -j36 -N6 "$B/sg-eject.bin" | tr -d ' \n')" = 1b0000000200 ] \
    && [ "$(od -An -tx1 -j36 -N6 "$B/sg-allow.bin" | tr -d ' \n')" = 1e0000000000 ]; then
    ok "sg command files: 36-byte sg_header (pack_len 42, reply_len 36) + ALLOW MEDIUM REMOVAL / START STOP UNIT eject"
else
    no "sg command files: $(od -An -tx1 "$B/sg-eject.bin" | tr -d '\n')"
fi
Z=$W/zc; U=$Z/usb; mkdir -p "$Z/dev" "$Z/drivers/usb-storage"
zdev() {   # zdev <port> <vid> <pid> <devnum> <product>
    mkdir -p "$U/$1/$1:1.0"; echo "$2" > "$U/$1/idVendor"; echo "$3" > "$U/$1/idProduct"; echo "$4" > "$U/$1/devnum"; echo "$5" > "$U/$1/product"
}
zscsi() {  # zscsi <port> <host> <sg> <vendor>: usb-storage bound, its SCSI device and sg node up
    L="$U/$1/$1:1.0/host$2/target$2:0:0/$2:0:0:0"; mkdir -p "$L/scsi_generic/$3" "$Z/drivers/usb-storage/$1:1.0"
    printf '%-8s\n' "$4" > "$L/vendor"; : > "$Z/dev/$3"
}
zc() {     # zc <passes>: CD passes in one service process
    env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_DEVICES="$U" USB_DRIVERS="$Z/drivers" \
        DEV_DIR="$Z/dev" ZC_NODE_TEST=-f ZC_WAIT=0 ZC_MAX=2 \
        $SH -c '. "$1/scripts/common.sh"; i=0; while [ $i -lt "$2" ]; do zerocd_check; i=$((i + 1)); done' sh "$S" "$1"
}
L0=$W/nemesis/ev6kr.usbap.sync.log
zdev 4-1 0bda 1a2b 3 DISK; zscsi 4-1 0 sg1 RTK; zdev 2-1 0781 5567 2 "Cruzer Blade"; zscsi 2-1 1 sg0 SanDisk
: > "$L0"; zc 1
if cmp -s "$Z/dev/sg1" "$B/sg-eject.bin" && [ ! -s "$Z/dev/sg0" ] && grep -q 'dongle CD-ROM 0bda:1a2b at 4-1' "$L0" \
    && grep -q 'dongle CD-ROM at 4-1:1.0: eject sent through sg1 (try 1 of 2)' "$L0"; then
    ok "ZeroCD: the dongle's CD ejected through its sg node, the USB stick untouched"
else
    no "ZeroCD eject: $(tr '\n' ' ' < "$L0")"
fi
# usbwifi.hotspot took usb-storage off: bound back; no SCSI device yet -> said, tried again, then left alone
rm -rf "$U/4-1/4-1:1.0/host0" "$Z/drivers/usb-storage/4-1:1.0"; : > "$Z/dev/sg1"; : > "$L0"; : > "$Z/drivers/usb-storage/bind"
zc 4
if [ "$(cat "$Z/drivers/usb-storage/bind")" = "4-1:1.0" ] && [ "$(grep -c 'no SCSI device for it' "$L0")" = 2 ] \
    && [ "$(grep -c 'still a CD after 2 tries' "$L0")" = 1 ] && [ ! -s "$Z/dev/sg1" ]; then
    ok "ZeroCD: usb-storage bound back, 2 tries, then left alone"
else
    no "ZeroCD retries: $(tr '\n' ' ' < "$L0")"
fi
# no device node for the sg -> said, nothing written
zscsi 4-1 0 sg1 RTK; rm -f "$Z/dev/sg1"; : > "$L0"; echo 4 > "$U/4-1/devnum"
zc 1
grep -q 'no .*/dev/sg1 node' "$L0" && [ ! -e "$Z/dev/sg1" ] && ok "ZeroCD: no /dev node -> said, nothing written" || no "ZeroCD no node: $(tr '\n' ' ' < "$L0")"
# ejected, then the Wi-Fi device at the same port is reported
: > "$Z/dev/sg1"; : > "$L0"; echo 5 > "$U/4-1/devnum"
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" USB_DEVICES="$U" USB_DRIVERS="$Z/drivers" \
    DEV_DIR="$Z/dev" ZC_NODE_TEST=-f ZC_WAIT=0 ZC_MAX=2 ZU="$U" \
    $SH -c '. "$1/scripts/common.sh"; zerocd_check; rm -rf "$ZU/4-1/4-1:1.0/host0"; echo b831 > "$ZU/4-1/idProduct"; echo 6 > "$ZU/4-1/devnum"
        echo "802.11ax WLAN Adapter" > "$ZU/4-1/product"; zerocd_check; zerocd_check' sh "$S"
if grep -q 'eject sent through sg1' "$L0" && [ "$(grep -c 'USB device at 4-1 after the CD: 0bda:b831 (802.11ax WLAN Adapter)' "$L0")" = 1 ]; then
    ok "ZeroCD: the device that comes up afterwards is reported once"
else
    no "ZeroCD after: $(tr '\n' ' ' < "$L0")"
fi
# the 8851bu driver's /proc entries are never touched by the tuning
mkdir -p "$W/proc/net/rtl8851bu/rtwlan1"; echo "accept: 1(auto)" > "$W/proc/net/rtl8851bu/rtwlan1/rx_ampdu"; cp "$W/proc/net/rtl8851bu/rtwlan1/rx_ampdu" "$W/ra8851.before"
printf 'rx_ampdu=0\ncountry=KR\n' > "$W/nemesis/ev6kr.usbap.sync.tune"
env EV6KR_TEST_PATH="$W/bin:$PATH" NEMESIS_DIR="$W/nemesis" APP_DIR="$S" PROC="$W/proc" $SH -c '. "$1/scripts/common.sh"; tune_rtl' sh "$S"
cmp -s "$W/proc/net/rtl8851bu/rtwlan1/rx_ampdu" "$W/ra8851.before" && [ ! -e "$W/proc/net/rtl8851bu/rtwlan1/country_code" ] \
    && ok "8851bu /proc left alone by the tuning" || no "8851bu /proc written: $(cat "$W/proc/net/rtl8851bu/rtwlan1/rx_ampdu")"
rm -rf "$W/proc/net/rtl8851bu" "$W/nemesis/ev6kr.usbap.sync.tune"

# the app: sync + toast
run "$S/bin/sync-now.sh" && grep -q 'Kia_aB3x' "$W/am.log" && ok "app toasts the SSID" || no "app"

# update: NEMESIS has the new version staged when it runs the old preuninstall -> nothing put back
cp "$CONF" "$W/before-update.conf"; rm -f "$W/usbtmp/force_restart"
mkdir -p "$W/stage/ev6kr.usbap.sync" && cp "$S/NEMESIS.data" "$W/stage/ev6kr.usbap.sync/" 2>/dev/null || echo "[nemesis]" > "$W/stage/ev6kr.usbap.sync/NEMESIS.data"
: > "$W/nemesis/ev6kr.usbap.sync.nodebug"
run "$S/scripts/preun.sh"
if cmp -s "$CONF" "$W/before-update.conf" && [ ! -f "$W/usbtmp/force_restart" ] && [ -f "$W/nemesis/backup/ev6kr.usbap.sync/hotspot.keys" ] \
    && [ "$(cat "$W/sysctl/netdev_max_backlog")" = 5000 ] && [ -f "$W/nemesis/ev6kr.usbap.sync.nodebug" ] && grep -q "for an update" "$W/nemesis/ev6kr.usbap.sync.log"; then
    ok "update: the hotspot keeps the CarPlay settings, backups and flags stay"
else
    no "update preuninstall changed things"
fi
rm -rf "$W/stage" "$W/nemesis/ev6kr.usbap.sync.nodebug"

# uninstall: the file is back byte for byte
run "$S/scripts/preun.sh"
cmp -s "$CONF" "$W/orig.conf" && ok "uninstall restores the original file exactly" || { no "uninstall left changes"; diff "$W/orig.conf" "$CONF" || true; }
[ "$(cat "$W/sysctl/netdev_max_backlog")" = 1000 ] && [ "$(cat "$W/sysctl/netdev_budget")" = 300 ] && [ "$(cat "$R/rx_ampdu")" = 255 ] \
    && ok "uninstall puts the receive backlog and the block ack setting back" || no "net untune: $(cat "$W/sysctl/netdev_max_backlog")"

# postinstall: the helper's masked view, no password in the log
(cd "$S" && run "$S/scripts/post.sh" >/dev/null)
grep -q "CP_PSK='${#PSK} chars'" "$W/nemesis/ev6kr.usbap.sync.log" && ! grep -q 'p.a"s' "$W/nemesis/ev6kr.usbap.sync.log" && ok "log masks the password" || no "log shows the password"

echo "$fails failed"
[ $fails = 0 ]
