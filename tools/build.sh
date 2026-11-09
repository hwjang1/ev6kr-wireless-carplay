#!/bin/sh
# Build the EV6 KR wireless CarPlay packages into dist/:
#   ev6kr.usbap.sync-<v>-nemesis.zip           USB stick: the hotspot sync NEMESIS package
#   ev6kr.usbap.sync-<v>-nemesis-package.zip   the same package alone (nemesis install / Package Store)
#   wireless-carplay-kr-<v>.zip                the signed HMG-API mod (HMGAPI/updates on a stick, or adb)
#   wireless-carplay-kr-<v>-nemesis*.zip       the mod as NEMESIS package hmgapi.wireless-carplay-kr
#   ev6kr-wireless-carplay-<v>-mod<mv>-nemesis.zip  one USB stick with both NEMESIS packages (Package Store list)
#   usb-hotspot-kr-<v>.zip, -nemesis*.zip      the standalone USB Wi-Fi hotspot mod (no usbwifi.hotspot);
#                                              needs the driver built first (driver/build.sh)
#   ev6kr-wireless-carplay-standalone-<v>-nemesis.zip   one USB stick: the hotspot mod + the CarPlay mod
#   ev6kr-preflight-usb.zip, ev6kr-trylog-usb.zip       the preflight and trylog sticks (unzip to a stick's root)
#   release/                                   the files for a GitHub release, with SHA256SUMS.txt
#
#   tools/build.sh [apsync|mod|bundle|sticks|all|release|hotspot|standalone]    (default all: the usbwifi.hotspot set)
#   tools/build.sh keygen                      make the mod signing key (once; keep it, outside the repo)
#
# Needs: a JDK (javac, java), the Android SDK (a platforms/android-*/android.jar, build-tools d8),
# python3, zip, and HMG-API's source next to this folder (HMGAPI_DIR, default ../HMG-API) for
# its runtime classes, signing and NEMESIS wrapper. HMG-API is only read, never written.
#   ANDROID_HOME  SDK (default: $HOME/Android, else Homebrew's android-commandlinetools)
#   MOD_KEY       mod signing key (default ~/hmg-private/keys/ev6kr-mods.key)
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
HMG=${HMGAPI_DIR:-$ROOT/../HMG-API}
[ -f "$HMG/core/runtime/java/hmgapi/engine/Signing.java" ] || { echo "no HMG-API source at $HMG (set HMGAPI_DIR)"; exit 1; }
HMG=$(cd "$HMG" && pwd)
for s in "${ANDROID_HOME:-}" "$HOME/Android" /opt/homebrew/share/android-commandlinetools; do
    [ -n "$s" ] && ls "$s"/platforms/android-*/android.jar >/dev/null 2>&1 && { SDK=$s; break; }
