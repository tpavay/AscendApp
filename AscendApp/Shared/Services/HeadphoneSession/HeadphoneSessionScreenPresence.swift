import Foundation

/// Which session screens are on screen right now, for every mode.
///
/// A session can be alive with no screen showing it - its tab was switched away, the app was
/// relaunched in the background by HealthKit, the Live Activity tap landed on a stale route - and
/// the only honest test for "does the climber see their climb" is whether its screen registered.
/// `MainTabView` reads this to decide whether a draft needs re-presenting; the in-memory
/// registries only say a session exists.
@MainActor
final class HeadphoneSessionScreenPresence {
    static let shared = HeadphoneSessionScreenPresence()

    private var onScreen: [String: Set<UUID>] = [:]

    init() {}

    func didAppear(sessionID: String, token: UUID) {
        onScreen[sessionID, default: []].insert(token)
    }

    func didDisappear(sessionID: String, token: UUID) {
        onScreen[sessionID]?.remove(token)
        if onScreen[sessionID]?.isEmpty == true {
            onScreen[sessionID] = nil
        }
    }

    func isOnScreen(sessionID: String) -> Bool {
        !(onScreen[sessionID]?.isEmpty ?? true)
    }
}
