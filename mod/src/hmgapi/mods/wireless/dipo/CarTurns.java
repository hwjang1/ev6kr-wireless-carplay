package hmgapi.mods.wireless.dipo;

/**
 * CarPlay's next turn in the car's own format, for the AR HUD (setting tbt_standard, off by
 * default). The AR HUD animates its arrow only for the car navigation's own main-display
 * types (Navigation.DisplayType), not for the projection icons (64 and up) CarPlay's turns
 * otherwise go out as. Near a maneuver the car's navigation sends its type with the
 * maneuver's angle in 45 degree steps and a distance bar; farther away the icon with the bar
 * off. Worked out on a US Ioniq 5 with the AR HUD by the Wireless mod's Android Auto turns
 * (Open-HMG/hmgapi-wireless-cp-aa, AaTurns.standard(), docs/ar-hud.md and
 * docs/cluster-turns.md); this is the same for CarPlay's iAP2 maneuvers. The values are the
 * same on the EV6 KR (260902, Navigation.DisplayType).
 * Pure functions, no Android: tests/carturns-test.sh runs them on a computer.
 */
final class CarTurns {
    /** Navigation.DisplayType */
    static final int TYPE_ARRIVED = 3, TYPE_TURN = 13, TYPE_EXIT_RIGHT = 17, TYPE_EXIT_LEFT = 18, TYPE_FORK = 25,
            TYPE_U_TURN = 31, TYPE_ROUNDABOUT_RIGHT = 32, TYPE_ROUNDABOUT_LEFT = 33;
    /** the destination icons (ahead, on the right, on the left): the car's navigation keeps them near too */
    static final int DEST_AHEAD = 112, DEST_RIGHT = 113, DEST_LEFT = 114;
    /** how far before a maneuver the car's navigation switches to its own types and starts the bar (m) */
    static final int GUIDE_WINDOW = 457;
    /** a destination this close is "arrived" (m) */
    static final int ARRIVED_WITHIN = 20;

    private CarTurns() {
    }

    /**
     * {type, direction, bar} for the main display (updateTBTInfo). type, side, junction, exit:
     * the iAP2 maneuver (ManeuverType, driving side 0 right-hand traffic / 1 left, junction 0
     * intersection / 1 roundabout, exit angle in degrees, right positive, 0 when absent);
     * icon: its projection icon (CpTurns.icon); meters: the distance to it (-1 unknown).
     * Outside the window, or for a maneuver with no car type: the icon (with the bar inside it).
     */
    static int[] standard(int type, int side, int junction, int exit, int icon, int meters) {
        if (icon < 64) return new int[] { icon, 0, 0 };   // ARRIVED (state 2), departure's NO_INFO
        if (icon == DEST_AHEAD || icon == DEST_RIGHT || icon == DEST_LEFT) {
            if (meters >= 0 && meters < ARRIVED_WITHIN) return new int[] { TYPE_ARRIVED, 0, 0 };
            return new int[] { icon, 0, 0 };
        }
        if (meters < 0 || meters > GUIDE_WINDOW) return new int[] { icon, 0, 0 };
        int bar = bar(meters);
        // a roundabout exit (the icons 96-107): its exit's direction. 32 draws a counterclockwise
        // roundabout (right-hand traffic), 33 a clockwise one
        int r = roundaboutDir(icon);
        if (r >= 0) return new int[] { side == 1 ? TYPE_ROUNDABOUT_LEFT : TYPE_ROUNDABOUT_RIGHT, r, bar };
        switch (type) {
            case 3:                // straight ahead
                return new int[] { TYPE_TURN, 0, bar };
            case 1: case 20:       // left turn, left turn at the end of the road
                return new int[] { TYPE_TURN, turnDir(exit, false), bar };
            case 2: case 21:       // right turn, right turn at the end of the road
                return new int[] { TYPE_TURN, turnDir(exit, true), bar };
            case 49:               // slight left / right
                return new int[] { TYPE_TURN, 315, bar };
            case 50:
                return new int[] { TYPE_TURN, 45, bar };
            case 47:               // sharp left / right
                return new int[] { TYPE_TURN, 225, bar };
            case 48:
                return new int[] { TYPE_TURN, 135, bar };
            case 4: case 26:       // U-turn, U-turn when possible: toward the middle of the road
                return new int[] { TYPE_U_TURN, side == 1 ? 90 : 270, bar };
            case 13: case 52:      // keep left, change highway left: a fork
                return new int[] { TYPE_FORK, 270, bar };
            case 14: case 53:      // keep right, change highway right
                return new int[] { TYPE_FORK, 90, bar };
            case 22:               // highway off-ramp left / right
                return new int[] { TYPE_EXIT_LEFT, 270, bar };
            case 23:
                return new int[] { TYPE_EXIT_RIGHT, 90, bar };
            default:               // off-ramps without a side, on-ramps, ferries: the icon, with the bar
                return new int[] { icon, 0, bar };
        }
    }

    /** the distance bar: (100 - progress) / 10 over the window, 1 at least, sent x10 (90 ... 10) */
    static int bar(int meters) {
        return Math.max(1, Math.min(9, meters * 10 / GUIDE_WINDOW)) * 10;
    }

    /**
     * A turn's direction from its exit angle, in 45 degree steps (right 45/90/135, left
     * 315/270/225); a plain right or left (90/270) when the angle is absent or points the
     * other way. T map sends no exit angle.
     */
    static int turnDir(int exit, boolean right) {
        int plain = right ? 90 : 270;
        if (exit == 0) return plain;
        int a = ((exit % 360) + 360) % 360;
        int d = ((a + 22) / 45) * 45 % 360;
        if (right) return d >= 45 && d <= 135 ? d : plain;
        return d >= 225 && d <= 315 ? d : plain;
    }

    /**
     * A roundabout exit icon's direction (the car's icons, one per 45 degrees: 96 straight on,
     * 97, 99, 100, 102, 104, 105, 107; 192-203 the clockwise set); -1 for any other icon.
     */
    static int roundaboutDir(int icon) {
        int i = icon >= 192 && icon <= 203 ? icon - 96 : icon;
        switch (i) {
            case 96: return 0;
            case 97: return 45;
            case 99: return 90;
            case 100: return 135;
            case 102: return 180;
            case 104: return 225;
            case 105: return 270;
            case 107: return 315;
            default: return -1;
        }
    }
}
