#!/system/bin/sh
# EV6 KR - does this head unit have a built-in Wi-Fi module? (docs/ANALYSIS.md section 38)
# Turns the stock Wi-Fi on once (`svc wifi enable`), which makes the stock stack load bcmdhd.ko and
# power the module, then watches for an SDIO card and wlan0 for 40 s, writes what it saw and turns
# Wi-Fi back off if it was off. Nothing else is changed.
# Turning Wi-Fi on can restart USB and Bluetooth for a moment, so this stick may drop out: the test
# runs from /data/local/tmp and shows its result as a toast. Plug the stick in again in the same
# boot to get EV6KR-WIFICHECK.txt without testing again. Restart the head unit afterwards.
# The file can hold the module's MAC address if one shows up: share it privately only.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib ANDROID_ROOT=/system ANDROID_DATA=/data
[ -n "$BOOTCLASSPATH" ] || export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
R=/data/local/tmp/ev6kr-wificheck
# First pass (from the stick): copy this script to /data and carry on from there, so a USB restart
# can't cut it off halfway through.
if [ "$1" != "--worker" ]; then
    mkdir -p "$R" || exit 1
    cat "$0" > "$R/run.sh" 2>/dev/null || cat "$(pwd)/NEMESIS.sh" > "$R/run.sh" || exit 1
    exec sh "$R/run.sh" --worker "$(pwd)"
fi
H=$2
O=$R/EV6KR-WIFICHECK.txt
NOSERIAL='serialno|command line|SerialNumber'
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
    true
}
say() { echo "$1" >> "$O"; }
to_stick() { [ -d "$H" ] && cat "$O" > "$H/EV6KR-WIFICHECK.txt" 2>/dev/null && sync; true; }
nets() { _s=""; for _i in $(ls /sys/class/net 2>/dev/null); do _s="$_s$_i "; done; echo "$_s"; }
sdio() { _s=""; for _i in $(ls /sys/bus/sdio/devices 2>/dev/null); do _s="$_s$_i "; done; echo "$_s"; }
BOOT=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)

# Already tested in this boot: hand over the result only (a second Wi-Fi toggle tells nothing new)
if [ -s "$O" ] && [ -n "$BOOT" ] && [ "$(cat "$R/boot" 2>/dev/null)" = "$BOOT" ]; then
    to_stick
    toast "EV6KR Wi-Fi 확인: 이번 부팅에 이미 시험했습니다. 결과를 USB에 복사했습니다"
    exit 0
fi

: > "$O"
echo "$BOOT" > "$R/boot"
say "ev6kr-wifi-check 1"
say "date $(date), uptime $(cat /proc/uptime 2>/dev/null)"
say "product $(getprop ro.build.product)"
WIFI_ON=$(settings get global wifi_on 2>/dev/null)
say ""
say "--- before"
say "wifi_on=$WIFI_ON wlan.driver.status=$(getprop wlan.driver.status) wifi.interface=$(getprop wifi.interface)"
say "net: $(nets)"
say "sdio: $(sdio)"
say "bcmdhd loaded: $(grep -c '^bcmdhd ' /proc/modules 2>/dev/null)"
logcat -d -v time 2>/dev/null | grep -E 'HW Variant|wifi_get_module_version' | grep -v -i -E "$NOSERIAL" | while read -r L; do say "$L"; done
to_stick

toast "EV6KR Wi-Fi 확인 중(약 1분): 블루투스·USB가 잠시 끊길 수 있습니다"
say ""
say "--- svc wifi enable"
T0=$(cat /proc/uptime 2>/dev/null); T0=${T0%%.*}
svc wifi enable > "$R/svc.txt" 2>&1 &
SVC=$!
W=0; D=0
N=0
while [ $N -lt 20 ]; do
    sleep 2
    N=$((N + 1))
    NOW=$(cat /proc/uptime 2>/dev/null); NOW=${NOW%%.*}
    say "+$((NOW - T0))s driver=$(getprop wlan.driver.status) net: $(nets)| sdio: $(sdio)"
    [ -d /sys/class/net/wlan0 ] && W=1
    [ -n "$(sdio)" ] && D=1
    # once something shows up, give it 10 s to settle and stop
    [ $((W + D)) -gt 0 ] && [ $N -ge 5 ] && break
done
SEEN=""
[ $W = 1 ] && SEEN="wlan0"
[ $D = 1 ] && SEEN="${SEEN:+$SEEN, }SDIO card"
kill -0 $SVC 2>/dev/null && { kill $SVC 2>/dev/null; say "svc wifi enable didn't finish: stopped"; }
say "svc output: $(cat "$R/svc.txt" 2>/dev/null)"

say ""
say "--- after"
say "wifi_on=$(settings get global wifi_on 2>/dev/null) wlan.driver.status=$(getprop wlan.driver.status)"
say "net: $(nets)"
say "sdio: $(sdio)"
ls /sys/bus/sdio/devices 2>/dev/null | while read -r D; do
    say "sdio $D: vendor $(cat /sys/bus/sdio/devices/$D/vendor 2>/dev/null) device $(cat /sys/bus/sdio/devices/$D/device 2>/dev/null)"
done
say "bcmdhd loaded: $(grep -c '^bcmdhd ' /proc/modules 2>/dev/null)"
say ""
say "--- logcat (stock Wi-Fi)"
logcat -d -v time 2>/dev/null | grep -E 'WifiHW|WifiStateMachine|WifiService|WifiController|WifiNative|wpa_supplicant|SoftapController|BCM:|wifi_load|insmod' \
    | grep -v -i -E "$NOSERIAL" > "$R/logcat.txt" 2>/dev/null
L=$(grep -c '' "$R/logcat.txt" 2>/dev/null); L=${L:-0}
S=$((L > 150 ? L - 150 : 0))
N=0
while read -r LL; do N=$((N + 1)); [ $N -gt $S ] && say "$LL"; done < "$R/logcat.txt"
say ""
say "--- kernel (SDIO, Wi-Fi driver)"
dmesg 2>/dev/null | grep -i -E 'dhd|bcmdhd|wlan|sdio|mmc1|wifi' | grep -v -i -E "$NOSERIAL" > "$R/dmesg.txt" 2>/dev/null
L=$(grep -c '' "$R/dmesg.txt" 2>/dev/null); L=${L:-0}
S=$((L > 80 ? L - 80 : 0))
N=0
while read -r LL; do N=$((N + 1)); [ $N -gt $S ] && say "$LL"; done < "$R/dmesg.txt"

if [ -n "$SEEN" ]; then
    VERDICT="built-in Wi-Fi FOUND ($SEEN)"
    MSG="EV6KR Wi-Fi 확인 완료: 내장 Wi-Fi가 있습니다($SEEN). 헤드유닛을 재시작해 주세요"
else
    VERDICT="no built-in Wi-Fi: no SDIO card and no wlan0 within 40 s of turning Wi-Fi on"
    MSG="EV6KR Wi-Fi 확인 완료: 내장 Wi-Fi 없음(wlan0·SDIO 없음). 헤드유닛을 재시작해 주세요"
fi
say ""
say "--- restore"
if [ "$WIFI_ON" != 1 ]; then
    svc wifi disable > /dev/null 2>&1
    sleep 3
    say "Wi-Fi turned back off: wifi_on=$(settings get global wifi_on 2>/dev/null)"
else
    say "Wi-Fi was already on before the test: left on"
fi
say ""
say "VERDICT: $VERDICT"
to_stick
toast "$MSG"
