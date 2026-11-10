package hmgapi.mods.wireless;

/** Host test of ClusterText: what the cluster shows for a CarPlay song. */
public final class ClusterTextTest {
    static int failed;

    static void check(String what, String want, String got) {
        boolean ok = want == null ? got == null : want.equals(got);
        System.out.println((ok ? "ok   " : "FAIL ") + what + (ok ? "" : ": want [" + want + "] got [" + got + "]"));
        if (!ok) failed++;
    }

    public static void main(String[] a) {
        check("artist and title", "김형중 - 그녀가 웃잖아", ClusterText.join("김형중", "그녀가 웃잖아"));
        check("artist trimmed", "IU - Love wins all", ClusterText.join("  IU ", "Love wins all"));
        check("no artist: the title", "Title", ClusterText.join(null, "Title"));
        check("empty artist: the title", "Title", ClusterText.join("  ", "Title"));
        check("empty title stays empty (it clears the cluster)", "", ClusterText.join("Artist", ""));
        check("null title stays null", null, ClusterText.join("Artist", null));
        check("title already has the artist", "Artist - Song", ClusterText.join("Artist", "Artist - Song"));
        StringBuilder t = new StringBuilder();
        for (int i = 0; i < 70; i++) t.append('x');
        String long1 = ClusterText.join("Band", t.toString());
        check("long: cut at 63 (the service would cut it to 31)", "Band - " + t.substring(0, 56), long1);
        check("long: 63 chars", "63", String.valueOf(long1.length()));
        if (failed > 0) {
            System.out.println(failed + " failed");
            System.exit(1);
        }
        System.out.println("all ClusterText tests passed");
    }
}
