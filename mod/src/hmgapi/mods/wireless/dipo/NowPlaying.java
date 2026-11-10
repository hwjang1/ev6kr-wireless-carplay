package hmgapi.mods.wireless.dipo;

/**
 * Song info for wireless CarPlay.
 *
 * From Korea Projection's HMG-API fork (github.com/StopDragon/HMG-API, branch korea-build,
 * commit 577434c, AGPL-3.0). Changed here: a name for the log lines, so the same start logic
 * also starts the phone's call state updates (mod 0.2.1, Bridge.CALL_STATE).
 *
 * DiPO starts the phone's NowPlaying updates (and its telephony ones) only for a USB
 * session: its setStartiAP2Service skips them when the transport is wireless (stock
 * HKMC_DiPO, the "[USB]" branch; on this EV6 it logs "setStartiAP2Service transportType[1]"
 * and DipoService then gets no title or artist). So on wireless the cluster, the media
 * widget and the split screen get no title, artist or album art.
 *
 * The mod starts NowPlaying itself, once per CarPlay-channel session, right after that
 * session's identification is accepted (the notification the bridge hides from DiPO).
 * The iAP2 server works on its current session's handle (as for route guidance) and sends
 * the updates to every listener that takes them, DiPO's included. No stop: the server's
 * handle goes with the session, and DiPO's own stop is skipped on wireless too.
 * Call state (mod 0.2.1, setting call_state): the same way, a second instance starts the
 * phone's call state updates, which DiPO's call button handling needs (see Bridge).
 *
 * The state is kept here, apart from Bridge, so the host test needs no Android.
 */
final class NowPlaying {
    /** iAP2 notification: identification accepted (Bridge.NOTI_IDENTIFICATION_ACCEPTED) */
    static final int IDENTIFICATION_ACCEPTED = 0;
    /** after the identification, before the call: the session's own start messages go first */
    static final long DELAY_MS = 500;
    /** a refused or failed start is tried again this many times, DELAY_MS apart */
    static final int TRIES = 3;

    interface Server {
        /** Iap2SvcNowPlayingStart: false when the server has no session (yet) */
        boolean start() throws Exception;
    }

    private boolean started;
    private int session;
    /** what the log lines call it */
    final String name;

    NowPlaying() {
        this("NowPlaying");
    }

    NowPlaying(String name) {
        this.name = name;
    }

    /**
     * DiPO's listener got notification what. True (once per channel session) when the mod
     * should start NowPlaying now: the setting is on, the bridge's CarPlay channel is up and
     * this is its identification.
     */
    synchronized boolean due(boolean on, boolean cpClient, int what) {
        if (!on || !cpClient || what != IDENTIFICATION_ACCEPTED || started) return false;
        started = true;
        return true;
    }

    /** the channel session ended or a new one starts: the next identification starts it again */
    synchronized void reset() {
        started = false;
        session++;
    }

    /** the current session's number: a delayed try for an older session does nothing */
    synchronized int session() {
        return session;
    }

    synchronized boolean current(int s) {
        return started && s == session;
    }

    /**
     * One try. Returns the log line, or null to try again later (refused or failed, tries
     * left). A stale try (the session ended meanwhile) returns "" and does nothing.
     */
    String attempt(int s, int tryNo, boolean cpClient, Server server) {
        if (!cpClient || !current(s)) return "";
        String why;
        try {
            if (server.start()) return name + " started for the CarPlay-channel session (try " + tryNo + ")";
            why = "refused";
        } catch (Throwable t) {
            why = "failed: " + t;
        }
        if (tryNo < TRIES) return null;
        synchronized (this) {
            // the next identification of this session (if any) may start it again
            if (s == session) started = false;
        }
        return name + " not started (" + why + ", " + TRIES + " tries)";
    }
}
