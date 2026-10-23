import Foundation

/// What stands down while a headphone session runs.
///
/// iOS reclaimed a backgrounded Live Climb a minute after the climber opened Instagram
/// (2026-10-23), and the process it reclaimed was carrying a MapKit globe nobody could see under
/// the pushed climb. A session is the one moment the app's footprint is a liability, so the globe
/// is unmounted for its length and rebuilt when it ends.
enum ActiveSessionFootprintPolicy {
    static let unmountedGlobeIdentifier = "home.globe.unmounted"

    static func mountsGlobe(sessionIsActive: Bool) -> Bool {
        !sessionIsActive
    }
}
