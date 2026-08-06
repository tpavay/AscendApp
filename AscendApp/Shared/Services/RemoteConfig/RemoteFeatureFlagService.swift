import Foundation

/// Keeps ``RemoteFeatureFlagStore/shared`` current: one fetch at launch and on every foreground,
/// plus a real-time listener that lands a console change on a running app within seconds.
///
/// Owns the cancellation contract for both. A superseded refresh is cancelled rather than left to
/// race the one that replaced it, and the listener registration is removed on ``teardown()`` so it
/// cannot outlive the service.
@MainActor
final class RemoteFeatureFlagService {
    static let shared = RemoteFeatureFlagService()

    private let source: any RemoteFeatureFlagSource
    private let store: RemoteFeatureFlagStore
    private let appVersionGateState: AppVersionGateState
    private let appMarketingVersionProvider: AppMarketingVersionProvider
    private let lifecycleCoordinator: RemoteFeatureFlagLifecycleCoordinator
    private let diagnostics: AppDiagnosticsRecorder
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var isListening = false

    /// Whether a fetch has ever succeeded on this launch. `false` means every flag is running on
    /// its shipped default or on a value the SDK persisted from a previous launch.
    private(set) var hasCompletedInitialFetch = false

    /// Counts refresh requests synchronously, before their asynchronous fetch begins. This exposes
    /// the lifecycle trigger boundary to deterministic tests without coupling them to task timing.
    private(set) var refreshRequestCount = 0

    /// Whether any flag is currently resolved from a backend-supplied value, whether that arrived
    /// on this launch or was seeded from the SDK's persisted activation. Only used to say honestly
    /// in diagnostics what a failed fetch fell back to.
    private var hasBackendSourcedValues = false

    init(
        source: any RemoteFeatureFlagSource,
        store: RemoteFeatureFlagStore = .shared,
        appVersionGateState: AppVersionGateState = AppVersionGateState(),
        appMarketingVersionProvider: AppMarketingVersionProvider = .init { nil },
        lifecycleCoordinator: RemoteFeatureFlagLifecycleCoordinator = .init(),
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.source = source
        self.store = store
        self.appVersionGateState = appVersionGateState
        self.appMarketingVersionProvider = appMarketingVersionProvider
        self.lifecycleCoordinator = lifecycleCoordinator
        self.diagnostics = diagnostics
    }

    private convenience init() {
        self.init(
            source: FirebaseRemoteFeatureFlagSource(),
            appVersionGateState: .shared,
            appMarketingVersionProvider: .mainBundle
        )
    }

    /// Seeds the store from the SDK's persisted activation, then starts the real-time listener and
    /// kicks off the first fetch. Call once, after Firebase is configured.
    ///
    /// The seed is synchronous and comes first on purpose: it is the only step that cannot fail, so
    /// every gate reads an operator's last published answer from the first line of the launch,
    /// including the offline launch where no fetch will ever land.
    func configure() {
        seedFromPersistedActivation()
        startListeningIfNeeded()
        lifecycleCoordinator.start { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    /// Re-fetches the template. Cheap to call on every foreground: the SDK's `minimumFetchInterval`
    /// serves a cached answer without a network round trip inside the window, so this does not turn
    /// into a per-foreground billable fetch.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        refreshRequestCount += 1
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(generation: generation)
        }
        refreshTask = task
        return task
    }

    /// ``refresh()`` plus the wait for its result. ``refresh()`` is the fire-and-forget form call
    /// sites use; this exists so a test can assert on the outcome without polling.
    func refreshAndWait() async {
        await refresh().value
    }

    func waitForCurrentRefresh() async {
        await refreshTask?.value
    }

    /// Tears down the real-time connection and cancels any in-flight refresh.
    func teardown() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        lifecycleCoordinator.stop()
        source.stopListening()
        isListening = false
    }

    /// Publishes the values the SDK already holds, before any network work. Safe to call whether or
    /// not the device has ever fetched: a device that never has supplies nothing here, so every
    /// flag stays on its shipped default.
    private func seedFromPersistedActivation() {
        apply(remoteValues: source.activatedValues(), trigger: "persisted_activation")
    }

    private func performRefresh(generation: UInt64) async {
        do {
            let remoteValues = try await source.fetchAndActivate()
            // Applied even when this task was superseded. The round trip is already paid for, the
            // store update is idempotent, and throwing away a kill switch to honour a cancellation
            // is the wrong trade for a mechanism that exists for the worst day.
            hasCompletedInitialFetch = true
            apply(remoteValues: remoteValues, trigger: "fetch")
            guard generation == refreshGeneration else { return }
            appVersionGateState.resolve(
                currentVersion: appMarketingVersionProvider.currentVersion(),
                remoteValues: source.appVersionValues()
            )
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            appVersionGateState.failOpen()
            // Deliberately non-fatal. Every flag keeps whatever it already resolved to - the last
            // activated value the SDK persisted, or the shipped default - so a failed fetch never
            // changes app behaviour on its own.
            let resolvedFrom: String
            if hasCompletedInitialFetch {
                resolvedFrom = "previous_fetch"
            } else if hasBackendSourcedValues {
                resolvedFrom = "persisted_activation"
            } else {
                resolvedFrom = "shipped_defaults"
            }
            diagnostics.record(
                "remote_config_fetch_failed",
                level: .warning,
                details: [
                    "error_type": String(describing: type(of: error)),
                    "resolved_from": resolvedFrom
                ]
            )
        }
    }

    private func startListeningIfNeeded() {
        guard !isListening else { return }
        isListening = true
        // Weak, because the source outlives the callback and holds it for the life of the
        // registration - a strong capture would be a retain cycle through `source`.
        source.startListening { [weak self] remoteValues in
            Task { @MainActor in
                guard let self else { return }
                self.hasCompletedInitialFetch = true
                self.apply(remoteValues: remoteValues, trigger: "realtime_update")
            }
        }
    }

    private func apply(remoteValues: [String: Bool], trigger: String) {
        hasBackendSourcedValues = remoteValues.isEmpty == false
        let snapshot = RemoteFeatureFlagSnapshot.resolving(remoteValues: remoteValues)
        guard store.apply(snapshot) else { return }

        let disabledFlagKeys = snapshot.disabledFlagKeys
        diagnostics.record(
            "remote_config_flags_changed",
            level: disabledFlagKeys.isEmpty ? .info : .warning,
            details: [
                "trigger": trigger,
                "disabled_flags": disabledFlagKeys.isEmpty
                    ? "none"
                    : disabledFlagKeys.joined(separator: ",")
            ]
        )
        NotificationCenter.default.post(name: .remoteFeatureFlagsDidChange, object: nil)
    }
}
