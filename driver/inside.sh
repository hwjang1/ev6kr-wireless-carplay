#!/bin/sh
# Container side of driver/build.sh: fetch (once) the toolchain, the kernel source and the
# driver, prepare the kernel for the car's config in its own object folder, apply
# patch-88x2bu.py to a fresh copy of the driver and build it.
#   /kb      cache volume       /drv   this folder (read only)
#   /out     output folder      /kconfig   the car's kernel config (from its /proc/config.gz)
set -e
KB=/kb
PLATFORM=${PLATFORM:-tcc803x}
REV=${REV:-418d71cc00cd18b4a671f8c49ecce9b19cbfd3c9}
DRV_URL=${DRV_URL:-https://github.com/morrownr/88x2bu-20210702.git}
TOOLCHAIN_URL=${TOOLCHAIN_URL:-https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.7/+archive/refs/heads/kitkat-release.tar.gz}
KERNEL_URL=${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.24.tar.xz}
KSRC=$KB/linux-3.18.24
export PATH=$KB/arm-eabi-4.7/bin:$PATH

if [ ! -x "$KB/arm-eabi-4.7/bin/arm-eabi-gcc" ]; then
    echo "fetching the arm-eabi-4.7 toolchain (AOSP kitkat-release)"
    rm -rf "$KB/arm-eabi-4.7" && mkdir -p "$KB/arm-eabi-4.7"
    curl -fsSL "$TOOLCHAIN_URL" | tar -xz -C "$KB/arm-eabi-4.7"
fi
if [ ! -f "$KSRC/Makefile" ]; then
    echo "fetching linux-3.18.24 (kernel.org)"
    rm -rf "$KSRC"
    curl -fsSL "$KERNEL_URL" | tar -xJ -C "$KB"
fi
# the object folder keeps the source tree clean (a seeded tree may have been built in place)
[ -f "$KSRC/.config" ] && make -s -C "$KSRC" mrproper

OBJ=$KB/obj-$PLATFORM
mkdir -p "$OBJ"
if ! cmp -s /kconfig "$OBJ/.config.car"; then
    echo "preparing the kernel for $PLATFORM"
    cp /kconfig "$OBJ/.config.car"
    cp /kconfig "$OBJ/.config"
    make -s -C "$KSRC" O="$OBJ" ARCH=arm CROSS_COMPILE=arm-eabi- olddefconfig
    make -s -C "$KSRC" O="$OBJ" ARCH=arm CROSS_COMPILE=arm-eabi- modules_prepare
fi
echo "kernel release: $(cat "$OBJ/include/config/kernel.release")"

SRC0=$KB/88x2bu-$REV
if [ ! -f "$SRC0/Makefile" ]; then
    echo "fetching the driver at $REV"
    rm -rf "$SRC0" && mkdir -p "$SRC0"
    git -C "$SRC0" init -q
    git -C "$SRC0" fetch -q --depth 1 "$DRV_URL" "$REV"
    git -C "$SRC0" checkout -q FETCH_HEAD
fi
W=$KB/work-$PLATFORM
rm -rf "$W" && cp -a "$SRC0" "$W" && rm -rf "$W/.git"
(cd "$W" && python3 /drv/patch-88x2bu.py)
make -C "$KSRC" O="$OBJ" M="$W" ARCH=arm CROSS_COMPILE=arm-eabi- CONFIG_RTL8822BU=m -j"$(nproc)" modules 2>&1 \
    | grep -E 'warning|error|LD \[M\]' || true
[ -f "$W/88x2bu.ko" ] || { echo "the build made no 88x2bu.ko"; exit 1; }
arm-eabi-strip --strip-debug -o "/out/88x2bu_$PLATFORM.ko" "$W/88x2bu.ko"
echo "$REV" > "/out/88x2bu_$PLATFORM.rev"
echo "built /out/88x2bu_$PLATFORM.ko from $REV"
