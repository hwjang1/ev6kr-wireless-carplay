#!/bin/sh
# Off-car test of usb-hotspot-kr's service (hotspot/scripts/usbap.sh): a fake /proc, /sys and
# softap.conf, stand-ins for insmod, ip, hostapd, dnsmasq, getprop and app_process (the JVM runs
# the real SoftApConf).
#   tests/hotspot-test.sh            (MOCK_SH=mksh to run the scripts with mksh, as on the unit)
set -e
cd "$(dirname "$0")/.."
SH=${MOCK_SH:-sh}
W=$(mktemp -d)
cleanup() {
    for f in "$W"/proc/*/comm; do
        [ -f "$f" ] || continue
        p=${f%/comm}; p=${p##*/}
        kill "$p" 2>/dev/null || true
    done
    rm -rf "$W"
}
trap cleanup EXIT; [ -n "$KEEP" ] && trap "echo kept $W" EXIT
fails=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fails=$((fails + 1)); }

M=$W/mod
mkdir -p "$M/svc" "$M/scripts" "$M/modules" "$W/cls" "$W/bin" "$W/data" "$W/run" "$W/nemesis/apps" \
    "$W/proc/sys/kernel/random" "$W/proc/net" "$W/usbdev" "$W/sysmod" "$W/sysnet" "$W/drivers" "$W/sysctl"
cp hotspot/svc/usbap.sh "$M/svc/"; cp hotspot/scripts/usbap.sh shared/rtwlan.sh "$M/scripts/"
javac --release 8 -Xlint:-options -d "$W/cls" apsync/java/ev6kr/cpw/SoftApConf.java
echo fake-ko > "$M/modules/88x2bu_tcc803x.ko"
printf '0bda:b812\n0bda:b82c\n' > "$M/modules/88x2bu_tcc803x.ids"
echo 4E6C0461198FFCF4CE5EBDA > "$M/modules/88x2bu_tcc803x.srcversion"
echo boot-1 > "$W/proc/sys/kernel/random/boot_id"
: > "$W/proc/modules"
printf '  sl  local_address rem_address   st\n   0: 00000000:14E9 00000000:0000 07\n' > "$W/proc/net/udp"
printf 'IP address       HW type     Flags       HW address            Mask     Device\n' > "$W/proc/net/arp"
echo 1000 > "$W/sysctl/netdev_max_backlog"; echo 300 > "$W/sysctl/netdev_budget"

PSK='p'"'"'a"s$s\ w`d!#&;x'
mksoftap() {   # mksoftap <ssid>: softap.conf in the stock format 3
    python3 -I - "$W/softap.conf" "$1" "$PSK" <<'EOF'
import struct, sys
def utf(s): b = s.encode('utf-8'); return struct.pack('>H', len(b)) + b
d = (struct.pack('>i', 3) + utf('AndroidAP') + utf(sys.argv[2]) + struct.pack('>i', 4) + utf('hotspotpw')
     + utf(sys.argv[3]) + struct.pack('>i', 149) + struct.pack('>i', 1) + b'\x00' + utf('dd0a0017f2') + struct.pack('>i', 2))
open(sys.argv[1], 'wb').write(d)
EOF
}
mksoftap Kia_aB3x

# stand-ins
cat > "$W/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in ro.board.platform) echo tcc803x ;; esac
EOF
cat > "$W/bin/app_process" <<EOF
#!/bin/sh
shift
exec java -cp "$W/cls" "\$@"
EOF
# the kernel taking a dongle on the bus (unless its start fails): the binding and rtwlan0
cat > "$W/bin/probe" <<EOF
#!/bin/sh
[ -d "$W/usbdev/1-1" ] && grep -q '^88x2bu ' "$W/proc/modules" && [ ! -f "$W/probe.fail" ] || exit 0
mkdir -p "$W/sysnet/rtwlan0" "$W/drivers/rtl88x2bu/1-1:1.0"
echo 9 > "$W/sysnet/rtwlan0/ifindex"
EOF
cat > "$W/bin/insmod" <<EOF
#!/bin/sh
echo "insmod \$*" >> "$W/insmod.log"
[ -f "$W/insmod.fail" ] && { echo "insmod: init_module '\$1' failed (Exec format error)"; exit 1; }
echo "88x2bu 4015604 0 - Live 0x00000000 (O)" >> "$W/proc/modules"
mkdir -p "$W/sysmod/88x2bu" "$W/drivers/rtl88x2bu"
echo 4E6C0461198FFCF4CE5EBDA > "$W/sysmod/88x2bu/srcversion"
echo v5.13.1-20-gbd7c7eb9d > "$W/sysmod/88x2bu/version"
"$W/bin/probe"
EOF
cat > "$W/bin/ip" <<EOF
#!/bin/sh
echo "ip \$*" >> "$W/ip.log"
case "\$*" in
    "rule show") printf '0:\tfrom all lookup local \n10000:\tfrom all fwmark 0x0/0xffff lookup 60 \n10500:\tfrom all oif rmnet0 lookup 61 \n32766:\tfrom all lookup main \n32767:\tfrom all lookup default \n' ;;
    "-4 addr show dev "*) echo "    inet 192.168.43.1/24 brd 192.168.43.255 scope global \$5" ;;
