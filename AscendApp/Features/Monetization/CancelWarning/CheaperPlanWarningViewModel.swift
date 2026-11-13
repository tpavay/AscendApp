import Foundation
import Observation

/// Owns the cheaper-plan heads-up that Settings shows before Apple's cancellation sheet.
///
/// The rule it protects: **the warning never gets in the way of cancelling.** The answer is read
/// ahead of the tap and the tap only ever consults what is already here, so a slow store, a failed
/// read or a switch that is off means Apple's sheet opens at once, exactly as it did before this
/// existed. The two buttons both leave; neither is a trap.
@MainActor
@Observable
final class CheaperPlanWarningViewModel {
    /// Bound to the alert. Only `manageTapped` turns it on.
    var isPresentingWarning = false

    /// The warning the last read produced, or `nil` when it found none or has not finished.
    private(set) var warning: CheaperPlanWarning?

    @ObservationIgnored private let provider: any SubscriberRateProviding
    @ObservationIgnored private let featureFlags: RemoteFeatureFlagStore
    @ObservationIgnored private let track: @MainActor (CheaperPlanWarningAnalyticsEvent) -> Void
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        provider: any SubscriberRateProviding = StoreKitSubscriberRateProvider(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        track: @escaping @MainActor (CheaperPlanWarningAnalyticsEvent) -> Void = { event in
            TelemetryManager.shared.track(event)
        }
    ) {
        self.provider = provider
        self.featureFlags = featureFlags
        self.track = track
    }

    /// Reads the held plan and the standard yearly price. Called when Settings appears, so the
    /// answer is waiting by the time anyone taps Manage Subscription.
    func refresh() async {
        guard featureFlags.isEnabled(.cheaperPlanCancelWarning) else {
            warning = nil
            return
        }

        // A second call while one is in flight joins it rather than racing it.
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { [provider] in
            let snapshot = await provider.currentRates()
            // A read that failed keeps whatever the last good one said; that is never a reason to
            // newly warn, and never a reason to stop warning someone it already found eligible.
            guard let snapshot else { return }
            self.warning = CheaperPlanWarningPolicy.warning(
                for: snapshot.held,
                standardYearly: snapshot.standardYearly
            )
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// The Manage Subscription tap. Shows the warning when there is one ready, otherwise hands
    /// straight to Apple's sheet - it never waits on the store.
    func manageTapped(openSystemFlow: @MainActor () -> Void) {
        guard featureFlags.isEnabled(.cheaperPlanCancelWarning), let warning else {
            openSystemFlow()
            return
        }

        isPresentingWarning = true
        track(.shown(warning))
    }

    func keepTapped() {
        isPresentingWarning = false
        guard let warning else { return }
        track(.keepTapped(warning))
    }

    func continueTapped(openSystemFlow: @MainActor () -> Void) {
        isPresentingWarning = false
        if let warning {
            track(.continueTapped(warning))
        }
        openSystemFlow()
    }
}
