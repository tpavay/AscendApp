import Foundation

@MainActor
final class LiveClimbSessionCoordinator {
    static let shared = LiveClimbSessionCoordinator()

    private var activeViewModel: LiveClimbSessionViewModel?

    private init() {}

    func setActive(_ viewModel: LiveClimbSessionViewModel) {
        activeViewModel = viewModel
    }

    func activeViewModel(sessionID: String) -> LiveClimbSessionViewModel? {
        guard activeViewModel?.liveActivitySessionID == sessionID else {
            return nil
        }

        return activeViewModel
    }

    func clearIfActive(sessionID: String) {
        guard activeViewModel?.liveActivitySessionID == sessionID else { return }
        activeViewModel = nil
    }
}
