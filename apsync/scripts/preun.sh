#!/system/bin/sh
# preuninstall (the service is already stopped): give the USB hotspot its own settings back.
# During an update (common.sh is_update) everything is left for the new version: the hotspot
# settings, the passphrase, net.core, the backups, the flags and the debug files. On a real
# uninstall the debug logcat and sampler files go too (this package's own log stays: a few KB).
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
if ! is_update; then
    rm -f "$DISABLED" "$DEBUG_FLAG" "$NODEBUG_FLAG" "$LOWDISK" "$TUNE" "$TXP_GUARD" 2>/dev/null
    # the debug logcat's and the sampler's files (about 6 MB); the sampler beside the stopped
    # service ends within one round (NETSAMPLE_EVERY) and may write once more: removed again
    if [ -f "$NETSAMPLE" ]; then
        debug_files_rm
        sleep $((NETSAMPLE_EVERY + 1))
    fi
    debug_files_rm
    say "debug logcat and sampler files removed"
fi
exit 0
