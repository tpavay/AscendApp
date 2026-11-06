import Foundation
import Observation

/// 07a's state: the read, what it found, and what ADD TO MY HISTORY carries forward.
///
/// Read-only. The summary is a look at Health's own records; nothing is filed and nothing reaches
/// the account, which does not exist yet. The import itself runs after sign-in from the identifiers
/// this screen leaves in ``PreAuthOnboardingAnswers``.
@MainActor
@Observable
final class OnboardingHealthHistoryViewModel {
    enum State {
        case loading
        case found(HealthHistorySummary)
        /// Nothing to show: no workouts, or a read that failed.
        case nothing
    }

    private(set) var state: State = .loading
    private(set) var comparison: HealthHistoryComparison?

    @ObservationIgnored private let reader: any HealthWorkoutReading
    @ObservationIgnored private let loadClimbs: () -> [Climb]
    @ObservationIgnored private let now: () -> Date

    init(
        reader: any HealthWorkoutReading = HealthKitWorkoutReader.shared,
        loadClimbs: @escaping () -> [Climb] = { (try? HostedClimbCatalogRepository().loadInitialCatalog().climbs) ?? [] },
        now: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.loadClimbs = loadClimbs
        self.now = now
    }

    /// Reads Health. With nothing to show the climber goes straight on to the usual-climb question,
    /// because this screen has nothing to say to them.
    func load(coordinator: OnboardingV3Coordinator) async {
        guard case .loading = state else { return }

        guard let summary = try? await HealthHistorySummary.load(using: reader, now: now()),
              !summary.isEmpty else {
            state = .nothing
            if coordinator.step == .healthHistory {
                coordinator.update { $0.foundHealthWorkoutIDs = [] }
                coordinator.go(to: .usualClimb)
            }
            return
        }
        comparison = HealthHistoryComparison.make(knownSteps: summary.knownSteps, climbs: loadClimbs())
        state = .found(summary)
    }

    /// ADD TO MY HISTORY: records the workouts the climber was shown, which the sign-in hand-off
    /// imports once there is an account, and the usual climb read from them, then moves on. Both
    /// answers stay on the device; the first has to be non-empty or the hand-off has nothing to do.
    func addToHistory(coordinator: OnboardingV3Coordinator) {
        guard case .found(let summary) = state else { return }

        coordinator.update {
            $0.foundHealthWorkoutIDs = summary.workoutIDs
            $0.usualClimbSteps = summary.usualClimb?.steps
            $0.usualClimbMinutes = summary.usualClimb?.minutes
        }
        coordinator.advance()
    }
}
