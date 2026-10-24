import Foundation

/// The running routine session, held by the process so a screen can find it again.
///
/// The Live Climb twin is `LiveClimbSessionCoordinator`. A routine's view model used to live only
/// in `ActiveRoutineView`'s state, so a session resumed with no screen - the HealthKit relaunch
/// in the background - had nowhere to live and a screen that came up later had nothing to adopt.
@MainActor
final class ActiveRoutineSessionCoordinator {
    static let shared = ActiveRoutineSessionCoordinator()

    private var activeViewModel: ActiveRoutineViewModel?
    private var activeSessionID: String?

    private init() {}

    func setActive(_ viewModel: ActiveRoutineViewModel, sessionID: String) {
        activeViewModel = viewModel
        activeSessionID = sessionID
    }

    func activeViewModel(sessionID: String) -> ActiveRoutineViewModel? {
        guard activeSessionID == sessionID else { return nil }
        return activeViewModel
    }

    var hasActiveSession: Bool {
        activeViewModel != nil
    }

    func clearIfActive(sessionID: String) {
        guard activeSessionID == sessionID else { return }
        activeViewModel = nil
        activeSessionID = nil
    }
}
