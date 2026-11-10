package hmgapi.mods.wireless;

import java.io.FileInputStream;
import java.lang.reflect.Member;

import hmgapi.hook.MethodHook;
import hmgapi.hook.ModContext;
import hmgapi.hook.Points;

/**
 * EV6 KR (mod 0.2.1): two of the car's own services in system_server (automotive-service.jar,
 * loaded by com.hkmc.internal.Loader: hook point framework.hkmc_loader.automotive_service, as
 * HMG-API's own button bindings do). Hooked by name: automotive-service of 260902.
 *
 * Cluster song popup (cluster_artist): ClusterService.updateClusterWithArtistInfo(mode, track,
 * seconds, title, artist, userInput) sends the title and the artist to the HUD
 * (updateFileNameWithArtistDelayed, TP_TxHandleCon_H_UHUD_202) and the title alone to the
 * cluster (updateFilenameDelayed(mode, title, delay)), so the cluster's song popup shows the
 * title only. For CarPlay (mode DIPO, 0x73) the cluster gets "artist - title" (ClusterText);
 * the HUD is left as it is.
 *
 * Voice button (siri_key): ModeKeyDispatcher.determineWhichAppToSendPttKey picks who gets the
 * voice button. With CarPlay connected and neither Siri nor the car's voice recognition running
 * it is both (SEND_PTT_TO_VR_CARPLAYSIRI, 2): a short press starts the car's voice recognition,
 * and Siri needs a long press. This makes it CarPlay only (SEND_PTT_TO_CARPLAYSIRI_ONLY, 0),
 * where DiPO then opens Siri on a short press (dipo/CarKeys). With CarPlay not connected, or
 * the car's voice recognition already running, nothing changes.
 */
final class SystemHooks {
    private SystemHooks() {}

    static final String CLUSTER_SERVICE = "com.hkmc.micom.ClusterService";
    static final String KEY_DISPATCHER = "com.hkmc.micom.ModeKeyDispatcher";
    /** ModeConstants.ModeType.DIPO */
    static final int MODE_DIPO = 0x73;
    static final int PTT_TO_CARPLAYSIRI_ONLY = 0, PTT_TO_VR_CARPLAYSIRI = 2;

    static volatile boolean installed;
    /** updateClusterWithArtistInfo's title and artist while it runs (CarPlay only) */
    static final ThreadLocal<String[]> SONG = new ThreadLocal<String[]>();
    static volatile boolean artistLogged;
    static volatile long lastSiriLog;

    /** Wireless.zygoteInit: the hooks go in when system_server loads automotive-service */
    static void zygote(final ModContext mod) {
        final boolean artist = mod.settingBoolean("cluster_artist", true);
        final boolean siri = mod.settingBoolean("bridge", true) && mod.settingBoolean("siri_key", true);
        if (!artist && !siri) return;
        mod.hook(null, "framework.hkmc_loader.automotive_service", new MethodHook() {
            @Override
            protected void afterHookedMethod(Param p) {
                if (installed || p.getResult() == null || !"system_server".equals(processName())) return;
                installed = true;
                try {
                    ClassLoader cl = (ClassLoader) Points.get(null, "framework.hkmc_loader.class_loader", p.getResult());
                    if (artist) clusterArtist(mod, cl);
                    if (siri) siriKey(mod, cl);
                } catch (Throwable t) {
                    mod.error("system_server hooks", t);
                }
            }
        });
    }

    private static void clusterArtist(final ModContext mod, ClassLoader cl) {
        try {
            Class<?> cs = cl.loadClass(CLUSTER_SERVICE);
            hmgapi.hook.Hooks.findAndHookMethod(cs, "updateClusterWithArtistInfo", int.class, int.class, int.class,
                    String.class, String.class, boolean.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!mod.enabled()) return;
                    if (Integer.valueOf(MODE_DIPO).equals(p.args[0])) SONG.set(new String[] { (String) p.args[3], (String) p.args[4] });
                }

                @Override
                protected void afterHookedMethod(Param p) {
                    SONG.remove();
                }
            });
            hmgapi.hook.Hooks.findAndHookMethod(cs, "updateFilenameDelayed", int.class, String.class, long.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    String[] song = SONG.get();
                    if (song == null || !Integer.valueOf(MODE_DIPO).equals(p.args[0])) return;
                    String title = (String) p.args[1];
                    if (title == null || !title.equals(song[0])) return;
                    String shown = ClusterText.join(song[1], title);
                    if (shown.equals(title)) return;
                    p.args[1] = shown;
                    if (!artistLogged) {
                        artistLogged = true;
                        mod.log("cluster: CarPlay song popup shows \"artist - title\" (" + shown.length() + " chars; logged once)");
                    }
                }
            });
            mod.log("cluster: artist added to the CarPlay song title on the cluster");
        } catch (Throwable t) {
            mod.error("cluster: song title hook (ClusterService not as expected)", t);
        }
    }

    private static void siriKey(final ModContext mod, ClassLoader cl) {
        try {
            Class<?> kd = cl.loadClass(KEY_DISPATCHER);
            Member m = hmgapi.hook.Hooks.findAndHookMethod(kd, "determineWhichAppToSendPttKey", int.class, new MethodHook() {
                @Override
                protected void afterHookedMethod(Param p) {
                    if (!mod.enabled() || !Integer.valueOf(PTT_TO_VR_CARPLAYSIRI).equals(p.getResult())) return;
                    p.setResult(PTT_TO_CARPLAYSIRI_ONLY);
                    long now = System.currentTimeMillis();
                    if (now - lastSiriLog > 2000) {
                        lastSiriLog = now;
                        mod.log("voice button: CarPlay connected, to Siri (DiPO) only, not the car's voice recognition");
                    }
                }
            });
            if (m != null) mod.log("voice button: Siri on a short press while CarPlay is connected");
        } catch (Throwable t) {
            mod.error("voice button: routing hook (ModeKeyDispatcher not as expected)", t);
        }
    }

    static String processName() {
        FileInputStream in = null;
        try {
            in = new FileInputStream("/proc/self/cmdline");
            byte[] b = new byte[64];
            int n = in.read(b);
            int end = 0;
            while (end < n && b[end] != 0) end++;
            return new String(b, 0, end, "UTF-8");
        } catch (Throwable t) {
            return "";
        } finally {
            if (in != null) try { in.close(); } catch (Throwable t) { /* closed */ }
        }
    }
}
