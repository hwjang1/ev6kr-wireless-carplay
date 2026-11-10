package hmgapi.mods.wireless.dipo;

import android.content.Context;
import android.content.Intent;

import java.lang.reflect.Method;

import hmgapi.hook.MethodHook;

/**
 * EV6 KR (mod 0.2.1): the steering wheel's call and voice buttons, and CarPlay music after the
 * car is switched off and on, in DiPO. Each is a setting, applied at the next restart. DiPO
 * is HKMC_DiPO 260902 (md5 caf67d3b): these hooks are on its own (obfuscated) methods, found
 * by name and signature; a method that isn't there turns only that part off, with a log line.
 *
 * Call button (call_key_phone): DiPO's call key handler (DipoService's static a(svc, action,
 * flags), "onKeyForService() performPhoneKey Call Key") sends HookSwitch with no call, or, when
 * the CarPlay screen isn't up, shows a "no call" notice. With no call, a short press opens
 * CarPlay's Phone app instead: DipoActivity with CarPlayMode 2, as DiPO's own phone display
 * (updateDisplay mode 2: takes the screen, then requestUI("mobilephone:")). Only while the
 * call state updates run (Bridge.sCallState): without them DiPO can't tell a ringing call
 * from no call. Calls (ringing, active, held, dialing) and long presses stay DiPO's.
 *
 * Voice button (siri_key): with CarPlay connected and neither Siri nor the car's voice
 * recognition running, system_server sends the voice button to both (SEND_PTT_TO_VR_CARPLAYSIRI):
 * a short press is the car's voice recognition, and DiPO only prewarms Siri; Siri starts on a
 * long press. SystemHooks sends it to DiPO only; here DiPO's voice key handler (private
 * l(action, flags)) sends Siri's ButtonDown at the press and ButtonUp at the release, so a
 * short press opens Siri (it stays open), and a hold is push-to-talk as before. Not during a
 * CarPlay call (DiPO ignores the button then, before this handler).
 *
 * CarPlay music after a restart (audio_resume): at ACC off DiPO borrows the main audio
 * (borrow id ACC_OFF_DELAYD_MODE), and that change of owner saves "the last audio wasn't
 * CarPlay" (setCpAudioLastMode false, DipoService.C(false)). At the next connection DiPO then
 * lets the iPhone take the audio only when the user starts playback (UserInitiated), so the
 * music doesn't come back by itself (EV6 KR, 2026-11-10 18:48:11). A false while the car is
 * at ACC off (MicomPowerManager power status DELAYMODE 6, PRESYSTEMOFF 7, OFF 0xff) is not
 * saved. Switching to another source with the car on still saves it.
 */
final class CarKeys {
    private CarKeys() {}

    static final String DIPO_SERVICE = "com.daudio.app.dipo.service.DipoService";
    static final String DIPO_ACTIVITY = "com.daudio.app.dipo.ui.DipoActivity";
    static final String SIRI_ACTION = "com.daudio.app.dipo.telechips.CarPlaySiriAction";
    static final int ACTION_DOWN = 0, ACTION_UP = 1;
    static final int FLAG_CANCELED = 0x20, FLAG_LONG_PRESS = 0x80, FLAG_CANCELED_LONG_PRESS = 0x100;
    /** DipoActivity's CarPlayMode extra: 2 is the phone (DiPO's updateDisplay) */
    static final int CARPLAY_MODE_PHONE = 2;
    /** MicomPowerConstants.AccStatus: the car going off */
    static final int ACC_DELAYMODE = 6, ACC_PRESYSTEMOFF = 7, ACC_OFF = 0xff;

    static ClassLoader cl;
    static Context context;
    private static Method sCo, sFx, sCallers, sSize, sSiri;
    private static Object sSiriDown, sSiriUp;
    /** the call key press now: a long press was seen (DiPO's own hK) */
    private static volatile boolean sCallLong;
    /** the voice key press now is ours (we sent Siri's ButtonDown) */
    private static volatile boolean sSiriOwn;
    private static Object sPower;
    private static Method sPowerStatus;

    static void start(ClassLoader loader, Context c, boolean callKey, boolean siriKey, boolean audioResume) {
        cl = loader;
        context = c;
        Class<?> svc;
        try {
            svc = cl.loadClass(DIPO_SERVICE);
        } catch (Throwable t) {
            Dipo.error("keys: no DipoService", t);
            return;
        }
        if (callKey) callKey(svc);
        if (siriKey) siriKey(svc);
        if (audioResume) audioResume(svc);
    }

    // ---- call button

