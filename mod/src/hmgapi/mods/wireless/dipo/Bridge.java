package hmgapi.mods.wireless.dipo;

import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiConfiguration;
import android.os.Handler;
import android.os.HandlerThread;

import com.broadcom.bt.hfdevice.hfbtcm.HfDeviceBTCMManager;
import com.broadcom.bt.hfdevice.hfbtcm.HfDeviceStatusListener;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Method;
import java.util.ArrayList;

import hmgapi.hook.Points;

/**
 * Wireless CarPlay's Bluetooth bridge, in DiPO (from the bridge build, com.ev6.cpwl).
 *
 * An iPhone pairs over Bluetooth; wireless CarPlay starts with iAP2 over Bluetooth
 * (RFCOMM/SPP), which the iAP2 server here can't do by itself. The bridge carries it:
 * SPP data from Broadcom's Bluetooth manager goes into the iAP2 server as transport data
 * (Iap2SvcTransportReadDone), and what the server sends back (notification 80) goes out
 * over SPP. The iAP2 server opens the session for BT_ATTACHED (HMG-API's hook there, part
 * "bridge"). Once the phone has joined the hotspot and the CarPlay session runs, iAP2
 * moves into the CarPlay session's own channel: bytes the phone sends there
 * (oniAPSendMessage) go to the server, and what the server sends for it
 * (notification 81) goes out through the CarPlay library.
 *
 * HMG-API binds the iAP2 server and hooks Broadcom's manager (a library), and only
 * observes DiPO's CarPlay callbacks; DiPO's own iAP2 listener is told to ignore what
 * belongs to the bridge's sessions (Dipo's hooks).
 *
 * persist.ev6.cpwl.enable=0 turns it off; persist.ev6.cpwl.handover=created moves iAP2
 * into the CarPlay channel as soon as the session is created (default: on its first data).
 */
final class Bridge {
    static final String ACTION_ATTACH = "com.ev6.cpwl.BT_ATTACHED", ACTION_DETACH = "com.ev6.cpwl.BT_DETACHED";
    static final String IAP2_PKG = "com.tcc.iap2server";
    static final int APPLE_VENDOR_ID = 76;
    /** iAP2 components: 1 USB, 4 Bluetooth CarPlay, 5 the CarPlay session's channel */
    static final int COMPONENT_USB = 1, COMPONENT_BT_CARPLAY = 4, COMPONENT_CARPLAY_CLIENT = 5;
    static final int LISTENER_EXTERNAL_BT_TRANSPORT = 1024, LISTENER_EXTERNAL_CARPLAY_TRANSPORT = 2048;
    static final int NOTI_IDENTIFICATION_ACCEPTED = 0, NOTI_TRANSPORT_IDENTIFIER = 24;
    static final int NOTI_BT_TRANSPORT_DATA = 80, NOTI_CARPLAY_CLIENT_TRANSPORT_DATA = 81, OBJ_BLOB = 11;
    static final int MAX_PENDING = 64;
    static final long SPP_CONNECT_DELAY_MS = 3000;
    static final int SPP_DISCONNECTED = 0, SPP_CONNECTED = 2, EVENT_BTCM_CONNECTED = 2;

    static volatile String sAddr;
    static volatile HfDeviceBTCMManager sBtcm;
    static volatile Object sCp;
    static volatile boolean sCpClient, sCpConnected, sCpWireless, sSession, sUsb;
    static volatile IIap2Service sIap2;
    /** the phone's Bluetooth address from its last iAP2 session (DiPO's first-connect notice) */
    static volatile String sLastBtId;
    static ClassLoader cl;
    static Context context;
    private static int sCpFail, sCpSent;
    private static Handler sHandler, sCpTx;
    private static Method sNativeSend;
    private static final ArrayList<byte[]> sPendingIn = new ArrayList<byte[]>();
    private static BtListener sBt;
    private static TxListener sTx;

    private Bridge() {}

    static void log(String m) {
        Dipo.log("bridge: " + m);
    }

    static void error(String m, Throwable t) {
        Dipo.error("bridge: " + m, t);
    }

    /** DiPO registered its listener with Broadcom's manager (the manager is connected): ours goes next to it */
    static void onBtcmReady(HfDeviceBTCMManager m) {
        if (m == null) return;
        try {
            sBtcm = m;
            synchronized (Bridge.class) {
                if (sBt == null) sBt = new BtListener();
            }
            m.registerHfDeviceStatusListener(sBt);
            log("BTCM listener registered");
            BluetoothDevice d = m.IbtcmGetHfpConnectedDevice();
            if (d != null && isApple(d)) scheduleSppConnect(d.getAddress());
        } catch (Throwable t) {
            error("onBtcmReady", t);
        }
    }

