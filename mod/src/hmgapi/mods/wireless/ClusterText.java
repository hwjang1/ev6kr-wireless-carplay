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
}
