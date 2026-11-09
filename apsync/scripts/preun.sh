#!/system/bin/sh
# preuninstall (the service is already stopped): give the USB hotspot its own settings back.
# During an update (common.sh is_update) everything is left for the new version: the hotspot
# settings, the passphrase, net.core, the backups and the flags.
umask 022
. "${0%/scripts/*}/scripts/common.sh"
if is_update; then
    say "preuninstall for an update: the USB hotspot keeps the CarPlay settings"
else
    say "preuninstall"
    restore_psk
    net_untune
    tune_untune
    restore_usb_conf
fi
DEBUG_STOP=1
debug_logcat
is_update || rm -f "$DISABLED" "$NODEBUG_FLAG" "$TUNE" "$TXP_GUARD" 2>/dev/null
exit 0