    static boolean isOurs(Object listener) {
        return listener != null && listener == sBt;
    }

    /** the iAP2 server is bound: register for Bluetooth and CarPlay-channel transport data */
    static void onIap2Bound(IIap2Service s) {
        if (s == null) return;
        try {
            sIap2 = s;
            synchronized (Bridge.class) {
                if (sTx == null) sTx = new TxListener();
            }
            Iap2ListenerInfo info = new Iap2ListenerInfo();
            info.onSetSupportType(LISTENER_EXTERNAL_BT_TRANSPORT | LISTENER_EXTERNAL_CARPLAY_TRANSPORT);
            info.onSetListenerName("EV6_CPWL_BT");
            log("Iap2SvcInit(EV6_CPWL_BT, 0xc00) = " + s.Iap2SvcInit(sTx, info));
        } catch (Throwable t) {
            error("onIap2Bound", t);
        }
    }

    static boolean enabled() {
        return !"0".equals(prop("persist.ev6.cpwl.enable", "1"));
    }

    /** a system property (android.os.SystemProperties isn't in the public SDK) */
    static String prop(String key, String fallback) {
        try {
            return (String) Class.forName("android.os.SystemProperties").getMethod("get", String.class, String.class).invoke(null, key, fallback);
        } catch (Throwable t) {
            return fallback;
        }
    }

    static synchronized Handler handler() {
        if (sHandler == null) {
            HandlerThread t = new HandlerThread("hmgapi-cpwl");
            t.start();
            sHandler = new Handler(t.getLooper());
        }
        return sHandler;
    }

    static boolean isApple(BluetoothDevice d) {
        if (d == null) return false;
        try {
            Object v = BluetoothDevice.class.getMethod("getVendor").invoke(d);
            if (v instanceof Integer) return (Integer) v == APPLE_VENDOR_ID;
        } catch (Throwable t) {
            // no vendor id on this build: by name
        }
        try {
            String n = d.getName();
            return n != null && (n.contains("iPhone") || n.contains("iPad"));
        } catch (Throwable t) {
            return false;
        }
    }

