#!/system/bin/sh
# usb-hotspot-kr service, started and watched by HMG-API (root): see scripts/usbap.sh.
umask 022
MOD_DIR=${HMGAPI_MOD_DIR:-${0%/svc/*}}
. "$MOD_DIR/scripts/usbap.sh"
usbap_main
