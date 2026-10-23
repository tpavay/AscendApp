import Foundation

/// What may stay mounted while a headphone session runs.
///
/// iOS reclaimed a backgrounded Live Climb a minute after the climber opened Instagram
/// (2026-10-23), and the process it reclaimed was carrying a MapKit globe nobody could see under
/// the pushed climb. A session is the one moment the app's footprint is a liability, so this names
/// the root views that keep their weight through one and the test pins the list.
enum ActiveSessionFootprintPolicy {
    /// Root views that stay mounted under an active session. Everything else that is heavy - the
    /// globe above all - stands down and is rebuilt when the session pops. A view joins this list
    /// by deliberate decision in a reviewed diff, never by default.
    static let rootViewsAllowedUnderActiveSession: Set<String> = [
        "HomeView",
        "GlobeEdgeOverlays",
        "ClimbCatalogStateOverlay",
        "MainTabBarView",
        "LiveClimbSessionView",
        "ActiveRoutineView",
        "ActiveHeadphoneWorkoutRecoveryView"
    ]

    /// Heavy root views that are unmounted for the length of a session.
    static let rootViewsUnmountedUnderActiveSession: Set<String> = [
        "GlobeView"
    ]

    static let unmountedGlobeIdentifier = "home.globe.unmounted"

    static func mountsGlobe(sessionIsActive: Bool) -> Bool {
        !sessionIsActive
    }
}
