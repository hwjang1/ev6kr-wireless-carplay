package hmgapi.mods.wireless;

/**
 * The cluster's CarPlay song line (SystemHooks): "artist - title". No Android here, so the
 * host test (tests/clustertext-test.sh) runs it.
 */
final class ClusterText {
    private ClusterText() {}

    /** ClusterService.updateFilename cuts a title over 63 chars to 31: never make it longer than 63 */
    static final int MAX = 63;
    static final String SEPARATOR = " - ";

    /**
     * What the cluster shows for this title and artist. An empty title stays empty (it clears
     * the cluster); no artist, or a title that already starts with the artist, stays the title.
     */
    static String join(String artist, String title) {
        if (title == null || title.trim().isEmpty()) return title;
        if (artist == null) return title;
        String a = artist.trim();
        if (a.isEmpty() || title.startsWith(a)) return title;
        String s = a + SEPARATOR + title;
        return s.length() > MAX ? s.substring(0, MAX) : s;
    }

    /**
     * The title for the HUD when the car sends it a line (0.2.4): the car keeps the cluster's
     * last line as its last title and sends that to the HUD again when it restores the cluster
     * (ClusterLastInfo.restoreClusterInfo), with the artist beside it. lastJoin is the line made
     * last and the title it was made from; a line that is exactly it goes back to that title.
     * Anything else (another song, a title that only looks like one) is left as it is: null.
     */
    static String hudTitle(String[] lastJoin, String line) {
        if (lastJoin == null || line == null || !line.equals(lastJoin[0])) return null;
        return lastJoin[1];
    }
}