esac
EOF
cat > "$W/bin/hostapd" <<EOF
#!/bin/sh
echo "hostapd \$*" >> "$W/hostapd.starts"
cat "\$3" > "$W/hostapd.conf.seen"
[ -f "$W/hostapd.crash" ] && exit 1
mkdir -p "$W/proc/\$\$" && echo hostapd > "$W/proc/\$\$/comm"
exec /bin/sleep 300
EOF
cat > "$W/bin/dnsmasq" <<EOF
#!/bin/sh
echo "dnsmasq \$*" >> "$W/dnsmasq.args"
for a in "\$@"; do case "\$a" in --pid-file=*) echo \$\$ > "\${a#--pid-file=}" ;; esac; done
mkdir -p "$W/proc/\$\$" && echo dnsmasq > "$W/proc/\$\$/comm"
# (a background job's stdin is /dev/null unless given: hand it the pipe through fd 3)
exec 3<&0
cat <&3 > "$W/dnsmasq.stdin" &
exec /bin/sleep 300
EOF
cat > "$W/bin/sleepstub" <<EOF
#!/bin/sh
mkdir -p "$W/proc/\$\$" && echo sleep > "$W/proc/\$\$/comm"
exec /bin/sleep 300
EOF
# the service's own short waits: 0.3 s here (the background tuning loop sleeps for real)
cat > "$W/bin/sleep" <<'EOF'
#!/bin/sh
case "$1" in 0) exit 0 ;; 1|2) exec /bin/sleep 0.3 ;; esac
exec /bin/sleep "$1"
EOF
printf '#!/bin/sh\necho "logcat $*" >> "%s/logcat.log"\n' "$W" > "$W/bin/logcat"
printf '#!/bin/sh\necho "chown $*" >> "%s/chown.log"\n' "$W" > "$W/bin/chown"
printf '#!/bin/sh\nexit 0\n' > "$W/bin/log"
chmod 755 "$W"/bin/*

# us <commands>: the service's functions in one shell, the unit's paths moved under $W
us() {
    env EV6KR_TEST_PATH="$W/bin:$PATH" MOD_DIR="$M" DATA="$W/data" RUN="$W/run" NEMESIS_DIR="$W/nemesis" \
        SOFTAP="$W/softap.conf" PROC="$W/proc" USB_DEVICES="$W/usbdev" SYSMODULE="$W/sysmod" SYSNET="$W/sysnet" \
        USB_DRIVERS="$W/drivers" SYSCTL_CORE="$W/sysctl" HOSTAPD="$W/bin/hostapd" DNSMASQ="$W/bin/dnsmasq" \
        SLEEP_BIN="$W/bin/sleepstub" HOOK_DIR="$W/hook" INTERVAL=0 TUNE_EVERY=1 W="$W" \
        $SH -c '. "$MOD_DIR/scripts/usbap.sh"; drv_files; '"$1"
}
L=$W/data/usbap.log
dongle() { mkdir -p "$W/usbdev/1-1/1-1:1.0"; echo 0bda > "$W/usbdev/1-1/idVendor"; echo b812 > "$W/usbdev/1-1/idProduct"; "$W/bin/probe"; }
unplug() { rm -rf "$W/usbdev/1-1" "$W/drivers/rtl88x2bu/1-1:1.0" "$W/sysnet/rtwlan0"; }
: > "$W/data/usbap.nodebug"   # the debug logcat and sampler: their own test below

# usbwifi.hotspot installed: this mod stays off
mkdir -p "$W/nemesis/apps/usbwifi.hotspot"; dongle
us 'stale_cleanup; USBAP_PASSES=2 usbap_main'
[ ! -f "$W/insmod.log" ] && [ ! -f "$W/hostapd.starts" ] && grep -q "usbwifi.hotspot is installed and runs the hotspot" "$L" \
    && ok "usbwifi.hotspot installed: stays off" || no "standoff: $(cat "$L")"
rm -rf "$W/nemesis/apps/usbwifi.hotspot"

# no dongle: waits, loads nothing
unplug
us 'usbap_pass; usbap_pass'
[ ! -f "$W/insmod.log" ] && grep -q "waiting for a USB Wi-Fi dongle" "$L" && ok "no dongle: waits, no driver" || no "no dongle"

# the service at boot, no dongle yet: the driver goes in first (it takes the dongle as it appears);
# HMG-API's boot guard tripped is logged
mkdir -p "$W/hook"; echo 3 > "$W/hook/starts"
us 'USBAP_PASSES=1 usbap_main'
grep -q "^insmod $M/modules/88x2bu_tcc803x.ko " "$W/insmod.log" && [ ! -f "$W/hostapd.starts" ] && grep -q "HMG-API's boot guard has its hooks off (hook/starts=3" "$L" \
    && ok "service start: driver loaded before the dongle; boot guard reported" || no "early driver: $(cat "$W/insmod.log" 2>/dev/null) / $(cat "$L")"
echo 0 > "$W/hook/starts"
# the dongle's start fails (driver loaded, interface never taken): bound again once, then a replug asked
: > "$W/probe.fail"; dongle; : > "$L"
us 'i=0; while [ $i -lt 8 ]; do usbap_pass; i=$((i + 1)); done'
[ "$(cat "$W/drivers/rtl88x2bu/bind" 2>/dev/null)" = "1-1:1.0" ] && grep -q "asked it to try again" "$L" && grep -q "unplug it and plug it back in" "$L" \
    && [ ! -f "$W/hostapd.starts" ] && ok "dongle start failed: bind tried once, then a replug asked" || no "probe failure: $(cat "$L")"
rm -f "$W/probe.fail" "$W/drivers/rtl88x2bu/bind"; unplug; : > "$W/proc/modules"; rm -rf "$W/sysmod/88x2bu"; : > "$W/insmod.log"

# a dongle: the driver with the daemon's parameters, then the hotspot on the stock CarPlay settings,
# the phone's A-MPDU refused before hostapd starts
mkdir -p "$W/proc/net/rtl88x2bu/rtwlan0"; printf 'accept: 1(auto)\nsize: 64(auto)\n' > "$W/proc/net/rtl88x2bu/rtwlan0/rx_ampdu"
dongle; : > "$L"
us 'usbap_pass'
grep -q "^insmod $M/modules/88x2bu_tcc803x.ko rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0 rtw_en_napi=0 rtw_en_gro=0 ifname=rtwlan%d if2name=rtwlan%d$" "$W/insmod.log" \
    && grep -q "driver loaded: 88x2bu v5.13.1" "$L" && ok "dongle: driver loaded with power saving and NAPI/GRO off, rtwlan names" || no "insmod: $(cat "$W/insmod.log")"
C=$W/hostapd.conf.seen
if grep -qx 'interface=rtwlan0' "$C" && grep -qx 'ssid=Kia_aB3x' "$C" && grep -qx 'channel=149' "$C" && grep -qx 'hw_mode=a' "$C" \
    && grep -qx 'driver=nl80211' "$C" && grep -qx 'wpa=2' "$C" && grep -qx 'rsn_pairwise=CCMP' "$C" && grep -qx 'ieee80211n=1' "$C" \
    && [ "$(grep '^wpa_passphrase=' "$C")" = "wpa_passphrase=$PSK" ]; then
    ok "hostapd: stock CarPlay SSID and passphrase (symbols kept as they are), 5 GHz channel 149"
else
    no "hostapd.conf: $(cat "$C")"
fi
[ "$(ls -l "$W/run/hostapd.conf" | cut -c1-10)" = "-rw-------" ] && [ "$(ls -ld "$W/run" | cut -c1-10)" = "drwxr-xr-x" ] \
    && [ "$(ls -l "$W/run/hostapd.pid" | cut -c1-10)" = "-rw-r--r--" ] && [ "$(cat "$W/run/iface")" = rtwlan0 ] \
    && ok "files: passphrase readable by its owner only; hostapd.pid and the interface readable (the CarPlay mod looks)" || no "file modes: $(ls -l "$W/run")"
grep -q "^chown 1010:1010 $W/run/hostapd.conf$" "$W/chown.log" && grep -q "^chown 1010:1010 $W/run/ctrl $W/run/entropy.bin$" "$W/chown.log" \
    && [ "$(ls -l "$W/run/entropy.bin" | cut -c1-10)" = "-rw-------" ] && [ "$(ls -ld "$W/run/ctrl" | cut -c1-10)" = "drwxrwx---" ] \
    && ok "hostapd's settings, entropy file and control folder given to its wifi user (1010)" || no "hostapd ownership: $(cat "$W/chown.log" 2>/dev/null)"
grep -q "^ip addr add 192.168.43.1/24 broadcast 192.168.43.255 dev rtwlan0$" "$W/ip.log" \
    && grep -q "^ip route replace 192.168.43.0/24 dev rtwlan0 table 60$" "$W/ip.log" && grep -q "^ip route replace 192.168.43.0/24 dev rtwlan0 table 61$" "$W/ip.log" \
    && ! grep -q -E "table (local|main|default)" "$W/ip.log" && ok "address 192.168.43.1/24, the subnet in the policy routing tables (60, 61)" || no "ip: $(cat "$W/ip.log")"
D=$W/dnsmasq.args
grep -q -- '--interface=rtwlan0' "$D" && grep -q -- '--port=0' "$D" && grep -q -- '--dhcp-range=192.168.43.10,192.168.43.100,12h' "$D" \
    && grep -q -- '--dhcp-option=3 --dhcp-option=6 ' "$D" && [ "$(cat "$W/dnsmasq.stdin")" = "update_ifaces:rtwlan0" ] \
    && [ "$(od -c "$W/dnsmasq.stdin" | grep -c '\\n')" = 0 ] && ok "dnsmasq: DHCP only on rtwlan0, no gateway or DNS; interfaces on stdin, no newline" \
    || no "dnsmasq: $(cat "$D") / $(od -c "$W/dnsmasq.stdin")"
grep -q "hotspot on rtwlan0: SSID Kia_aB3x, channel 149" "$L" && ok "log: hotspot up" || no "log: $(cat "$L")"
[ "$(cat "$W/proc/net/rtl88x2bu/rtwlan0/rx_ampdu")" = 0 ] && grep -q "A-MPDU from the phone refused" "$L" && ok "A-MPDU refused before hostapd" || no "rx_ampdu: $(cat "$W/proc/net/rtl88x2bu/rtwlan0/rx_ampdu")"

# the service again in the same boot (HMG-API restarted it): the old daemons go, one new start, then healthy
HP=$(cat "$W/run/hostapd.pid"); : > "$W/hostapd.starts"
us 'stale_cleanup; usbap_pass; usbap_pass'
! kill -0 "$HP" 2>/dev/null && [ "$(grep -c . "$W/hostapd.starts")" = 1 ] && grep -q "service restarted" "$L" \
    && ok "service restart: old hostapd stopped, started once, then left alone" || no "restart: $(cat "$W/hostapd.starts")"

# a reboot: the pid files name other processes now, nothing is killed
sleep 60 & OTHER=$!
echo "$OTHER" > "$W/run/hostapd.pid"; mkdir -p "$W/proc/$OTHER"; echo hostapd > "$W/proc/$OTHER/comm"
echo boot-2 > "$W/proc/sys/kernel/random/boot_id"
us 'stale_cleanup'
kill -0 "$OTHER" 2>/dev/null && [ ! -f "$W/run/hostapd.pid" ] && ok "after a reboot: old pid files dropped, nobody killed" || no "stale pids"
kill "$OTHER" 2>/dev/null || true; rm -rf "$W/proc/$OTHER"

# hostapd exits: started again on the next pass
: > "$W/hostapd.starts"; : > "$W/hostapd.crash"
us 'usbap_pass; rm -f "$W/hostapd.crash"; usbap_pass'
[ "$(grep -c . "$W/hostapd.starts")" = 2 ] && grep -q "hostapd or dnsmasq stopped" "$L" && ok "hostapd gone: started again" || no "crash restart: $(cat "$W/hostapd.starts")"

# the stock settings change (new SSID) while it runs, then a tuned channel: restarted with them
cp "$W/softap.conf" "$W/softap1.conf"; mksoftap Kia_zZ9q; cp "$W/softap.conf" "$W/softap2.conf"; cp "$W/softap1.conf" "$W/softap.conf"
: > "$W/hostapd.starts"
us 'usbap_pass; cp "$W/softap2.conf" "$SOFTAP"; usbap_pass; cp "$W/hostapd.conf.seen" "$W/conf.after-ssid"; echo channel=36 > "$DATA/usbap.tune"; usbap_pass'
[ "$(grep -c . "$W/hostapd.starts")" = 3 ] && grep -qx 'ssid=Kia_zZ9q' "$W/conf.after-ssid" && grep -qx 'channel=149' "$W/conf.after-ssid" \
    && grep -qx 'ssid=Kia_zZ9q' "$C" && grep -qx 'channel=36' "$C" && grep -qx 'hw_mode=a' "$C" && grep -q "interface or settings changed" "$L" \
    && ok "new stock SSID, then tune file channel 36: hostapd restarted with each" || no "settings change: $(cat "$W/hostapd.starts") / $(cat "$C")"
rm -f "$W/data/usbap.tune"; cp "$W/softap1.conf" "$W/softap.conf"

# dongle pulled: hostapd and dnsmasq stopped
us 'usbap_pass; HP=$(cat "$RUN/hostapd.pid"); DP=$(cat "$RUN/dhcp/dnsmasq.pid"); echo "$HP $DP" > "$W/pids"; rm -rf "$W/usbdev/1-1"; usbap_pass'
set -- $(cat "$W/pids")
! kill -0 "$1" 2>/dev/null && ! kill -0 "$2" 2>/dev/null && [ ! -f "$W/run/hostapd.pid" ] && [ ! -f "$W/run/iface" ] \
    && grep -q "hotspot off on rtwlan0 (dongle gone)" "$L" && ok "dongle pulled: hostapd and dnsmasq stopped" || no "unplug: $(cat "$L")"
dongle

# another 88x2bu driver in the kernel (usbwifi.hotspot's): not replaced, reboot asked
echo OTHERSRCVERSION > "$W/sysmod/88x2bu/srcversion"; : > "$W/insmod.log"; : > "$W/hostapd.starts"
us 'usbap_pass'
[ ! -s "$W/insmod.log" ] && [ ! -s "$W/hostapd.starts" ] && grep -q "another 88x2bu driver is loaded" "$L" && ok "someone else's 88x2bu loaded: left alone, reboot asked" || no "foreign driver"

# the driver doesn't load: once per boot
: > "$W/proc/modules"; rm -rf "$W/sysmod/88x2bu"; : > "$W/insmod.fail"; : > "$W/insmod.log"
us 'usbap_pass; usbap_pass'
[ "$(grep -c '^insmod' "$W/insmod.log")" = 1 ] && grep -q "the driver didn't load: insmod: init_module" "$L" && grep -q "not tried again before a reboot" "$L" \
    && ok "driver doesn't load: tried once per boot" || no "insmod failure: $(cat "$W/insmod.log")"
rm -f "$W/insmod.fail" "$W/run/insmod.failed"

# the whole service: extras on (no ev6kr.usbap.sync), stopped by HMG-API (TERM) -> everything off
rm -f "$W/data/usbap.nodebug"; : > "$W/logcat.log"
env EV6KR_TEST_PATH="$W/bin:$PATH" HMGAPI_MOD_DIR="$M" DATA="$W/data" RUN="$W/run" NEMESIS_DIR="$W/nemesis" \
    SOFTAP="$W/softap.conf" PROC="$W/proc" USB_DEVICES="$W/usbdev" SYSMODULE="$W/sysmod" SYSNET="$W/sysnet" \
    USB_DRIVERS="$W/drivers" SYSCTL_CORE="$W/sysctl" HOSTAPD="$W/bin/hostapd" DNSMASQ="$W/bin/dnsmasq" \
    SLEEP_BIN="$W/bin/sleepstub" INTERVAL=1 TUNE_EVERY=1 NETSAMPLE_EVERY=1 $SH "$M/svc/usbap.sh" &
SVC=$!
i=0; while [ $i -lt 40 ] && [ ! -f "$W/run/iface" ]; do /bin/sleep 0.25; i=$((i + 1)); done
HP=$(cat "$W/run/hostapd.pid" 2>/dev/null)
B=$(cat "$W/sysctl/netdev_max_backlog")
kill -TERM "$SVC"; wait "$SVC" 2>/dev/null || true
[ "$B" = 5000 ] && [ -s "$W/logcat.log" ] && ok "service: receive backlog raised, debug logcat on" || no "extras: backlog $B, logcat $(cat "$W/logcat.log")"
[ -n "$HP" ] && ! kill -0 "$HP" 2>/dev/null && [ ! -f "$W/run/iface" ] && [ "$(cat "$W/sysctl/netdev_max_backlog")" = 1000 ] \
    && grep -q "usb-hotspot-kr stop" "$L" && ok "service stopped (TERM): hotspot off, backlog back" || no "stop: $(cat "$L")"

echo "$fails failed"
[ $fails = 0 ]
