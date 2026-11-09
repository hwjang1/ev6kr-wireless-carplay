package ev6kr.cpw;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

/**
 * Reads the stock hotspot settings file (/data/misc/wifi/softap.conf) the way the
 * head unit's framework writes it (android.net.wifi.WifiApConfigStore, format 3 on
 * Gen5W 260902):
 *
 *   int version (3), UTF SSID, UTF ConnectivitySSID, int authType, UTF preSharedKey,
 *   UTF ConnectivityPSK, int channel (5 GHz), int channel24GHzBand, boolean is24GHzBand,
 *   UTF vendorSpecific (CarPlay IE, hex), int apMode
 *
 * The iAP2 server sends ConnectivitySSID / ConnectivityPSK to the iPhone for wireless
 * CarPlay (Iap2Service.OnSendWifiInformation), so those are what the USB hotspot must use.
 * On units with com.hkmc.software.security.unece the PSKs are encrypted and the file is
 * /securedata/wifi/softap.conf; this tool refuses that case.
 *
 * usage: app_process /system/bin ev6kr.cpw.SoftApConf [shell|show|usbconf] [file]
 *   shell    CP_* assignments, single-quoted for /system/bin/sh (default)
 *   show     the same with the passwords masked, for logs
 *   usbconf  the AP_SSID / AP_PASS / AP_HW_MODE / AP_CHANNEL lines for the USB Wi-Fi
 *            package's config/hotspot.conf (which its daemon sources as shell)
 * exit: 0 ok, 2 no file, 3 unsupported format, 4 encrypted PSKs, 5 PSK not 8-63 chars
 */
public final class SoftApConf {
    static final String DEFAULT_FILE = "/data/misc/wifi/softap.conf";
    static final String UNECE = "com.hkmc.software.security.unece";

    String ssid, cpSsid, psk, cpPsk, vendorIe;
    int version, authType, channel, channel24, apMode;
    boolean is24;

    private SoftApConf() {}

