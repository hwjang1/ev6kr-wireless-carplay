#!/system/bin/sh
# postinstall (cwd = the package folder): check the helper reads the stock settings, then sync once.
umask 022
APP_DIR=$(pwd)
. "$APP_DIR/scripts/common.sh"
chmod 755 "$APP_DIR"/scripts/*.sh "$APP_DIR"/svc/*.sh "$APP_DIR"/bin/*.sh 2>/dev/null
chmod 644 "$JAR" 2>/dev/null
say "postinstall in $APP_DIR"
_show=$(CLASSPATH="$JAR" app_process /system/bin ev6kr.cpw.SoftApConf show "$SOFTAP" 2>&1)
_rc=$?
say "stock CarPlay hotspot settings (passwords masked): rc=$_rc $_show"
echo "$_show"
if [ $_rc != 0 ]; then
    echo "can't read the stock CarPlay hotspot settings ($SOFTAP), see $LOG"
    exit 1
fi
# an update: a debug logcat left by the old version keeps its old filter, so start it afresh
# (the service starts the new one)
DEBUG_STOP=1
debug_logcat
DEBUG_STOP=
sync_once
exit 0
