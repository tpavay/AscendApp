import CoreGraphics
import CoreLocation
import Foundation

/// Shared camera framing for showing a climb's real-world landmark in 3D —
/// used by both the globe pin-tap focus and the standalone flyover so the
/// distance/pitch tuning stays consistent.
///
/// MapKit's camera looks at a *ground* coordinate, so a tall structure rises
/// above that point. To keep landmarks centered regardless of height we pull
/// the camera back as height grows AND lower the pitch (more top-down) so tall
/// towers sit on their footprint instead of shooting out the top of the frame.
enum ClimbCameraFraming {
    static func isNatural(_ climb: Climb) -> Bool {
        ["mountain", "volcano", "rock", "waterfall"].contains(climb.category.lowercased())
    }

    /// Distance scales with height so the whole structure fits in frame.
    static func distance(for climb: Climb) -> CLLocationDistance {
        let h = max(climb.referenceHeightMeters, 60)
        if isNatural(climb) {
            return min(max(h * 3.0, 9_000), 50_000)
        }
        return min(max(h * 4.5, 800), 6_500)
    }

    /// Pitch is degrees from straight down (0 = nadir, 90 = horizon). Short
    /// landmarks get a dramatic near-horizontal angle; tall ones get a more
    /// top-down angle so they stay centered.
    static func pitch(for climb: Climb) -> CGFloat {
        if isNatural(climb) { return 66 }
        let h = max(climb.referenceHeightMeters, 60)
        let t = min(max((h - 120) / (600 - 120), 0), 1) // 0 at ≤120m, 1 at ≥600m
        return 70 - t * 25 // 70° (short) → 45° (tall)
    }
}