done
[ -n "$SDK" ] || { echo "no Android SDK with a platforms/android-*/android.jar (set ANDROID_HOME)"; exit 1; }
ANDROID_JAR=$(ls "$SDK"/platforms/android-*/android.jar | tail -1)   # compile only; the code uses API 19
D8=$(ls "$SDK"/build-tools/*/d8 2>/dev/null | tail -1)
[ -x "$D8" ] || D8=$(command -v d8) || { echo "no d8"; exit 1; }
MOD_KEY=${MOD_KEY:-$HOME/hmg-private/keys/ev6kr-mods.key}
B=$ROOT/build
DIST=$ROOT/dist
mkdir -p "$B" "$DIST"
JAVAC="javac --release 8 -Xlint:-options -nowarn"

# zipdir <dir> <zip>: fixed order and times, so the same input gives the same zip
zipdir() {
    rm -f "$2"
    (cd "$1" && find . -type f | TZ=UTC xargs touch -d 2026-01-01T00:00:00 && find . -type f | sed 's#^\./##' | sort | zip -q -X -D "$2" -@)
}

engine() {
    [ -f "$B/engine-host/hmgapi/engine/Signing.class" ] && return 0
    rm -rf "$B/engine-host" && mkdir -p "$B/engine-host"
    $JAVAC -d "$B/engine-host" "$HMG"/core/runtime/java/hmgapi/engine/*.java 2>/dev/null
}

keygen() {
    engine
    [ -f "$MOD_KEY" ] && { echo "$MOD_KEY already exists; not replacing it (installed mods are tied to its key)"; exit 1; }
    mkdir -p "$(dirname "$MOD_KEY")"
    (umask 077 && java -cp "$B/engine-host" hmgapi.engine.Signing keygen "$MOD_KEY")
    echo "made $MOD_KEY: keep a copy somewhere safe and never commit it"
}

apsync() {
    V=$(sed -n 's/^package-version=//p' apsync/NEMESIS.data)
    S=$B/apsync/pkg
    rm -rf "$B/apsync" && mkdir -p "$B/apsync/classes" "$S"
    $JAVAC -cp "$ANDROID_JAR" -d "$B/apsync/classes" apsync/java/ev6kr/cpw/SoftApConf.java
    cp apsync/NEMESIS.data "$S/"
    cp -r apsync/scripts apsync/svc apsync/bin "$S/"
    cp shared/rtwlan.sh "$S/scripts/"
    "$D8" --release --min-api 19 --lib "$ANDROID_JAR" --output "$S/bin/softapconf.jar" $(find "$B/apsync/classes" -name '*.class')
    chmod 755 "$S"/scripts/*.sh "$S"/svc/*.sh "$S"/bin/*.sh
    # NEMESIS refuses a short-desc over 64 and a detailed-desc over 256 characters
    python3 -I - "$S/NEMESIS.data" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
for k, n in (("short-desc", 64), ("detailed-desc", 256)):
    m = re.search(r'^%s="?(.*?)"?$' % k, t, re.M)
    if m and len(m.group(1)) > n:
        sys.exit("%s is %d characters (max %d)" % (k, len(m.group(1)), n))
PY
    P=$DIST/ev6kr.usbap.sync-$V-nemesis-package.zip
    zipdir "$S" "$P"
    T=$B/apsync/stick
    mkdir -p "$T/packages"
    cp "$P" "$T/packages/ev6kr.usbap.sync.zip"
    printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/ev6kr.usbap.sync.zip\n' > "$T/NEMESIS.data"
    zipdir "$T" "$DIST/ev6kr.usbap.sync-$V-nemesis.zip"
    echo "$DIST/ev6kr.usbap.sync-$V-nemesis.zip"
    echo "$P"
}

mod() {
    [ -f "$MOD_KEY" ] || { echo "no mod signing key at $MOD_KEY: run tools/build.sh keygen first (or set MOD_KEY)"; exit 1; }
    engine
    ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' mod/mod.json)
    V=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' mod/mod.json)
    rm -rf "$B/mod" && mkdir -p "$B/mod/runtime-stubs" "$B/mod/runtime" "$B/mod/stubs" "$B/mod/classes" "$B/mod/pkg/$ID"
    # HMG-API's runtime (hook API the mod calls), as build.sh's runtime(): compile only, never in hooks.jar
    $JAVAC -cp "$ANDROID_JAR" -d "$B/mod/runtime-stubs" $(find "$HMG/core/runtime/stubs" -name '*.java')
    $JAVAC -cp "$ANDROID_JAR:$B/mod/runtime-stubs" -d "$B/mod/runtime" $(find "$HMG/core/runtime/java" -name '*.java')
    # stubs/: the car's own libraries (iAP2 client, Broadcom BT manager), compile only
    $JAVAC -cp "$ANDROID_JAR" -d "$B/mod/stubs" $(find mod/stubs -name '*.java')
    $JAVAC -cp "$ANDROID_JAR:$B/mod/runtime:$B/mod/stubs" -d "$B/mod/classes" $(find mod/src -name '*.java')
    "$D8" --release --min-api 19 --lib "$ANDROID_JAR" --classpath "$B/mod/runtime" --classpath "$B/mod/stubs" \
        --output "$B/mod/pkg/$ID/hooks.jar" $(find "$B/mod/classes" -name '*.class')
    for f in mod/*; do
        case "${f##*/}" in src|tools|native|build.sh|test.sh) ;; *) cp -r "$f" "$B/mod/pkg/$ID/" ;; esac
    done
    java -cp "$B/engine-host" hmgapi.engine.Signing sign "$B/mod/pkg/$ID" "$MOD_KEY"
    java -cp "$B/engine-host" hmgapi.engine.Signing verify "$B/mod/pkg/$ID"
    Z=$DIST/$ID-$V.zip
    zipdir "$B/mod/pkg/$ID" "$Z"
    echo "$Z"
    sh "$HMG/tools/mknemesismod.sh" "$Z" "$DIST"
}

