import CoreGraphics

/// What moves on the selling screens, decided apart from the views so Reduce Motion is a tested
/// rule rather than a branch someone has to remember: it keeps every fade and drops every zoom,
/// bob, tilt and fall.
enum SellMotion {
    /// The welcome photo starts 15 percent large and settles to 1 over six seconds.
    static func heroStartScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 1.15
    }

    /// How far a piece of gear rises on each bob; zero holds it still.
    static func gearBobDistance(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : 10
    }

    /// A record card's tilt in degrees; Reduce Motion lays it flat.
    static func cardTilt(_ degrees: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : degrees
    }

    /// The phone on 02 rises 40 pt into place; Reduce Motion fades it where it stands.
    static func phoneRise(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : 40
    }
}
