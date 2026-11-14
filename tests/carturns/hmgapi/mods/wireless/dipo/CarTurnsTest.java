package hmgapi.mods.wireless.dipo;

/** Host test of CarTurns: CarPlay's turns in the car's own format (setting tbt_standard). */
public final class CarTurnsTest {
    static int failed;

    static void check(String what, int[] want, int[] got) {
        boolean ok = java.util.Arrays.equals(want, got);
        System.out.println((ok ? "ok   " : "FAIL ") + what + (ok ? "" : ": want " + java.util.Arrays.toString(want)
                + " got " + java.util.Arrays.toString(got)));
        if (!ok) failed++;
    }

    static void check(String what, int want, int got) {
        check(what, new int[] { want }, new int[] { got });
    }

    static int[] t(int type, int dir, int bar) {
        return new int[] { type, dir, bar };
    }

    public static void main(String[] a) {
        // ManeuverType, side, junction, exit, icon (CpTurns.icon), meters
        check("right turn far away: the icon, no bar", t(67, 0, 0), CarTurns.standard(2, 0, 0, 0, 67, 900));
        check("right turn at the window's edge: TURN 90, bar 90", t(13, 90, 90), CarTurns.standard(2, 0, 0, 0, 67, 457));
        check("just past the edge: still the icon", t(67, 0, 0), CarTurns.standard(2, 0, 0, 0, 67, 458));
        check("left turn at 300 m: TURN 270, bar 60", t(13, 270, 60), CarTurns.standard(1, 0, 0, 0, 70, 300));
        check("left turn at 5 m: bar 10 at least", t(13, 270, 10), CarTurns.standard(1, 0, 0, 0, 70, 5));
        check("left turn at 0 m: bar 10", t(13, 270, 10), CarTurns.standard(1, 0, 0, 0, 70, 0));
        check("unknown distance: the icon", t(70, 0, 0), CarTurns.standard(1, 0, 0, 0, 70, -1));
        check("straight (T map's type 3): TURN 0", t(13, 0, 40), CarTurns.standard(3, 0, 0, 0, 65, 200));
        check("left with exit -60: slight, 315", t(13, 315, 40), CarTurns.standard(1, 0, 0, -60, 71, 200));
        check("left with exit -120: sharp, 225", t(13, 225, 40), CarTurns.standard(1, 0, 0, -120, 69, 200));
        check("right with exit 120: sharp, 135", t(13, 135, 40), CarTurns.standard(2, 0, 0, 120, 68, 200));
        check("right with exit 45: slight, 45", t(13, 45, 40), CarTurns.standard(2, 0, 0, 45, 144, 200));
        check("left turn at the end of the road", t(13, 270, 40), CarTurns.standard(20, 0, 0, 0, 70, 200));
        check("slight left (49)", t(13, 315, 40), CarTurns.standard(49, 0, 0, 0, 71, 200));
        check("slight right (50)", t(13, 45, 40), CarTurns.standard(50, 0, 0, 0, 66, 200));
        check("sharp left (47)", t(13, 225, 40), CarTurns.standard(47, 0, 0, 0, 69, 200));
        check("sharp right (48)", t(13, 135, 40), CarTurns.standard(48, 0, 0, 0, 68, 200));
        check("U-turn, right-hand traffic: 270", t(31, 270, 40), CarTurns.standard(4, 0, 0, 0, 72, 200));
        check("U-turn, left-hand traffic: 90", t(31, 90, 40), CarTurns.standard(4, 1, 0, 0, 73, 200));
        check("keep left (13): fork 270", t(25, 270, 40), CarTurns.standard(13, 0, 0, 0, 174, 200));
        check("keep right (14): fork 90", t(25, 90, 40), CarTurns.standard(14, 0, 0, 0, 173, 200));
        check("change highway right (53): fork 90", t(25, 90, 40), CarTurns.standard(53, 0, 0, 0, 173, 200));
        check("highway off-ramp right (23): EXIT_RIGHT", t(17, 90, 40), CarTurns.standard(23, 0, 0, 0, 81, 200));
        check("highway off-ramp left (22): EXIT_LEFT", t(18, 270, 40), CarTurns.standard(22, 0, 0, 0, 82, 200));
        check("off-ramp with no side: the icon, with the bar", t(86, 0, 40), CarTurns.standard(8, 0, 0, 0, 86, 200));
        check("roundabout exit icon 99: TRS_RIGHT, 90", t(32, 90, 40), CarTurns.standard(29, 0, 1, 90, 99, 200));
        check("roundabout exit icon 104: TRS_RIGHT, 225", t(32, 225, 40), CarTurns.standard(32, 0, 1, -45, 104, 200));
        check("roundabout, left-hand traffic: TRS_LEFT", t(33, 270, 40), CarTurns.standard(1, 1, 1, -90, 105, 200));
        check("destination far: its icon", t(112, 0, 0), CarTurns.standard(12, 0, 0, 0, 112, 300));
        check("destination on the right near: its icon, no bar", t(113, 0, 0), CarTurns.standard(25, 0, 0, 0, 113, 100));
        check("destination within 20 m: ARRIVED", t(3, 0, 0), CarTurns.standard(12, 0, 0, 0, 112, 15));
        check("arrived (state 2): ARRIVED", t(3, 0, 0), CarTurns.standard(12, 0, 0, 0, 3, -1));
        check("departure (icon 1): left alone, no bar", t(1, 0, 0), CarTurns.standard(11, 0, 0, 0, 1, 200));
        check("bar at 457 m", 90, CarTurns.bar(457));
        check("bar at 229 m", 50, CarTurns.bar(229));
        check("bar at 46 m", 10, CarTurns.bar(46));
        check("turnDir: exit pointing the wrong way keeps the plain turn", 90, CarTurns.turnDir(-90, true));
        check("turnDir: -90 left", 270, CarTurns.turnDir(-90, false));
        check("roundaboutDir: clockwise set 195 (99 + 96)", 90, CarTurns.roundaboutDir(195));
        check("roundaboutDir: 103 isn't one of the car's", -1, CarTurns.roundaboutDir(103));
        check("roundaboutDir: a turn icon", -1, CarTurns.roundaboutDir(67));
        if (failed > 0) {
            System.out.println(failed + " failed");
            System.exit(1);
        }
        System.out.println("all CarTurns tests passed");
    }
}
