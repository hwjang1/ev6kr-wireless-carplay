#!/bin/sh
# Build the USB Wi-Fi dongle driver for the head unit: Realtek RTL8812BU/RTL8822BU, from
# morrownr/88x2bu-20210702 (v5.13.1) with patch-88x2bu.py, for the car's kernel (3.18.24-tcc).
#
#   driver/build.sh <kernel config> [platform]
#
#   <kernel config>  the car's own: /proc/config.gz from the head unit (the trylog stick saves it
#                    as EV6KR-TRYLOG/kernel-config.gz; gunzip it, or give the .gz)
#   [platform]       ro.board.platform: tcc803x (EV6, default) or tcc897x
#
# Output: build/driver/88x2bu_<platform>.ko, .ids (USB vendor:product pairs it takes),
# .srcversion and .info (vermagic, sha256). tools/build.sh hotspot puts them in the mod.
# Needs Docker (runs linux/amd64). The toolchain (AOSP arm-eabi-4.7), kernel.org 3.18.24 and the
# driver source are fetched once into the volume KBUILD_VOLUME (default ev6kr-kbuild).
#   KBUILD_SEED_VOLUME   an existing volume holding arm-eabi-4.7/ and src/linux-3.18.24/
#                        (copied once instead of downloading)
#   REV                  driver commit (default: the one the patch was written for)
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
CONF=$1
PLATFORM=${2:-tcc803x}
[ -n "$CONF" ] && [ -f "$CONF" ] || { sed -n '2,20p' "$0"; exit 1; }
case "$PLATFORM" in tcc803x|tcc897x) ;; *) echo "platform: tcc803x or tcc897x"; exit 1 ;; esac
IMAGE=${KBUILD_IMAGE:-ev6kr-kbuild:20.04}
VOLUME=${KBUILD_VOLUME:-ev6kr-kbuild}
OUT=$ROOT/build/driver
mkdir -p "$OUT"
docker info >/dev/null 2>&1 || { echo "Docker isn't running"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
case "$CONF" in *.gz) gunzip -c "$CONF" > "$T/kconfig" ;; *) cp "$CONF" "$T/kconfig" ;; esac
grep -q '^CONFIG_LOCALVERSION="-tcc"' "$T/kconfig" || { echo "$CONF: not a Gen5W kernel config (no LOCALVERSION -tcc)"; exit 1; }

docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build --platform linux/amd64 -t "$IMAGE" driver
if [ -n "$KBUILD_SEED_VOLUME" ]; then
    docker run --rm --platform linux/amd64 -v "$VOLUME:/kb" -v "$KBUILD_SEED_VOLUME:/seed:ro" "$IMAGE" sh -c '
        [ -x /kb/arm-eabi-4.7/bin/arm-eabi-gcc ] || { [ -d /seed/arm-eabi-4.7 ] && cp -a /seed/arm-eabi-4.7 /kb/; }
        [ -f /kb/linux-3.18.24/Makefile ] || { [ -d /seed/src/linux-3.18.24 ] && cp -a /seed/src/linux-3.18.24 /kb/; }
        true'
fi
docker run --rm --platform linux/amd64 -v "$VOLUME:/kb" -v "$ROOT/driver:/drv:ro" -v "$OUT:/out" \
    -v "$T/kconfig:/kconfig:ro" -e PLATFORM="$PLATFORM" ${REV:+-e REV="$REV"} "$IMAGE" sh /drv/inside.sh

KO=$OUT/88x2bu_$PLATFORM.ko
python3 -I - "$KO" <<'PY'
import hashlib, re, struct, sys
ko = sys.argv[1]
data = open(ko, 'rb').read()
# the .modinfo section of a 32-bit little-endian ELF
shoff, = struct.unpack_from('<I', data, 0x20)
shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x2e)
def sh(i):
    return struct.unpack_from('<IIIIII', data, shoff + i * shentsize)
names = sh(shstrndx)
def name(off):
    s = names[4] + off
    return data[s:data.index(b'\0', s)].decode()
info = {}
aliases = []
for i in range(shnum):
    n, typ, flags, addr, off, size = sh(i)
    if name(n) == '.modinfo':
        for kv in data[off:off + size].split(b'\0'):
            if b'=' in kv:
                k, v = kv.decode(errors='replace').split('=', 1)
                if k == 'alias':
                    aliases.append(v)
                else:
                    info.setdefault(k, v)
ids = []
for a in aliases:
    m = re.match(r'usb:v([0-9A-F]{4})p([0-9A-F]{4})', a)
    if m and (m.group(1).lower() + ':' + m.group(2).lower()) not in ids:
        ids.append(m.group(1).lower() + ':' + m.group(2).lower())
base = ko[:-3]
open(base + '.ids', 'w').write('\n'.join(ids) + '\n')
open(base + '.srcversion', 'w').write(info.get('srcversion', '') + '\n')
sha = hashlib.sha256(data).hexdigest()
open(base + '.info', 'w').write('vermagic=%s\nversion=%s\nsrcversion=%s\nsha256=%s\nusb_ids=%d\n'
                                % (info.get('vermagic'), info.get('version'), info.get('srcversion'), sha, len(ids)))
print(open(base + '.info').read(), end='')
if not info.get('vermagic', '').startswith('3.18.24-tcc SMP preempt mod_unload ARMv7'):
    sys.exit('unexpected vermagic: %s' % info.get('vermagic'))
PY
echo "$KO"
