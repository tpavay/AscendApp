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
    private let diagnostics: AppDiagnosticsRecorder
    private var refreshTask: Task<Void, Never>?
    private var isListening = false

    /// Whether a fetch has ever succeeded on this launch. `false` means every flag is running on
    /// its shipped default or on a value the SDK persisted from a previous launch.
    private(set) var hasCompletedInitialFetch = false

    init(
        source: any RemoteFeatureFlagSource,
        store: RemoteFeatureFlagStore = .shared,
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.source = source
        self.store = store
        self.diagnostics = diagnostics
    }

    private convenience init() {
        self.init(source: FirebaseRemoteFeatureFlagSource())
    }

    /// Starts the real-time listener and kicks off the first fetch. Call once, after Firebase is
    /// configured.
    func configure() {
        startListeningIfNeeded()
        refresh()
    }

    /// Re-fetches the template. Cheap to call on every foreground: the SDK's `minimumFetchInterval`
    /// serves a cached answer without a network round trip inside the window, so this does not turn
    /// into a per-foreground billable fetch.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    /// ``refresh()`` plus the wait for its result. ``refresh()`` is the fire-and-forget form call
    /// sites use; this exists so a test can assert on the outcome without polling.
    func refreshAndWait() async {
        refresh()
        await refreshTask?.value
    }

    /// Tears down the real-time connection and cancels any in-flight refresh.
    func teardown() {
        refreshTask?.cancel()
        refreshTask = nil
        source.stopListening()
        isListening = false
    }

    private func performRefresh() async {
        do {
            let remoteValues = try await source.fetchAndActivate()
            guard !Task.isCancelled else { return }
            hasCompletedInitialFetch = true
            apply(remoteValues: remoteValues, trigger: "fetch")
        } catch {
            guard !Task.isCancelled else { return }
            // Deliberately non-fatal. Every flag keeps whatever it already resolved to - the last
            // activated value the SDK persisted, or the shipped default - so a failed fetch never
            // changes app behaviour on its own.
            diagnostics.record(
                "remote_config_fetch_failed",
                level: .warning,
                details: [
                    "error_type": String(describing: type(of: error)),
                    "resolved_from": hasCompletedInitialFetch ? "previous_fetch" : "shipped_defaults"
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
