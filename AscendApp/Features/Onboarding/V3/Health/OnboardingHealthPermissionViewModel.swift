import Foundation
import Observation

/// 06b's one action. "GOT IT" asks for Health access through the Connect flow's own view model, then
/// reads what Health holds and says where onboarding goes next.
///
/// Whatever the request comes to, onboarding moves on. 06 and 06b have no Skip (Guideline 5.1.1(iv)),
/// so a refusal or a failed request cannot be left standing as a screen with nothing else to press:
/// the climber's no is the iOS sheet's Don't Allow, and a request that could not be made at all
/// (Health unavailable, an error) is the same answer with a different id. Either way the climber
/// goes on to the usual-climb question, and connecting waits in Settings.
///
/// Nothing is written. There is no account yet, so the climber's answer to the iOS sheet is the
/// only thing that changes, and what the read finds is carried to the next screen by that screen
/// reading it again.
@MainActor
@Observable
final class OnboardingHealthPermissionViewModel {
    @ObservationIgnored private let connect: AppleHealthConnectViewModel
    @ObservationIgnored private let reader: any HealthWorkoutReading
    private var isReading = false

    init(
        connect: AppleHealthConnectViewModel = AppleHealthConnectViewModel(),
        reader: any HealthWorkoutReading = HealthKitWorkoutReader.shared
    ) {
        self.connect = connect
        self.reader = reader
    }

    var isWorking: Bool { connect.isWorking || isReading }

    /// Asks for access, reads Health, and moves the flow on: to "We found your climbs" when there are
    /// workouts, to the usual-climb question when there are none or when the request itself failed.
    func gotIt(coordinator: OnboardingV3Coordinator) async {
        guard !isWorking else { return }
        guard await connect.requestAccessOnly() else {
            // The request could not be made, which is not a screen the climber can stay on: the only
            // way off it would be Back, and nothing on 06 leads anywhere but here.
            report("request_failed", coordinator: coordinator)
            guard coordinator.step == .healthPermission else { return }
            leaveHealthBehind(coordinator)
            return
        }

        isReading = true
        let hasHistory = (try? await HealthHistory.exists(using: reader)) == true
        isReading = false

        // The climber could have backed out while the sheet was up; the answer then belongs to a
        // screen that is gone.
        guard coordinator.step == .healthPermission else { return }

        report(hasHistory ? "history_found" : "none_found", coordinator: coordinator)
        if hasHistory {
            coordinator.advance()
        } else {
            // None found, or a read that failed - never reported as a history. A climber with
            // nothing to find loses nothing by the question, and nothing they were shown earlier
            // is left behind to be imported.
            coordinator.update { $0.clearFoundHealthHistory() }
            coordinator.go(to: .usualClimb)
        }
    }

    /// On to the usual-climb question with nothing carried from Health, reporting a plain continue:
    /// the climber did not decline a workout search, the request never completed.
    private func leaveHealthBehind(_ coordinator: OnboardingV3Coordinator) {
        coordinator.update { $0.clearFoundHealthHistory() }
        coordinator.go(to: .usualClimb, as: .continue)
    }

    /// What the sheet and the read came to. HealthKit never says whether a read type was allowed, so
    /// the ids name what Ascend can see: the request itself failed or was refused (`request_failed`),
    /// or it completed and the read then found workouts (`history_found`) or none (`none_found`).
    private func report(_ answerID: String, coordinator: OnboardingV3Coordinator) {
        coordinator.report(.questionAnswered(
            context: coordinator.analyticsContext,
            questionID: "health_permission",
            inputType: "button",
            selectionType: "single_select",
            answerID: answerID,
            answerIndex: nil,
            properties: [:]
        ))
    }
}