    static SoftApConf read(File f) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(new FileInputStream(f)));
        try {
            SoftApConf c = new SoftApConf();
            c.version = in.readInt();
            if (c.version != 3) throw new IllegalStateException("version " + c.version);
            c.ssid = in.readUTF();
            c.cpSsid = in.readUTF();
            c.authType = in.readInt();
            c.psk = in.readUTF();
            c.cpPsk = in.readUTF();
            c.channel = in.readInt();
            c.channel24 = in.readInt();
            c.is24 = in.readBoolean();
            c.vendorIe = in.readUTF();
            c.apMode = in.readInt();
            return c;
        } finally {
            in.close();
        }
    }

    /** a value for /system/bin/sh: 'abc' with ' written as '\'' */
    static String q(String s) {
        if (s == null) s = "";
        StringBuilder b = new StringBuilder("'");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\'') b.append("'\\''");
            else b.append(c);
        }
        return b.append('\'').toString();
    }

    static boolean printable(String s) {
        if (s == null) return false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c < 0x20 || c == 0x7f) return false;
        }
        return true;
    }

    static String mask(String s) {
        if (s == null || s.length() == 0) return "(empty)";
        return s.length() + " chars";
    }

    /** a 5 GHz channel an AP may use here without radar detection (36-48, 149-165), else 149 (the stock default) */
    static int channel5(int ch) {
        if ((ch >= 36 && ch <= 48 && ch % 4 == 0) || (ch >= 149 && ch <= 165 && (ch - 149) % 4 == 0)) return ch;
        return 149;
    }

    /** a 2.4 GHz channel 1-13, else 1 (the stock default) */
    static int channel24(int ch) {
        return ch >= 1 && ch <= 13 ? ch : 1;
    }

    /** true when any permissions XML declares the feature that encrypts the PSKs */
    static boolean encryptedUnit() {
        File[] xs = new File("/system/etc/permissions").listFiles();
        if (xs == null) return false;
        byte[] buf = new byte[8192];
        for (File x : xs) {
            if (!x.getName().endsWith(".xml")) continue;
            try {
                FileInputStream in = new FileInputStream(x);
                try {
                    int n = in.read(buf);
                    if (n > 0 && new String(buf, 0, n, "UTF-8").contains(UNECE)) return true;
                } finally {
                    in.close();
                }
            } catch (IOException ignored) {
                // unreadable: doesn't count
            }
        }
        return false;
    }

    // ---- the live settings, through the same API the iAP2 server reads (WifiManager.getWifiApConfiguration)

    /** letters and digits without look-alikes (as the stock generator, minus its symbols) */
    static final String SAFE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

    /** a passphrase every hop handles as is: 8-63 letters and digits */
    static boolean safePsk(String p) {
        if (p == null || p.length() < 8 || p.length() > 63) return false;
        for (int i = 0; i < p.length(); i++) {
            char c = p.charAt(i);
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return false;
        }
        return true;
    }

    static int nonAlnum(String p) {
        int n = 0;
        for (int i = 0; p != null && i < p.length(); i++) {
            char c = p.charAt(i);
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) n++;
        }
        return n;
    }

    /** 12 safe characters with at least one upper case letter, one lower case letter and one digit */
    static String newPsk() {
        java.security.SecureRandom r = new java.security.SecureRandom();
        while (true) {
            StringBuilder b = new StringBuilder();
            for (int i = 0; i < 12; i++) b.append(SAFE_CHARS.charAt(r.nextInt(SAFE_CHARS.length())));
            String s = b.toString();
            boolean up = false, lo = false, di = false;
            for (int i = 0; i < s.length(); i++) {
                char c = s.charAt(i);
                up |= c >= 'A' && c <= 'Z';
                lo |= c >= 'a' && c <= 'z';
                di |= c >= '0' && c <= '9';
            }
            if (up && lo && di) return s;
        }
    }

    static Object wifiManager() throws Exception {
        Object b = Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, "wifi");
        if (b == null) throw new IllegalStateException("no wifi service");
        return Class.forName("android.net.wifi.IWifiManager$Stub").getMethod("asInterface", Class.forName("android.os.IBinder")).invoke(null, b);
    }

    static Object liveConfig(Object wm) throws Exception {
        return Class.forName("android.net.wifi.IWifiManager").getMethod("getWifiApConfiguration").invoke(wm);
    }

    static void setLiveConfig(Object wm, Object conf) throws Exception {
        Class<?> wc = Class.forName("android.net.wifi.WifiConfiguration");
        Class.forName("android.net.wifi.IWifiManager").getMethod("setWifiApConfiguration", wc).invoke(wm, conf);
    }

    static String field(Object o, String name) {
        try {
            Object v = o.getClass().getField(name).get(o);
            return v == null ? null : v.toString();
        } catch (Throwable t) {
            return null;
        }
    }

    static String readText(File f) throws IOException {
        FileInputStream in = new FileInputStream(f);
        try {
            byte[] b = new byte[256];
            int n = in.read(b);
            return n <= 0 ? "" : new String(b, 0, n, "UTF-8");
        } finally {
            in.close();
        }
    }

    static void writeText(File f, String s) throws IOException {
        java.io.FileOutputStream out = new java.io.FileOutputStream(f);
        try {
            out.write(s.getBytes("UTF-8"));
        } finally {
            out.close();
        }
    }

    public static void main(String[] args) {
        String mode = args.length > 0 ? args[0] : "shell";
        File f = new File(args.length > 1 ? args[1] : DEFAULT_FILE);
        File backup = args.length > 2 ? new File(args[2]) : null;
        if ("selftest".equals(mode)) {   // off-car test of the passphrase rules (tests/apsync-test.sh)
            for (int i = 0; i < 2000; i++) {
                String p = newPsk();
                if (p.length() != 12 || !safePsk(p)) {
                    System.out.println("selftest: bad passphrase " + p);
                    System.exit(1);
                }
            }
            boolean ok = safePsk("Abc12345") && !safePsk("Abc1234") && !safePsk("Abc$1234") && !safePsk("Ab c12345")
                    && !safePsk(null) && nonAlnum("a'b\"c$d\\e") == 4;
            System.out.println(ok ? "selftest: ok" : "selftest: rules wrong");
            System.exit(ok ? 0 : 1);
        }
        if (encryptedUnit()) {
            System.err.println("softap: this unit encrypts the hotspot passwords (" + UNECE + "), not supported");
            System.exit(4);
        }
        // the live settings: what the iAP2 server will send the phone
        Object wm = null, live = null;
        String liveWhy = null;
        try {
            wm = wifiManager();
            live = liveConfig(wm);
            if (live == null) liveWhy = "getWifiApConfiguration returned null";
        } catch (Throwable t) {
            liveWhy = String.valueOf(t.getCause() != null ? t.getCause() : t);
        }
        if ("restore".equals(mode)) {
            try {
                if (live == null) throw new IllegalStateException(liveWhy);
                String old = readText(backup);
                live.getClass().getField("ConnectivityPSK").set(live, old);
                setLiveConfig(wm, live);
                System.out.println("softap: projection passphrase put back (" + old.length() + " chars)");
                return;
            } catch (Throwable t) {
                System.err.println("softap: can't put the projection passphrase back: " + t);
                System.exit(6);
            }
        }
        int exit = 0;
        // the projection passphrase is handed to the phone over iAP2 and to the USB hotspot through
        // a shell-sourced file: one with symbols in it is replaced by 12 letters and digits
        if (live != null && backup != null && "usbconf".equals(mode)) {
            String lp = field(live, "ConnectivityPSK");
            if (!safePsk(lp)) {
                try {
                    if (lp != null && !backup.exists()) writeText(backup, lp);
                    String np = newPsk();
                    live.getClass().getField("ConnectivityPSK").set(live, np);
                    setLiveConfig(wm, live);
                    live = liveConfig(wm);
                    String now = field(live, "ConnectivityPSK");
                    if (!np.equals(now)) throw new IllegalStateException("not taken (now " + (now == null ? "null" : now.length() + " chars") + ")");
                    System.err.println("softap: projection passphrase had " + nonAlnum(lp) + " non-alphanumeric characters: replaced by 12 letters and digits (original saved in " + backup + ")");
                    exit = 8;
                } catch (Throwable t) {
                    System.err.println("softap: can't replace the projection passphrase: " + t);
                }
            }
        }
        SoftApConf c = null;
        if (f.isFile()) {
            try {
                c = read(f);
            } catch (Exception e) {
                System.err.println("softap: unsupported " + f + ": " + e);
            }
        }
        if (c == null && live == null) {
            System.err.println("softap: no " + f + " and no live settings (" + liveWhy + ")");
            System.exit(f.isFile() ? 3 : 2);
        }
        if (c == null) {
            c = new SoftApConf();
            c.version = 0;
            c.channel = 149;
            c.channel24 = 1;
        }
        String fileSsid = c.cpSsid, filePsk = c.cpPsk;
        String source = "file";
        if (live != null && printable(field(live, "ConnectivitySSID")) && printable(field(live, "ConnectivityPSK"))) {
            c.cpSsid = field(live, "ConnectivitySSID");
            c.cpPsk = field(live, "ConnectivityPSK");
            source = "live";
        } else {
            System.err.println("softap: live settings unavailable (" + liveWhy + "), using " + f);
            if (exit == 0) exit = 7;
        }
        String fileMatch = fileSsid == null ? "na" : (c.cpSsid.equals(fileSsid) && c.cpPsk.equals(filePsk) ? "yes" : "no");
        if ("live".equals(source) && "no".equals(fileMatch)) {
            System.err.println("softap: live settings differ from " + f + " (" + (c.cpSsid.equals(fileSsid) ? "" : "SSID ") + (c.cpPsk.equals(filePsk) ? "" : "passphrase") + "): using the live ones");
        }
        if (!printable(c.cpSsid) || !printable(c.cpPsk) || c.cpSsid.length() == 0) {
            System.err.println("softap: ConnectivitySSID/PSK empty or not printable");
            System.exit(3);
        }
        if ("usbconf".equals(mode)) {
            if (c.cpPsk.length() < 8 || c.cpPsk.length() > 63) {
                System.err.println("softap: ConnectivityPSK is " + c.cpPsk.length() + " chars, hostapd needs 8-63");
                System.exit(5);
            }
            System.out.print("AP_SSID=" + q(c.cpSsid) + "\nAP_PASS=" + q(c.cpPsk) + "\n"
                    + (c.is24 ? "AP_HW_MODE=g\nAP_CHANNEL=" + channel24(c.channel24) : "AP_HW_MODE=a\nAP_CHANNEL=" + channel5(c.channel)) + "\n");
            System.out.flush();
            System.exit(exit);
        }
        boolean show = "show".equals(mode);
        StringBuilder o = new StringBuilder();
        o.append("CP_SOURCE=").append(source).append('\n');
        o.append("CP_FILE_MATCH=").append(fileMatch).append('\n');
        o.append("CP_PSK_SAFE=").append(q(safePsk(c.cpPsk) ? "yes" : "no (" + nonAlnum(c.cpPsk) + " non-alphanumeric)")).append('\n');
        o.append("CP_VERSION=").append(c.version).append('\n');
        o.append("CP_SSID=").append(q(c.cpSsid)).append('\n');
        o.append("CP_PSK=").append(show ? q(mask(c.cpPsk)) : q(c.cpPsk)).append('\n');
        o.append("CP_AUTH=").append(c.authType).append('\n');
        o.append("CP_CHANNEL=").append(c.channel).append('\n');
        o.append("CP_CHANNEL24=").append(c.channel24).append('\n');
        o.append("CP_IS24=").append(c.is24 ? 1 : 0).append('\n');
        o.append("CP_APMODE=").append(c.apMode).append('\n');
        o.append("CP_IE=").append(q(printable(c.vendorIe) ? c.vendorIe : "")).append('\n');
        System.out.print(o);
        System.out.flush();
    }
}
