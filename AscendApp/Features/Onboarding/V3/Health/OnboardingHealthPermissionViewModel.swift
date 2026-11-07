import Foundation
import Observation

/// 06b's one action. "GOT IT" asks for Health access through the Connect flow's own view model, then
/// reads what Health holds and says where onboarding goes next.
///
/// Nothing is written. There is no account yet, so the climber's answer to the iOS sheet is the
/// only thing that changes, and what the read finds is carried to the next screen by that screen
/// reading it again.
@MainActor
@Observable
final class OnboardingHealthPermissionViewModel {
    @ObservationIgnored private let connect: AppleHealthConnectViewModel
    @ObservationIgnored private let reader: any HealthWorkoutReading
    @ObservationIgnored private let now: () -> Date
    private var isReading = false

    init(
        connect: AppleHealthConnectViewModel = AppleHealthConnectViewModel(),
        reader: any HealthWorkoutReading = HealthKitWorkoutReader.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.connect = connect
        self.reader = reader
        self.now = now
    }

    var isWorking: Bool { connect.isWorking || isReading }

    /// The iOS sheet's refusal, or nil. The climber taps again to retry.
    var errorMessage: String? { connect.errorMessage }

    /// Asks for access, reads Health, and moves the flow on: to "We found your climbs" when there are
    /// workouts, to the usual-climb question when there are none. A refusal from the iOS request moves
    /// nothing and leaves ``errorMessage`` for the climber to retry from.
    func gotIt(coordinator: OnboardingV3Coordinator) async {
        guard !isWorking else { return }
        guard await connect.requestAccessOnly() else { return }

        isReading = true
        let summary = try? await HealthHistorySummary.load(using: reader, now: now())
        isReading = false

        // The climber could have backed out while the sheet was up; the answer then belongs to a
        // screen that is gone.
        guard coordinator.step == .healthPermission else { return }

        if summary?.isEmpty == false {
            coordinator.advance()
        } else {
            // None found, or a read that failed - never reported as a history. A climber with
            // nothing to find loses nothing by the question, and nothing they were shown earlier
            // is left behind to be imported.
            coordinator.update { $0.clearFoundHealthHistory() }
            coordinator.go(to: .usualClimb)
        }
    }
}