# bundle: one USB stick with both NEMESIS packages (type=list: NEMESIS Manager's Package
# Store opens on them; install the sync package first, then the mod)
bundle() {
    AV=$(sed -n 's/^package-version=//p' apsync/NEMESIS.data)
    MV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' mod/mod.json)
    MID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' mod/mod.json)
    L=$B/bundle
    rm -rf "$L" && mkdir -p "$L/packages"
    cp "$DIST/ev6kr.usbap.sync-$AV-nemesis-package.zip" "$L/packages/ev6kr.usbap.sync.zip"
    cp "$DIST/$MID-$MV-nemesis-package.zip" "$L/packages/hmgapi.$MID.zip"
    ini() { unzip -p "$1" NEMESIS.data | sed -n "s/^$2=//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
    {
        printf '[nemesis]\nversion=1.1\ntype=list\n'
        i=0
        for p in ev6kr.usbap.sync.zip "hmgapi.$MID.zip"; do
            printf '\n[package.%s]\npath=packages/%s\nname=%s\nshort-desc=%s\npublished=2026-11-07\n' \
                "$i" "$p" "$(ini "$L/packages/$p" name)" "$(ini "$L/packages/$p" short-desc)"
            i=$((i + 1))
        done
    } > "$L/NEMESIS.data"
    cp README.md "$L/README-ev6kr.md"
    # named by both versions: a new mod with the same sync package is a new file, never a changed one
    zipdir "$L" "$DIST/ev6kr-wireless-carplay-$AV-mod$MV-nemesis.zip"
    echo "$DIST/ev6kr-wireless-carplay-$AV-mod$MV-nemesis.zip"
}


# sticks: the preflight and trylog USB sticks as zips. Their names carry no version, so a
# release's direct link stays the same; each release has its own copy.
sticks() {
    for s in preflight trylog; do
        rm -rf "$B/stick-$s" && mkdir -p "$B/stick-$s"
        cp "usb/$s/NEMESIS.data" "usb/$s/NEMESIS.sh" "$B/stick-$s/"
        zipdir "$B/stick-$s" "$DIST/ev6kr-$s-usb.zip"
        echo "$DIST/ev6kr-$s-usb.zip"
    done
}

# release: the files for a GitHub release in dist/release/. The install stick also goes in under a
# name without versions (ev6kr-wireless-carplay-nemesis.zip) for a fixed "latest" download link.
release() {
    AV=$(sed -n 's/^package-version=//p' apsync/NEMESIS.data)
    MV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' mod/mod.json)
    MID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' mod/mod.json)
    R=$DIST/release
    rm -rf "$R" && mkdir -p "$R"
    cp "$DIST/ev6kr-wireless-carplay-$AV-mod$MV-nemesis.zip" "$R/"
    cp "$DIST/ev6kr-wireless-carplay-$AV-mod$MV-nemesis.zip" "$R/ev6kr-wireless-carplay-nemesis.zip"
    cp "$DIST/ev6kr.usbap.sync-$AV-nemesis.zip" "$DIST/$MID-$MV-nemesis.zip" "$R/"
    cp "$DIST/ev6kr-preflight-usb.zip" "$DIST/ev6kr-trylog-usb.zip" "$R/"
    (cd "$R" && shasum -a 256 *.zip > SHA256SUMS.txt)
    ls "$R"
}


# hotspot: the usb-hotspot-kr HMG-API mod (standalone: its own driver, the stock hostapd and
# dnsmasq). The driver comes from build/driver (driver/build.sh): tcc803x is needed, tcc897x
# is taken when there.
hotspot() {
    [ -f "$MOD_KEY" ] || { echo "no mod signing key at $MOD_KEY: run tools/build.sh keygen first (or set MOD_KEY)"; exit 1; }
    DRV=$ROOT/build/driver
    [ -f "$DRV/88x2bu_tcc803x.ko" ] && [ -f "$DRV/88x2bu_tcc803x.ids" ] && [ -f "$DRV/88x2bu_tcc803x.srcversion" ] \
        || { echo "no driver in $DRV: run driver/build.sh <the car's kernel config> first"; exit 1; }
    engine
    ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' hotspot/mod.json)
    V=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' hotspot/mod.json)
    P=$B/hotspot/pkg/$ID
    rm -rf "$B/hotspot" && mkdir -p "$B/hotspot/classes" "$P/bin" "$P/modules"
    cp hotspot/mod.json "$P/"
    cp -r hotspot/svc hotspot/scripts "$P/"
    cp shared/rtwlan.sh "$P/scripts/"
    $JAVAC -cp "$ANDROID_JAR" -d "$B/hotspot/classes" apsync/java/ev6kr/cpw/SoftApConf.java
    "$D8" --release --min-api 19 --lib "$ANDROID_JAR" --output "$P/bin/softapconf.jar" $(find "$B/hotspot/classes" -name '*.class')
    for pl in tcc803x tcc897x; do
        [ -f "$DRV/88x2bu_$pl.ko" ] || continue
        cp "$DRV/88x2bu_$pl.ko" "$DRV/88x2bu_$pl.ids" "$DRV/88x2bu_$pl.srcversion" "$P/modules/"
    done
    # GPL-2.0: what the driver is built from, and our changes to it
    cp driver/patch-88x2bu.py "$P/modules/"
    {
        echo "88x2bu_<platform>.ko: Realtek RTL8812BU/RTL8822BU USB Wi-Fi driver, GPL-2.0."
        echo "Source: https://github.com/morrownr/88x2bu-20210702 at commit $(cat "$DRV/88x2bu_tcc803x.rev" 2>/dev/null || echo '(see driver/inside.sh)'),"
        echo "with patch-88x2bu.py (this folder, GPL-2.0), built by driver/build.sh of ev6kr-wireless-carplay"
        echo "for Linux 3.18.24-tcc (the head unit's own kernel config) with AOSP's arm-eabi-4.7."
        for pl in tcc803x tcc897x; do [ -f "$DRV/88x2bu_$pl.info" ] && { echo; echo "[$pl]"; cat "$DRV/88x2bu_$pl.info"; }; done
    } > "$P/modules/SOURCE.txt"
    chmod 755 "$P"/svc/*.sh "$P"/scripts/*.sh
    java -cp "$B/engine-host" hmgapi.engine.Signing sign "$P" "$MOD_KEY"
    java -cp "$B/engine-host" hmgapi.engine.Signing verify "$P"
    Z=$DIST/$ID-$V.zip
    zipdir "$P" "$Z"
    echo "$Z"
    sh "$HMG/tools/mknemesismod.sh" "$Z" "$DIST"
}

# standalone: one USB stick with the hotspot mod and the CarPlay mod as NEMESIS packages
# (Package Store list; install the hotspot first). No usbwifi.hotspot, no ev6kr.usbap.sync.
standalone() {
    HV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' hotspot/mod.json)
    HID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' hotspot/mod.json)
    MV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' mod/mod.json)
    MID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' mod/mod.json)
    L=$B/standalone
    rm -rf "$L" && mkdir -p "$L/packages"
    cp "$DIST/$HID-$HV-nemesis-package.zip" "$L/packages/hmgapi.$HID.zip"
    cp "$DIST/$MID-$MV-nemesis-package.zip" "$L/packages/hmgapi.$MID.zip"
    ini() { unzip -p "$1" NEMESIS.data | sed -n "s/^$2=//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
    {
        printf '[nemesis]\nversion=1.1\ntype=list\n'
        i=0
        for p in "hmgapi.$HID.zip" "hmgapi.$MID.zip"; do
            printf '\n[package.%s]\npath=packages/%s\nname=%s\nshort-desc=%s\npublished=2026-11-08\n' \
                "$i" "$p" "$(ini "$L/packages/$p" name)" "$(ini "$L/packages/$p" short-desc)"
            i=$((i + 1))
        done
    } > "$L/NEMESIS.data"
    cp README.md "$L/README-ev6kr.md"
    zipdir "$L" "$DIST/ev6kr-wireless-carplay-standalone-$HV-nemesis.zip"
    echo "$DIST/ev6kr-wireless-carplay-standalone-$HV-nemesis.zip"
}

case "${1:-all}" in
    keygen) keygen ;;
    apsync) apsync ;;
    mod) mod ;;
    bundle) bundle ;;
    sticks) sticks ;;
    all) apsync; mod; bundle; sticks ;;
    release) apsync; mod; bundle; sticks; release ;;
    hotspot) hotspot ;;
    standalone) hotspot; mod; standalone ;;
    standalone-bundle) standalone ;;   # only the stick, from the packages already in dist/
    *) echo "usage: tools/build.sh [apsync|mod|bundle|sticks|all|release|hotspot|standalone|keygen]"; exit 2 ;;
esac
