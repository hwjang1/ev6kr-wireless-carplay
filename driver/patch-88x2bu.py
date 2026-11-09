#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Gen5W changes for morrownr/88x2bu-20210702 (Realtek RTL8812BU/RTL8822BU driver v5.13.1).
# Run in the driver's source tree (driver/inside.sh does). Patches, as part of a GPL-2.0
# driver, are GPL-2.0 too.
#
#   1. usbfs can't open the dongle: the head unit's projection stack opens every USB device to
#      ask for Android accessory (AOA) mode, and the dongle doesn't take that well. While we
#      hold the dongle, its usb_device carries a device number no /dev/bus/usb node has, so
#      usbdev_open() finds nothing. Put back on remove (and on a failed probe), before the USB
#      core removes the node.
#   2. A pulled dongle is marked gone before the netdev teardown: the stock remove unregisters
#      the netdev (hostapd's stop_ap, ndo_stop, ...) first and sets "surprise removed" after, so
#      that teardown talks to a device that isn't there any more.
#   3. ethtool driver info (new in v5.13.1) without a parent device: answered from the driver's
#      own name instead of following a NULL pointer (a kernel panic on ETHTOOL_GDRVINFO, which
#      Android's netd sends).
#   4. Build options: the /proc debug entries on (ev6kr's sampler and TX path/power tuning use
#      them), PHY parameters built in (no files on the unit), TX power by rate from the efuse,
#      errors and warnings in dmesg.
#   5. RX A-MPDU (the phone's block ack sessions) refused from the start: accepted, it crashed
#      the head unit (8th car test).
# Interface names (rtwlan%d), power saving and NAPI/GRO are module parameters, set by the
# loader (usb-hotspot-kr's service), not patched here.
import sys

DEVT_MARK = "0x00080000U"


def patch(path, old, new, count=1):
    with open(path) as f:
        text = f.read()
    if text.count(old) < count:
        sys.exit("%s: expected text not found:\n%s" % (path, old))
    text = text.replace(old, new, count)
    with open(path, "w") as f:
        f.write(text)


def makefile(old, new):
    patch("Makefile", old + "\n", new + "\n")


# 4. build options
makefile("CONFIG_PROC_DEBUG = n", "CONFIG_PROC_DEBUG = y")
makefile("CONFIG_LOAD_PHY_PARA_FROM_FILE = y", "CONFIG_LOAD_PHY_PARA_FROM_FILE = n")
makefile("CONFIG_TXPWR_BY_RATE_EN = n", "CONFIG_TXPWR_BY_RATE_EN = y")
makefile("CONFIG_RTW_LOG_LEVEL = 0", "CONFIG_RTW_LOG_LEVEL = 2")

# 1. keep usbfs off the dongle while the driver has it
patch("os_dep/linux/usb_intf.c",
      "\t/* step 0. */\n\tprocess_spec_devid(pdid);\n",
      "\t/* ev6kr: no usbfs open (AOA probing) while we hold the dongle; see rtw_dev_remove() */\n"
      "\tinterface_to_usbdev(pusb_intf)->dev.devt |= " + DEVT_MARK + ";\n"
      "\n\t/* step 0. */\n\tprocess_spec_devid(pdid);\n")
patch("os_dep/linux/usb_intf.c",
      "free_dvobj:\n\tif (status != _SUCCESS)\n\t\tusb_dvobj_deinit(pusb_intf);\nexit:\n\treturn status == _SUCCESS ? 0 : -ENODEV;\n",
      "free_dvobj:\n\tif (status != _SUCCESS)\n\t\tusb_dvobj_deinit(pusb_intf);\nexit:\n"
      "\tif (status != _SUCCESS)\n\t\tinterface_to_usbdev(pusb_intf)->dev.devt &= ~" + DEVT_MARK + ";\n"
      "\treturn status == _SUCCESS ? 0 : -ENODEV;\n")
patch("os_dep/linux/usb_intf.c",
      "\tusb_dvobj_deinit(pusb_intf);\n\n\tRTW_INFO(\"-r871xu_dev_remove, done\\n\");\n",
      "\t/* ev6kr: the device number back, so the USB core removes the right /dev node */\n"
      "\tinterface_to_usbdev(pusb_intf)->dev.devt &= ~" + DEVT_MARK + ";\n\n"
      "\tusb_dvobj_deinit(pusb_intf);\n\n\tRTW_INFO(\"-r871xu_dev_remove, done\\n\");\n")

# 2. a dongle that was pulled out is gone before the netdev teardown starts
patch("os_dep/linux/usb_intf.c",
      "\tdvobj->processing_dev_remove = _TRUE;\n",
      "\tdvobj->processing_dev_remove = _TRUE;\n\n"
      "\t/* ev6kr: pulled out (not rmmod): no USB I/O from the teardown below */\n"
      "\tif (interface_to_usbdev(pusb_intf)->state == USB_STATE_NOTATTACHED)\n"
      "\t\trtw_set_surprise_removed(padapter);\n")

# 3. ethtool driver info without a parent device
with open("os_dep/linux/os_intfs.c") as f:
    src = f.read()
start = src.find("static void rtw_ethtool_get_drvinfo(")
if start < 0:
    sys.exit("os_intfs.c: rtw_ethtool_get_drvinfo not found")
end = src.find("\n}\n", start)
body = src[start:end]
for old, new in (
        ("\tif (wdev) {\n\t\tstrlcpy(info->driver, wiphy_dev(wdev->wiphy)->driver->name,",
         "\tif (wdev && wiphy_dev(wdev->wiphy) && wiphy_dev(wdev->wiphy)->driver) {\n"
         "\t\tstrlcpy(info->driver, wiphy_dev(wdev->wiphy)->driver->name,"),
        ("\tstrlcpy(info->bus_info, dev_name(wiphy_dev(wdev->wiphy)),\n\t\tsizeof(info->bus_info));",
         "\tif (wdev && wiphy_dev(wdev->wiphy))\n"
         "\t\tstrlcpy(info->bus_info, dev_name(wiphy_dev(wdev->wiphy)),\n\t\t\tsizeof(info->bus_info));\n"
         "\telse\n\t\tstrlcpy(info->bus_info, \"usb\", sizeof(info->bus_info));")):
    if old not in body:
        sys.exit("os_intfs.c: rtw_ethtool_get_drvinfo has an unexpected shape:\n" + body)
    body = body.replace(old, new)
src = src[:start] + body + src[end:]
with open("os_dep/linux/os_intfs.c", "w") as f:
    f.write(src)

# 5. the phone's A-MPDU (block ack) sessions refused from the start. With RX A-MPDU accepted, this
#    driver took the head unit down within seconds of CarPlay traffic (8th car test, 2026-11-08:
#    three reboots in a row, ~10 s after the iPhone joined); refused, it ran for hours (7th test).
#    /proc/net/rtl88x2bu/<if>/rx_ampdu still takes 255 (the driver's choice) for experiments.
patch("os_dep/linux/os_intfs.c",
      "\tpadapter->fix_rx_ampdu_accept = RX_AMPDU_ACCEPT_INVALID;\n",
      "\tpadapter->fix_rx_ampdu_accept = 0; /* ev6kr: RX A-MPDU refused, see patch-88x2bu.py 5. */\n",
      count=2)

print("ev6kr Gen5W changes applied")
