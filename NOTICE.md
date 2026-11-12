# NOTICE

This folder is a derivative of **HMG-API** (Open-HMG/HMG-API, AGPL-3.0), source at commit
`f80751b31795d3e813452867d2c7dad85ee0d061` (HMG-API 1.0.2).

| Path | Origin |
|---|---|
| `mod/src/`, `mod/stubs/`, `mod/settings.json` | HMG-API `mods/wireless-carplay-aa` 2.1.0 by VysseCodes. Changed: `dipo/Bridge.java` (`ensureHotspot`: the USB Wi-Fi hotspot instead of the stock one on units without a Wi-Fi chip; mod 0.2.3: a second iPhone's Bluetooth iAP2 during a CarPlay session waits for its turn instead of replacing the current phone) |
| `mod/src/hmgapi/mods/wireless/dipo/NowPlaying.java`, `tests/nowplaying/` | From Korea Projection's HMG-API fork (StopDragon/HMG-API, branch `korea-build`, commit `577434c`, AGPL-3.0): song info on wireless CarPlay. The matching changes in `dipo/Bridge.java`, `dipo/Dipo.java`, `mod/settings.json` (`now_playing`) and the `IIap2Service` stub follow the same commit. Changed in mod 0.2.1: a name for its log lines, so the same start logic also starts the call state updates (`Bridge.CALL_STATE`) |
| `mod/mod.json`, `mod/patches.json` | Based on the same mod's files; changed for CVEV.KOR 260902 (id, system, feature flags, parts' changes, native recipes) |
| `mod/recipes/carplay-core-wifi.recipe`, `carplay-audio-formats.recipe`, `carplay-utils-converter.recipe` | Copied unchanged from the same mod |
| `mod/recipes/carplay-coreutils-usbwifi.recipe`, `carplay-core-screen-timeout.recipe` | New, made with HMG-API `tools/mkrecipe.py` (hashes of the stock bytes and our own new bytes only) |
| `maps/kia/ev6/kor/260902/` | Generated with HMG-API `tools/map-car.py` from the car's stock files (hook names and stock md5s only, no app code) |
| `apsync/`, `usb/`, `tests/`, `tools/build.sh` | New. `tools/build.sh` follows HMG-API's `build.sh` and `tools/mkmodpkg.sh`, and runs HMG-API's `tools/mknemesismod.sh` |
| `hotspot/`, `shared/`, `tests/hotspot-test.sh` | New (AGPL-3.0). `shared/rtwlan.sh` is `apsync/scripts/common.sh`'s dongle side, moved |
| `driver/` | New, **GPL-2.0**: build scripts and `patch-88x2bu.py` for the Realtek RTL8812BU/RTL8822BU driver from morrownr/88x2bu-20210702 (GPL-2.0). The `modules/` of the usb-hotspot-kr package carry the built driver with `SOURCE.txt` and the patch. Nothing from HKG_5W_USB_Wlan (usbwifi.hotspot) is used |
| `LICENSE` | HMG-API's (AGPL-3.0) |

No manufacturer (Hyundai/Kia/Mobis/Telechips) apps or libraries are included.

usbwifi.hotspot (GRT47/HKG_5W_USB_Wlan, no license file) is a separate NEMESIS package the owner installs from its own source; none of its code is copied here. `ev6kr.usbap.sync` works next to it at run time only: it rewrites a few keys of its `config/hotspot.conf` (AP_SSID, AP_PASS, AP_HW_MODE, AP_CHANNEL, ENABLE_LTE_NAT; saved and put back at uninstall), asks its daemon to restart through its `force_restart` file, and ejects a ZeroCD dongle's CD itself.
