import Foundation
import Observation

/// Settings -> Integrations -> Apple Health -> Import older workouts: the same look at Health's history that
/// onboarding's "We found your climbs" takes, for a climber who already has an account.
///
/// What it lists is what the history backfill can still bring in: stair workouts from before the
/// climber joined that are not climbs yet and were never turned away. Workouts since joining are
/// the pass's, and arrive through Imports.
@MainActor
@Observable
final class AppleHealthOlderWorkoutsViewModel {
    enum State {
        case loading
        case found(HealthHistoryChoice)
        /// Health was read and holds nothing older to bring in.
        case nothing
        /// Health could not be read right now. Never said as "nothing".
        case unavailable
    }

    static let importFailedMessage = "Some workouts did not make it in. Try again."

    private(set) var state: State = .loading
    private(set) var isImporting = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let importService: AppleHealthImportService
    @ObservationIgnored private let loadClimbs: () -> [Climb]
    @ObservationIgnored private let now: () -> Date

    init(
        importService: AppleHealthImportService = .shared,
        loadClimbs: @escaping () -> [Climb] = { (try? HostedClimbCatalogRepository().loadInitialCatalog().climbs) ?? [] },
        now: @escaping () -> Date = Date.init
    ) {
        self.importService = importService
        self.loadClimbs = loadClimbs
        self.now = now
    }

    func load() async {
        guard case .loading = state else { return }

        guard let older = await importService.olderWorkouts() else {
            state = .unavailable
            return
        }
        let history = HealthHistory(workouts: older)
        state = history.isEmpty
            ? .nothing
            : .found(HealthHistoryChoice(history: history, climbs: loadClimbs(), now: now()))
    }

    /// ADD TO MY HISTORY: files the workouts inside the picked range through the history backfill.
    ///
    /// - Returns: Whether every one of them landed, which is when the screen closes. Otherwise the
    ///   screen stays with a line to try again, and a second run files only what is still waiting.
    func addToHistory() async -> Bool {
        guard case .found(let choice) = state, !isImporting else { return false }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let landed = await importService.importHistory(matching: Set(choice.summary.workoutIDs))
        if !landed { errorMessage = Self.importFailedMessage }
        return landed
    }
}
