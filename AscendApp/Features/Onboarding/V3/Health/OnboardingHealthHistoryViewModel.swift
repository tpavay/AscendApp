import Foundation
import Observation

/// 07a's state: the read, what it found, the range the climber picked, and what each of the two
/// buttons carries forward.
///
/// Read-only. What it holds is a look at Health's own records; nothing is filed and nothing reaches
/// the account, which does not exist yet. The import itself runs after sign-in from the identifiers
/// this screen leaves in ``PreAuthOnboardingAnswers``.
@MainActor
@Observable
final class OnboardingHealthHistoryViewModel {
    enum State {
        case loading
        case found(HealthHistoryChoice)
        /// Nothing to show: no workouts, or a read that failed.
        case nothing
    }

    /// The `question_id` both answers report under, and the `answer_id` of the one that brings in
    /// nothing. Adding reports the range's own id (`HealthHistoryRange.analyticsID`).
    static let questionID = "health_history"
    static let skipAnswerID = "skip_history"

    private(set) var state: State = .loading

    @ObservationIgnored private let reader: any HealthWorkoutReading
    @ObservationIgnored private let skipReporter: any HealthWorkoutSkipReporting
    @ObservationIgnored private let loadClimbs: () -> [Climb]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let track: (any TelemetryEvent) -> Void

    init(
        reader: any HealthWorkoutReading = HealthKitWorkoutReader.shared,
        skipReporter: any HealthWorkoutSkipReporting = HealthWorkoutSkipReporter.shared,
        loadClimbs: @escaping () -> [Climb] = { (try? HostedClimbCatalogRepository().loadInitialCatalog().climbs) ?? [] },
        now: @escaping () -> Date = Date.init,
        track: @escaping (any TelemetryEvent) -> Void = { TelemetryManager.shared.track($0) }
    ) {
        self.reader = reader
        self.skipReporter = skipReporter
        self.loadClimbs = loadClimbs
        self.now = now
        self.track = track
    }

    /// Reads Health. With nothing to show the climber goes straight on to the usual-climb question,
    /// because this screen has nothing to say to them.
    func load(coordinator: OnboardingV3Coordinator) async {
        guard case .loading = state else { return }

        guard let history = try? await HealthHistory.load(using: reader, skipReporter: skipReporter),
              !history.isEmpty else {
            state = .nothing
            if coordinator.step == .healthHistory {
                coordinator.update { $0.clearFoundHealthHistory() }
                coordinator.go(to: .usualClimb, as: .noWorkoutsFound)
            }
            return
        }
        state = .found(HealthHistoryChoice(history: history, climbs: loadClimbs(), now: now()))
    }

    /// ADD TO MY HISTORY: records the workouts inside the range the climber left the row on, which
    /// the sign-in hand-off imports once there is an account, and the usual climb read from them,
    /// then moves on. Both answers stay on the device.
    func addToHistory(coordinator: OnboardingV3Coordinator) {
        guard case .found(let choice) = state else { return }
        let summary = choice.summary
        guard !summary.isEmpty else { return }

        report(answerID: choice.range.analyticsID, adding: summary.workoutCount, of: choice, coordinator: coordinator)
        coordinator.update {
            $0.recordFoundHealthHistory(summary)
            $0.usualClimbSteps = summary.usualClimb?.steps
            $0.usualClimbMinutes = summary.usualClimb?.minutes
        }
        coordinator.advance()
    }

    /// "Skip history, just import new workouts": nothing from before today is brought in, and the
    /// identifiers leave the device exactly as they do when Health is declined. Health stays
    /// connected with auto-import on, so the climber's next stair stepper workout still arrives.
    ///
    /// The usual climb is still the one read from what Health holds: it is what the climber was
    /// just shown, and the screens after this one speak to them with it.
    func skipHistory(coordinator: OnboardingV3Coordinator) {
        guard case .found(let choice) = state else { return }
        let usual = choice.history.summary(now: choice.now, calendar: choice.calendar).usualClimb

        report(answerID: Self.skipAnswerID, adding: 0, of: choice, coordinator: coordinator)
        coordinator.update {
            $0.clearFoundHealthHistory()
            $0.usualClimbSteps = usual?.steps
            $0.usualClimbMinutes = usual?.minutes
        }
        coordinator.advance(as: .skip)
    }

    private func report(
        answerID: String,
        adding count: Int,
        of choice: HealthHistoryChoice,
        coordinator: OnboardingV3Coordinator
    ) {
        track(OnboardingAnalyticsEvent.questionAnswered(
            context: coordinator.analyticsContext,
            questionID: Self.questionID,
            inputType: "button",
            selectionType: "single_select",
            answerID: answerID,
            answerIndex: nil,
            properties: [
                "workouts_added": .int(count),
                "workouts_found": .int(choice.history.workouts.count)
            ]
        ))
    }
}