    static void scheduleSppConnect(final String addr) {
        if (addr == null || !enabled() || sUsb || sSession || sCpWireless) return;
        handler().postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    HfDeviceBTCMManager m = sBtcm;
                    if (m == null || sUsb || sSession || sCpWireless || !enabled()) return;
                    if (m.IbtcmIsSppConnectedDevice(addr)) log("SPP already up for " + addr);
                    else log("IbtcmSppConnect(" + addr + ") = " + m.IbtcmSppConnect(addr));
                } catch (Throwable t) {
                    error("sppConnect", t);
                }
            }
        }, SPP_CONNECT_DELAY_MS);
    }

    static void onSppUp(final String addr) {
        if (addr == null || sSession) return;
        sAddr = addr;
        if (sCpClient || sCpWireless || !enabled() || sUsb) return;
        sSession = true;
        handler().post(new Runnable() {
            @Override
            public void run() {
                try {
                    Context c = context;
                    if (c == null) {
                        log("no context, cannot start session");
                        sSession = false;
                        return;
                    }
                    ensureHotspot(c);
                    Intent i = new Intent(ACTION_ATTACH);
                    i.setPackage(IAP2_PKG);
                    i.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
                    i.putExtra("component", COMPONENT_BT_CARPLAY);
                    i.putExtra("serial", addr);
                    c.sendBroadcast(i);
                    log("BT_ATTACHED sent for " + addr);
                } catch (Throwable t) {
                    sSession = false;
                    error("onSppUp", t);
                }
            }
        });
    }

    static void onUsbGone() {
        final String addr = sAddr;
        if (addr == null || sSession) return;
        handler().postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    HfDeviceBTCMManager m = sBtcm;
                    if (m != null && !sUsb && !sSession && addr.equals(sAddr) && m.IbtcmIsSppConnectedDevice(addr)) onSppUp(addr);
                } catch (Throwable t) {
                    error("onUsbGone", t);
                }
            }
        }, SPP_CONNECT_DELAY_MS);
    }

    static void onCpSessionCreated(Object cp) {
        if (cp != null) sCp = cp;
        log("CarPlay session created (usb=" + sUsb + " btAddr=" + sAddr + ")");
        if ("created".equals(prop("persist.ev6.cpwl.handover", "data")) && !sUsb && sAddr != null) {
            startCpClient("session created");
        }
    }

    static void onCpSessionStarted(int transport) {
        sCpWireless = transport == 1 && !sUsb;
        log("CarPlay session started transport=" + transport + " wireless=" + sCpWireless);
    }

    /** iAP2 bytes from the phone over the CarPlay channel: to the iAP2 server (buffered until its session is up) */
    static void onCpIapIn(Object cp, byte[] data, int len) {
        try {
            if (cp != null) sCp = cp;
            if (data == null || len <= 0 || sUsb) return;
            if (len >= data.length) len = data.length;
            byte[] b = new byte[len];
            System.arraycopy(data, 0, b, 0, len);
            if (!sCpClient) startCpClient("iAP2 data from CarPlay channel");
            IIap2Service s = sIap2;
            if (sCpConnected && s != null) {
                flushPending(s);
                s.Iap2SvcTransportReadDone(b, len);
            } else {
                synchronized (sPendingIn) {
                    if (sPendingIn.size() < MAX_PENDING) sPendingIn.add(b);
                }
            }
        } catch (Throwable t) {
            error("onCpIapIn", t);
        }
    }

    static void onCpSessionFinalized(int type) {
        try {
            log("CarPlay session finalized type=" + type + " cpClient=" + sCpClient);
            boolean client = sCpClient, wireless = sCpWireless;
            sCpWireless = false;
            sCpClient = false;
            sCpConnected = false;
            NOW_PLAYING.reset();
            CALL_STATE.reset();
            sCallState = false;
            synchronized (sPendingIn) {
                sPendingIn.clear();
            }
            if (client) sendDetach();
            if (client || wireless) onUsbGone();
        } catch (Throwable t) {
            error("onCpSessionFinalized", t);
        }
    }

    /** DiPO's iAP2 listener: ignore the Bluetooth and CarPlay-channel sessions ending while wireless CarPlay is up */
    static boolean dipoIgnoreDisconnect(int component) {
        boolean ignore = (sCpClient || sCpWireless) && (component == COMPONENT_BT_CARPLAY || component == COMPONENT_CARPLAY_CLIENT);
        if (ignore) log("DiPO: ignoring iAP2 disconnect comp=" + component + " (wireless CarPlay up)");
        return ignore;
    }

    /** DiPO's iAP2 listener: the CarPlay-channel session's identification isn't a new phone */
    static boolean dipoDropNoti(int what) {
        boolean drop = sCpClient && (what == NOTI_IDENTIFICATION_ACCEPTED || what == NOTI_TRANSPORT_IDENTIFIER);
        if (drop) log("DiPO: dropping iAP2 noti " + what + " from the CarPlay-channel session");
        if (drop && NOW_PLAYING.due(Dipo.nowPlaying, sCpClient, what)) startNowPlaying(NOW_PLAYING.session(), 1);
        if (drop && CALL_STATE.due(Dipo.callState, sCpClient, what)) startCallState(CALL_STATE.session(), 1);
        return drop;
    }

    /**
     * Call state on wireless (setting call_state, mod 0.2.1): DiPO starts the phone's call
     * state and telephony updates only on USB, in the same setStartiAP2Service branch as
     * NowPlaying. Without them its caller list stays empty, so the steering wheel's call
     * button sends HookSwitch ("no call") during a call, which the iPhone takes as hold
     * (EV6 KR, 2026-11-10), where a USB session sends Drop (end). Started the NowPlaying way.
     */
    static final NowPlaying CALL_STATE = new NowPlaying("call state updates");
    /** the call state updates run for this CarPlay-channel session (DiPO's caller list can be trusted) */
    static volatile boolean sCallState;

    private static void startCallState(final int session, final int tryNo) {
        handler().postDelayed(new Runnable() {
            @Override
            public void run() {
                final IIap2Service s = sIap2;
                final String[] updates = { null };
                String r = CALL_STATE.attempt(session, tryNo, sCpClient, new NowPlaying.Server() {
                    @Override
                    public boolean start() throws Exception {
                        if (s == null) return false;
                        if (!s.Iap2SvcTelephonyStartCallState()) return false;
                        try {
                            updates[0] = s.Iap2SvcTelephonyStartUpdates() ? "telephony updates too" : "telephony updates refused";
                        } catch (Throwable t) {
                            updates[0] = "telephony updates failed: " + t;
                        }
                        return true;
                    }
                });
                if (r == null) startCallState(session, tryNo + 1);
                else if (!r.isEmpty()) {
                    if (updates[0] != null) sCallState = true;
                    log(r + (updates[0] == null ? "" : ", " + updates[0]));
                }
            }
        }, NowPlaying.DELAY_MS + 200);
    }

    /** song info on wireless: DiPO asks for it only on USB (see NowPlaying) */
    static final NowPlaying NOW_PLAYING = new NowPlaying();

    private static void startNowPlaying(final int session, final int tryNo) {
        handler().postDelayed(new Runnable() {
            @Override
            public void run() {
                final IIap2Service s = sIap2;
                String r = NOW_PLAYING.attempt(session, tryNo, sCpClient, new NowPlaying.Server() {
                    @Override
                    public boolean start() throws Exception {
                        if (s == null) return false;
                        return s.Iap2SvcNowPlayingStart();
                    }
                });
                if (r == null) startNowPlaying(session, tryNo + 1);
                else if (!r.isEmpty()) log(r);
            }
        }, NowPlaying.DELAY_MS);
    }

    static void startCpClient(final String why) {
        if (sCpClient) return;
        NOW_PLAYING.reset();
        CALL_STATE.reset();
        sCallState = false;
        sCpClient = true;
        sCpConnected = false;
        final String addr = sAddr;
        handler().post(new Runnable() {
            @Override
            public void run() {
                try {
                    Context c = context;
                    if (c == null) return;
                    Intent i = new Intent(ACTION_ATTACH);
                    i.setPackage(IAP2_PKG);
                    i.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
                    i.putExtra("component", COMPONENT_CARPLAY_CLIENT);
                    i.putExtra("serial", addr);
                    c.sendBroadcast(i);
                    log("iAP2 handover to CarPlay channel requested (" + why + ")");
                } catch (Throwable t) {
                    error("startCpClient", t);
                }
            }
        });
    }

    static void onCpClientConnected() {
        sCpConnected = true;
        IIap2Service s = sIap2;
        if (s != null) flushPending(s);
    }

    private static void flushPending(IIap2Service s) {
        ArrayList<byte[]> all;
        synchronized (sPendingIn) {
            if (sPendingIn.isEmpty()) return;
            all = new ArrayList<byte[]>(sPendingIn);
            sPendingIn.clear();
        }
        for (byte[] b : all) {
            try {
                s.Iap2SvcTransportReadDone(b, b.length);
            } catch (Throwable t) {
                error("flushPending", t);
            }
        }
        log("flushed " + all.size() + " buffered CarPlay-channel packets");
    }

    private static synchronized Handler cpTx() {
        if (sCpTx == null) {
            HandlerThread t = new HandlerThread("hmgapi-cp-tx");
            t.start();
            sCpTx = new Handler(t.getLooper());
        }
        return sCpTx;
    }

    private static Method nativeSend() {
        if (sNativeSend == null) sNativeSend = Points.method(cl, "dipo.carplay.native_iap_send");
        return sNativeSend;
    }

    /** iAP2 bytes from the server for the CarPlay channel: out through the CarPlay library */
    static void writeCp(byte[] data) {
        final Object cp = sCp;
        if (cp == null || data == null || data.length == 0 || !sCpClient) return;
        final byte[] b = data.clone();
        cpTx().post(new Runnable() {
            @Override
            public void run() {
                try {
                    Object r = nativeSend().invoke(cp, b, b.length);
                    int rc = r instanceof Integer ? (Integer) r : -1;
                    if (rc == 0) {
                        sCpSent++;
                        if (sCpSent <= 3 || sCpSent % 200 == 0) log("CarPlay-channel iAP2 sent " + b.length + " bytes (#" + sCpSent + ")");
                    } else {
                        sCpFail++;
                        if (sCpFail <= 5 || sCpFail % 50 == 0) log("CarPlay-channel iAP2 send failed rc=" + rc + " len=" + b.length);
                    }
                } catch (Throwable t) {
                    error("writeCp native", t);
                }
            }
        });
    }

    static void onSppDown(String addr) {
        if (addr == null || !addr.equals(sAddr)) return;
        if (sCpWireless) {
            sSession = false;
            startCpClient("bluetooth dropped during wireless CarPlay");
            return;
        }
        sAddr = null;
        if (sSession) {
            sSession = false;
            sendDetach();
        }
    }

    static void sendDetach() {
        handler().post(new Runnable() {
            @Override
            public void run() {
                try {
                    Context c = context;
                    if (c == null) return;
                    Intent i = new Intent(ACTION_DETACH);
                    i.setPackage(IAP2_PKG);
                    i.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
                    c.sendBroadcast(i);
                    log("BT_DETACHED sent");
                } catch (Throwable t) {
                    error("sendDetach", t);
                }
            }
        });
    }

    /** SPP data from the phone: to the iAP2 server */
    static void onSppData(BluetoothDevice d, byte[] data, int len) {
        try {
            String addr = sAddr;
            IIap2Service s = sIap2;
            if (addr == null || s == null || d == null || data == null || len <= 0 || !sSession || !addr.equals(d.getAddress())) return;
            if (len >= data.length) len = data.length;
            if (len != data.length) {
                byte[] b = new byte[len];
                System.arraycopy(data, 0, b, 0, len);
                data = b;
            }
            s.Iap2SvcTransportReadDone(data, len);
        } catch (Throwable t) {
            error("onSppData", t);
        }
    }

    /** iAP2 bytes from the server for the Bluetooth session: out over SPP */
    static void writeSpp(byte[] data) {
        try {
            String addr = sAddr;
            HfDeviceBTCMManager m = sBtcm;
            if (addr == null || m == null || data == null || data.length == 0 || !sSession) return;
            if (!m.IbtcmSppOutPutStreamWrite(addr, data)) log("SPP write failed, " + data.length + " bytes");
        } catch (Throwable t) {
            error("writeSpp", t);
        }
    }

    /**
     * Where a USB Wi-Fi hotspot keeps its hostapd pid: the usb-hotspot-kr mod's (standalone) and
     * the usbwifi.hotspot package's. Both drivers name interfaces rtwlan0, rtwlan1, ...
     */
    static final String[] USB_HOSTAPD_PIDS = {
        "/data/local/tmp/ev6kr_usbap/hostapd.pid",
        "/data/local/tmp/usbwifi_hotspot/hostapd.pid"
    };

    /** a USB Wi-Fi hotspot's hostapd runs */
    static boolean usbHostapdRunning() {
        for (String f : USB_HOSTAPD_PIDS) {
            String pid = firstLine(f);
            if (pid != null && pid.trim().length() > 0 && new File("/proc/" + pid.trim()).isDirectory()) return true;
        }
        return false;
    }

    /** the USB Wi-Fi hotspot's interface when it's up (hostapd running, an rtwlan* interface up), else null */
    static String usbHotspot() {
        if (!usbHostapdRunning()) return null;
        String[] ifs = new File("/sys/class/net").list();
        if (ifs == null) return null;
        for (String i : ifs) {
            if (!i.startsWith("rtwlan")) continue;
            String st = firstLine("/sys/class/net/" + i + "/operstate");
            if (st != null && ("up".equals(st.trim()) || "unknown".equals(st.trim()))) return i;
        }
        return null;
    }

    static String firstLine(String path) {
        BufferedReader r = null;
        try {
            r = new BufferedReader(new FileReader(path));
            return r.readLine();
        } catch (Throwable t) {
            return null;
        } finally {
            if (r != null) {
                try {
                    r.close();
                } catch (Throwable ignored) {
                    // nothing to do
                }
            }
        }
    }

    /**
     * A USB Wi-Fi dongle is on the bus now: a USB interface (e.g. 4-1:1.0) bound to one of the
     * Realtek drivers (rtl88x2bu, rtl8851bu, ...). Not the net interface: usbwifi.hotspot's driver
     * build drops SET_NETDEV_DEV (hot-unplug safety), so rtwlanN has no device link there, and a
     * gone one lingers.
     */
    static boolean usbWifiPresent() {
        String[] drivers = new File("/sys/bus/usb/drivers").list();
        if (drivers != null) {
            for (String d : drivers) {
                if (!d.startsWith("rtl")) continue;
                String[] e = new File("/sys/bus/usb/drivers/" + d).list();
                if (e == null) continue;
                for (String x : e) {
                    if (x.indexOf(':') > 0) return true;
                }
            }
        }
        return usbWifiOnBus();
    }

    /**
     * Realtek USB Wi-Fi (RTL8812BU/8822BU, RTL8831BU/8851BU) vendor:product pairs that
     * usbwifi.hotspot's drivers take, for a dongle on the bus that no driver has bound yet: just
     * plugged in, or its driver still starting. The 10th collection (2026-11-08 14:17) had DiPO's
     * reset land in that window and cut the dongle while it was coming up.
     */
    static final String[] USB_WIFI_IDS = {
        "0bda:b812", "0bda:b82c", "0bda:b81a", "0bda:b820", "0bda:b82b",
        "0bda:b831", "0bda:b851", "0bda:b832", "0bda:1a2b"
    };

    static boolean usbWifiOnBus() {
        String[] devs = new File("/sys/bus/usb/devices").list();
        if (devs == null) return false;
        for (String d : devs) {
            if (d.indexOf(':') >= 0) continue;   // interfaces; devices are like 4-1
            String v = firstLine("/sys/bus/usb/devices/" + d + "/idVendor");
            String p = firstLine("/sys/bus/usb/devices/" + d + "/idProduct");
            if (v == null || p == null) continue;
            String id = v.trim() + ":" + p.trim();
            for (String w : USB_WIFI_IDS) {
                if (w.equals(id)) return true;
            }
        }
        return false;
    }

    /**
     * EV6 KR: DiPO treats the Bluetooth CarPlay session like a USB phone (as on the US/Canadian
     * cars), and when no session has started ~6 s after CarPlay starts it shows a connection
     * error and resets the USB port's power (DipoService: sys.usb.vbus_ctrl off/on, or MICOM's
     * requestVBusOffOn). On this car that port holds the USB Wi-Fi dongle: the reset dropped
     * the hotspot while the iPhone was joining it (first car test, 0.1.1). Both resets are
     * skipped in DiPO's process while a dongle is on the port; without one they run as stock.
     */
    static void usbResetGuard(ClassLoader cl) {
        try {
            hmgapi.hook.Hooks.findAndHookMethod("android.os.SystemProperties", cl, "set", String.class, String.class, new hmgapi.hook.MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!"sys.usb.vbus_ctrl".equals(p.args[0])) return;
                    if (!usbWifiPresent()) {
                        log("USB power reset (sys.usb.vbus_ctrl " + p.args[1] + "): no USB Wi-Fi dongle on the port, left as stock");
                        return;
                    }
                    p.setResult(null);
                    log("USB power reset (sys.usb.vbus_ctrl " + p.args[1] + ") skipped: the USB Wi-Fi dongle is on the port");
                }
            });
            log("USB reset guard on sys.usb.vbus_ctrl");
        } catch (Throwable t) {
            error("USB reset guard (sys.usb.vbus_ctrl)", t);
        }
        try {
            hmgapi.hook.Hooks.findAndHookMethod("com.hkmc.micom.ISystemService$Stub$Proxy", cl, "requestVBusOffOn", new hmgapi.hook.MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!usbWifiPresent()) {
                        log("USB power reset (MICOM requestVBusOffOn): no USB Wi-Fi dongle on the port, left as stock");
                        return;
                    }
                    p.setResult(null);
                    log("USB power reset (MICOM requestVBusOffOn) skipped: the USB Wi-Fi dongle is on the port");
                }
            });
            log("USB reset guard on MICOM requestVBusOffOn");
        } catch (Throwable t) {
            error("USB reset guard (requestVBusOffOn)", t);
        }
    }

    /**
     * The hotspot wireless CarPlay joins. EV6 KR: the head unit has no Wi-Fi chip, so the
     * hotspot is on a USB Wi-Fi dongle, on the stock CarPlay SSID/password: the usb-hotspot-kr
     * mod's, or usbwifi.hotspot's (which ev6kr.usbap.sync keeps on them); the stock hotspot is
     * only started on a unit with its own chip (wlan0), as on the US/Canadian cars.
     */
    static void ensureHotspot(Context c) {
        String usb = usbHotspot();
        if (usb != null) {
            log("USB Wi-Fi hotspot up on " + usb);
            return;
        }
        if (!new File("/sys/class/net/wlan0").exists()) {
            log("no USB Wi-Fi hotspot running and no stock Wi-Fi chip: wireless CarPlay can't join (the dongle in, and usb-hotspot-kr on, or usbwifi.hotspot in AP mode?)");
            return;
        }
        ensureStockHotspot(c);
    }

    /** the head unit's own hotspot in mode 2 (for connectivity), which wireless CarPlay joins */
    static void ensureStockHotspot(Context c) {
        try {
            Object wifi = c.getSystemService(Context.WIFI_SERVICE);
            if (wifi == null) return;
            Class<?> k = wifi.getClass();
            boolean on = false;
            int mode;
            try {
                on = (Boolean) k.getMethod("isWifiApEnabled").invoke(wifi);
            } catch (Throwable t) {
                // no such call: treat as off
            }
            try {
                mode = (Integer) k.getMethod("getWifiApMode").invoke(wifi);
            } catch (Throwable t) {
                mode = -1;
            }
            if (on && mode == 2) {
                log("hotspot already up (mode 2)");
                return;
            }
            Object conf = k.getMethod("getWifiApConfiguration").invoke(wifi);
            Object r = k.getMethod("setWifiApEnabledForConnectivity", WifiConfiguration.class, boolean.class).invoke(wifi, conf, true);
            log("setWifiApEnabledForConnectivity -> " + r + " (was on=" + on + " mode=" + mode + ")");
        } catch (Throwable t) {
            error("ensureHotspot", t);
        }
    }

    /** Broadcom's status callbacks: an iPhone connects (start SPP), SPP up/down, SPP data */
    static final class BtListener extends HfDeviceStatusListener {
        @Override
        public void onBTCMDeviceConnectionEventChanged(BluetoothDevice d, int event, boolean[] profiles) {
            if (event != EVENT_BTCM_CONNECTED) return;
            try {
                if (isApple(d)) {
                    log("iPhone BT connected: " + d.getAddress());
                    scheduleSppConnect(d.getAddress());
                }
            } catch (Throwable t) {
                error("connEvent", t);
            }
        }

        @Override
        public void onBTCMSppStatusChanged(BluetoothDevice d, int status) {
            if (d == null) return;
            try {
                if (!isApple(d)) return;
                String addr = d.getAddress();
                log("SPP status " + status + " for " + addr);
                if (status == SPP_CONNECTED) onSppUp(addr);
                else if (status == SPP_DISCONNECTED) onSppDown(addr);
            } catch (Throwable t) {
                error("sppStatus", t);
            }
        }

        @Override
        public void onBTCMSppInPutStreamChanged(BluetoothDevice d, byte[] buffer, int length) {
            onSppData(d, buffer, length);
        }
    }

    /** the iAP2 server's side: USB and CarPlay-channel sessions, and transport data to send */
    static final class TxListener extends IIap2Listener.Stub {
        @Override
        public void connected(int component, String serial) {
            log("iAP2 connected comp=" + component);
            // what DiPO keeps as the current device (setCurrentIapDeviceName): a Bluetooth address is the notice's key
            if ((component == COMPONENT_USB || component == COMPONENT_BT_CARPLAY) && serial != null && serial.contains(":")) sLastBtId = serial;
            if (component == COMPONENT_USB) sUsb = true;
            else if (component == COMPONENT_CARPLAY_CLIENT) onCpClientConnected();
        }

        @Override
        public void disconnected(int component) {
            log("iAP2 disconnected comp=" + component);
            if (component == COMPONENT_USB) {
                sUsb = false;
                onUsbGone();
            } else if (component == COMPONENT_BT_CARPLAY) {
                sSession = false;
            } else if (component == COMPONENT_CARPLAY_CLIENT) {
                sCpConnected = false;
                NOW_PLAYING.reset();
            }
        }

        @Override
        public void notify(int what, int a1, int a2, Iap2NotiMsg msg) {
            if ((what != NOTI_BT_TRANSPORT_DATA && what != NOTI_CARPLAY_CLIENT_TRANSPORT_DATA) || msg == null) return;
            try {
                Iap2NotiMsg.Iap2ObjGroup g = msg.getItemGroup();
                if (g == null) return;
                for (int k = 0; k < g.getItemCnt(); k++) {
                    Iap2NotiMsg.Iap2ObjItem it = g.getObjItem(k);
                    if (it == null || it.getItemParamType() != OBJ_BLOB) continue;
                    if (what == NOTI_CARPLAY_CLIENT_TRANSPORT_DATA) writeCp(it.getItemByteArray());
                    else writeSpp(it.getItemByteArray());
                }
            } catch (Throwable t) {
                error("notify", t);
            }
        }
    }
}