    private static void callKey(final Class<?> svc) {
        try {
            sCo = svc.getDeclaredMethod("co");   // isCPCalling
            sFx = svc.getDeclaredMethod("fX");   // a telematics (TMU) call
            sCallers = svc.getDeclaredMethod("fR");   // its caller list (i/c)
            sCo.setAccessible(true);
            sFx.setAccessible(true);
            sCallers.setAccessible(true);
            sSize = sCallers.getReturnType().getDeclaredMethod("size");
            sSize.setAccessible(true);
            hmgapi.hook.Hooks.findAndHookMethod(svc, "a", svc, int.class, int.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!Dipo.mod.enabled()) return;   // the mod turned off: DiPO as stock
                    if (onCallKey(p.args[0], (Integer) p.args[1], (Integer) p.args[2])) p.setResult(null);
                }
            });
            Dipo.log("keys: call button opens CarPlay Phone when there's no call");
        } catch (Throwable t) {
            Dipo.error("keys: call button hook (DiPO's call key handler not found)", t);
        }
    }

    /** true: the press is handled here (DiPO's handler is skipped) */
    static boolean onCallKey(Object svc, int action, int flags) {
        try {
            if (action == ACTION_DOWN) {
                sCallLong = (flags & FLAG_LONG_PRESS) != 0;
                return false;
            }
            if (action != ACTION_UP) return false;
            boolean longPress = sCallLong || (flags & (FLAG_LONG_PRESS | FLAG_CANCELED_LONG_PRESS)) != 0;
            sCallLong = false;
            if ((flags & FLAG_CANCELED) != 0 || longPress) return false;
            if (!Bridge.sCpWireless || !Bridge.sCallState) {
                Dipo.log("keys: call button: DiPO's (" + (!Bridge.sCpWireless ? "no wireless CarPlay" : "no call state updates") + ")");
                return false;
            }
            boolean calling = Boolean.TRUE.equals(sCo.invoke(svc));
            boolean tmu = Boolean.TRUE.equals(sFx.invoke(svc));
            Object callers = sCallers.invoke(svc);
            int n = callers == null ? -1 : (Integer) sSize.invoke(callers);
            if (calling || tmu || n != 0) {
                Dipo.log("keys: call button: DiPO's (call: carplay " + calling + ", tmu " + tmu + ", callers " + n + ")");
                return false;
            }
            Intent i = new Intent();
            i.setClassName(context.getPackageName(), DIPO_ACTIVITY);
            i.putExtra("CarPlayMode", CARPLAY_MODE_PHONE);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
            Dipo.log("keys: call button with no call: CarPlay Phone");
            return true;
        } catch (Throwable t) {
            Dipo.error("keys: call button", t);
            return false;
        }
    }

    // ---- voice button

    private static void siriKey(final Class<?> svc) {
        try {
            Class<?> action = cl.loadClass(SIRI_ACTION);
            sSiri = svc.getDeclaredMethod("requestSiriAction", action);
            sSiri.setAccessible(true);
            sSiriDown = enumValue(action, "ButtonDown");
            sSiriUp = enumValue(action, "ButtonUp");
            hmgapi.hook.Hooks.findAndHookMethod(svc, "l", int.class, int.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!Dipo.mod.enabled()) return;   // the mod turned off: DiPO as stock
                    if (onVoiceKey(p.thisObject, (Integer) p.args[0], (Integer) p.args[1])) p.setResult(null);
                }
            });
            Dipo.log("keys: voice button opens Siri with a short press while CarPlay is connected");
        } catch (Throwable t) {
            Dipo.error("keys: voice button hook (DiPO's voice key handler not found)", t);
        }
    }

    @SuppressWarnings({ "unchecked", "rawtypes" })
    private static Object enumValue(Class<?> c, String name) {
        return Enum.valueOf((Class) c, name);
    }

    /** true: the press is handled here (DiPO's handler is skipped) */
    static boolean onVoiceKey(Object svc, int action, int flags) {
        try {
            if (!Bridge.sCpWireless) return false;
            if (action == ACTION_DOWN) {
                if (sSiriOwn) return true;   // the same press held: its long press is ours too
                if ((flags & FLAG_LONG_PRESS) != 0) return false;   // a press that started before
                sSiriOwn = true;
                sSiri.invoke(svc, sSiriDown);
                Dipo.log("keys: voice button: Siri (button down)");
                return true;
            }
            if (action == ACTION_UP && sSiriOwn) {
                sSiriOwn = false;
                sSiri.invoke(svc, sSiriUp);
                return true;
            }
            return false;
        } catch (Throwable t) {
            sSiriOwn = false;
            Dipo.error("keys: voice button", t);
            return false;
        }
    }

    // ---- CarPlay music after a restart

    private static void audioResume(final Class<?> svc) {
        try {
            hmgapi.hook.Hooks.findAndHookMethod(svc, "C", boolean.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    if (!Dipo.mod.enabled()) return;   // the mod turned off: DiPO as stock
                    if (Boolean.FALSE.equals(p.args[0]) && carGoingOff()) {
                        p.setResult(null);
                        Dipo.log("keys: CarPlay audio given up at ACC off: kept as the last audio (music comes back at the next connection)");
                    }
                }
            });
            Dipo.log("keys: CarPlay audio stays the last audio through ACC off");
        } catch (Throwable t) {
            Dipo.error("keys: CarPlay audio last mode hook (DiPO's setCpAudioLastMode not found)", t);
        }
    }

    /** the car is at ACC off (DiPO's own power status listener got DELAYMODE before it borrows the audio) */
    static boolean carGoingOff() {
        int s = powerStatus();
        return s == ACC_DELAYMODE || s == ACC_PRESYSTEMOFF || s == ACC_OFF;
    }

    static synchronized int powerStatus() {
        try {
            if (sPower == null) {
                Class<?> m = Class.forName("com.hkmc.power.MicomPowerManager");
                sPower = m.getConstructor(Context.class).newInstance(context);
                sPowerStatus = m.getMethod("getPowerStatus");
            }
            return (Integer) sPowerStatus.invoke(sPower);
        } catch (Throwable t) {
            Dipo.error("keys: power status", t);
            return -1;
        }
    }
}
