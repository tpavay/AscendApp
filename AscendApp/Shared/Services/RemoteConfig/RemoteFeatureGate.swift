import Foundation

/// The one way a data path asks whether it is still allowed to run.
///
/// Gates are placed at the choke point that understands how to *defer* work, never at the raw
/// Firestore call: a blocked path must leave its pending state exactly as it found it, so the work
/// flushes on its own once the flag comes back on. A gate that dropped queued writes would turn a
/// kill switch into a second data-loss bug.
enum RemoteFeatureGate {
    /// Returns whether `flag` permits the work to proceed, recording a diagnostic on the rare
    /// occasion it does not. `path` names the call site so the log says which work was skipped.
    static func allows(
        _ flag: RemoteFeatureFlag,
        path: String,
        store: RemoteFeatureFlagStore = .shared,
        diagnostics: AppDiagnosticsRecorder = .shared
    ) -> Bool {
        guard store.isEnabled(flag) == false else { return true }

        diagnostics.record(
            "remote_feature_gate_blocked",
            level: .warning,
            details: ["flag": flag.key, "path": path]
        )
        return false
    }
}
