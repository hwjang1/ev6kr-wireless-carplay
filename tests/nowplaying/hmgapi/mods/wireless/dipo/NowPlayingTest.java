package hmgapi.mods.wireless.dipo;

/** Host test of NowPlaying (from Korea Projection's HMG-API fork, StopDragon/HMG-API commit 577434c, AGPL-3.0): what DiPO's listener sees on a wireless CarPlay connect, and the server's answers. */
public final class NowPlayingTest {
    static int fail;

    static void check(String what, Object want, Object got) {
        if (want == null ? got == null : want.equals(got)) {
            System.out.println("ok    " + what);
        } else {
            System.out.println("FAIL  " + what + ": wanted [" + want + "], got [" + got + "]");
            fail = 1;
        }
    }

    /** a server that answers from a list (true, false, or throws for null) and counts its calls */
    static final class Fake implements NowPlaying.Server {
        final Boolean[] answers;
        int calls;

        Fake(Boolean... answers) {
            this.answers = answers;
        }

        @Override
        public boolean start() throws Exception {
            Boolean a = answers[Math.min(calls, answers.length - 1)];
            calls++;
            if (a == null) throw new java.io.IOException("binder died");
            return a;
        }
    }

    public static void main(String[] args) {
        final int ID = NowPlaying.IDENTIFICATION_ACCEPTED, TRANSPORT_ID = 24;

        NowPlaying n = new NowPlaying();
        check("setting off: no start", false, n.due(false, true, ID));
        check("USB (no CarPlay channel): no start", false, n.due(true, false, ID));
        check("other notification: no start", false, n.due(true, true, TRANSPORT_ID));
        check("channel identification: start", true, n.due(true, true, ID));
        check("same session again: no second start", false, n.due(true, true, ID));

        int s = n.session();
        Fake ok = new Fake(true);
        check("server takes it on the first try", "NowPlaying started for the CarPlay-channel session (try 1)", n.attempt(s, 1, true, ok));
        check("one call to the server", 1, ok.calls);

        n.reset();
        check("new session: start again", true, n.due(true, true, ID));
        int s2 = n.session();
        check("a try left from the old session does nothing", "", n.attempt(s, 1, true, ok));
        check("no call for the old session", 1, ok.calls);
        check("channel gone before the try: nothing", "", n.attempt(s2, 1, false, ok));
        check("no call without the channel", 1, ok.calls);

        Fake late = new Fake(false, false, true);
        check("refused (no session yet): try again", null, n.attempt(s2, 1, true, late));
        check("refused twice: try again", null, n.attempt(s2, 2, true, late));
        check("third try works", "NowPlaying started for the CarPlay-channel session (try 3)", n.attempt(s2, 3, true, late));
        check("still once for this session", false, n.due(true, true, ID));

        n.reset();
        n.due(true, true, ID);
        int s3 = n.session();
        Fake dead = new Fake(new Boolean[] { null });
        check("binder error: try again", null, n.attempt(s3, 1, true, dead));
        check("binder error: try again (2)", null, n.attempt(s3, 2, true, dead));
        check("binder error, last try: gives up with the reason", "NowPlaying not started (failed: java.io.IOException: binder died, 3 tries)", n.attempt(s3, 3, true, dead));
        check("after giving up: the next identification may start it", true, n.due(true, true, ID));

        n.reset();
        n.due(true, true, ID);
        int s4 = n.session();
        Fake never = new Fake(false);
        n.attempt(s4, 1, true, never);
        n.attempt(s4, 2, true, never);
        n.reset();
        check("gave up after the session changed: new session's state kept", "", n.attempt(s4, 3, true, never));
        check("new session starts normally", true, n.due(true, true, ID));

        n.reset();
        n.due(true, true, ID);
        int s5 = n.session();
        NowPlaying.Server missing = new NowPlaying.Server() {
            @Override
            public boolean start() {
                throw new NoSuchMethodError("Iap2SvcNowPlayingStart");
            }
        };
        n.attempt(s5, 1, true, missing);
        n.attempt(s5, 2, true, missing);
        check("server without the method (NoSuchMethodError): caught, gives up with the reason",
                "NowPlaying not started (failed: java.lang.NoSuchMethodError: Iap2SvcNowPlayingStart, 3 tries)", n.attempt(s5, 3, true, missing));

        System.out.println(fail == 0 ? "all NowPlaying tests passed" : "NowPlaying tests FAILED");
        System.exit(fail);
    }
}
