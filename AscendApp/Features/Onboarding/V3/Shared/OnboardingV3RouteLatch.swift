import Foundation
import Observation

/// Decides once per launch whether a signed-out climber gets the v3 onboarding, so neither a slow
/// fetch nor a later console change can swap the flow under a climber already inside one.
///
/// A device the backend has already answered about the switch decides from that answer at once. A
/// device it never has - every fresh install - would read the shipped `false` and start the old
/// flow, so it holds until the first fetch ends or ``holdLimit`` runs out. Either way it then reads
/// the store, which still holds the shipped default if the fetch failed or has not landed.
@MainActor
@Observable
final class OnboardingV3RouteLatch {
    static let holdLimit: Duration = .milliseconds(1500)

    /// `nil` while the launch is still holding.
    private(set) var showsFlow: Bool?

    @ObservationIgnored private let store: RemoteFeatureFlagStore
    @ObservationIgnored private let firstFetch: @MainActor () async -> Void
    @ObservationIgnored private let holdLimit: Duration

    init(
        store: RemoteFeatureFlagStore = .shared,
        firstFetch: @escaping @MainActor () async -> Void = {
            await RemoteFeatureFlagService.shared.waitForCurrentRefresh()
        },
        holdLimit: Duration = OnboardingV3RouteLatch.holdLimit
    ) {
        self.store = store
        self.firstFetch = firstFetch
        self.holdLimit = holdLimit

        if store.snapshot.source(of: .onboardingV3) == .remote {
            showsFlow = store.isEnabled(.onboardingV3)
        }
    }

    /// Starts the clock. Two independent tasks rather than a task group, because a group could not
    /// return at the cap: awaiting the fetch's task does not end when the waiter is cancelled.
    func beginHold() {
        guard showsFlow == nil else { return }

        Task { [firstFetch, weak self] in
            await firstFetch()
            self?.decide()
        }
        Task { [holdLimit, weak self] in
            try? await Task.sleep(for: holdLimit)
            self?.decide()
        }
    }

    private func decide() {
        guard showsFlow == nil else { return }

        showsFlow = store.isEnabled(.onboardingV3)
    }
}
