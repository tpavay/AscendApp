import FirebaseFirestore
import Foundation
import os.lock

/// The process-wide answer to two questions `FirestoreDiskPolicy` decides: which cache this
/// process runs Firestore with, and whether a cache-writing Firestore operation may run right
/// now.
///
/// `activate(applyingTo:)` runs once, in `AscendApp.configureFirebase()`, before anything can
/// touch `Firestore.firestore()` - the SDK refuses settings after first use. The pre-flight
/// `allowsLocalCacheWrite()` is asked by `ServerPreferredRead` in front of every server read
/// and by `WorkoutSyncCoordinator` in front of every sync pass; both already know how to fail
/// without losing anything (the live board says it could not refresh and the climb keeps
/// counting; the outbox stays pending). A memory-cache process answers yes without reading the
/// disk, because it has nothing to protect.
///
/// Lock-guarded rather than actor-isolated for the same reason `RemoteFeatureFlagStore` is: the
/// gate sits inside a generic isolated read path, and a pre-flight that forced an `await` would
/// be skipped in exactly the places it matters.
final class FirestoreDiskGuard: @unchecked Sendable {
    static let shared = FirestoreDiskGuard()

    private struct State {
        /// The volume Firestore's cache lives on - the app container's, unless a test activated
        /// the guard on a volume it controls.
        var volume: any VolumeFreeSpaceReading
        var cacheMode: FirestoreCacheMode?
        var hasReportedReadGate = false
    }

    private let state: OSAllocatedUnfairLock<State>
    private let featureFlags: RemoteFeatureFlagStore
    private let diagnostics: any AppDiagnosticsRecording
    private let telemetry: @Sendable (TelemetryRecord) -> Void

    init(
        freeSpace: any VolumeFreeSpaceReading = VolumeFreeSpaceReader(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared,
        telemetry: @escaping @Sendable (TelemetryRecord) -> Void = { TelemetryManager.shared.track($0) }
    ) {
        self.state = OSAllocatedUnfairLock(initialState: State(volume: freeSpace))
        self.featureFlags = featureFlags
        self.diagnostics = diagnostics
        self.telemetry = telemetry
    }

    /// The cache this process was activated with, nil before `activate` or `decideCacheMode`.
    var cacheMode: FirestoreCacheMode? {
        state.withLock { $0.cacheMode }
    }

    /// Decides this process's cache from the volume and applies it to `firestore`.
    ///
    /// Must run before `firestore` performs any operation; the SDK throws on a settings change
    /// after first use, and a decision taken later would be too late to keep LevelDB off the
    /// disk anyway.
    ///
    /// - Parameter volume: The volume `firestore`'s cache lives on, which the guard then
    ///   watches for every pre-flight. Nil keeps the one it was constructed with - the app
    ///   container's; `FirestoreDiskFullSurvivalTests` passes the disk image it points a
    ///   dedicated instance at.
    @discardableResult
    func activate(applyingTo firestore: Firestore, on volume: (any VolumeFreeSpaceReading)? = nil) -> FirestoreCacheMode {
        let mode = decideCacheMode(on: volume)
        let settings = firestore.settings
        settings.cacheSettings = mode.makeCacheSettings()
        firestore.settings = settings
        return mode
    }

    /// Decides and records this process's cache without touching an instance, for a caller
    /// that applies the settings itself. Re-arms the once-per-activation read-gate report.
    @discardableResult
    func decideCacheMode(on volume: (any VolumeFreeSpaceReading)? = nil) -> FirestoreCacheMode {
        let freeSpace = state.withLock { state in
            if let volume { state.volume = volume }
            return state.volume
        }
        let availableBytes = freeSpace.availableBytes()
        let mode = FirestoreDiskPolicy.cacheMode(availableBytes: availableBytes, isEnabled: isEnabled)
        state.withLock {
            $0.cacheMode = mode
            $0.hasReportedReadGate = false
        }
        if !mode.usesLocalDisk {
            report(trigger: .launchMemoryCache, cacheMode: mode, availableBytes: availableBytes)
        } else if availableBytes == nil {
            // Unreachable by construction - an unreadable volume is answered with memory - but
            // the policy is the authority on that, so this stays as the record of a surprise.
            diagnostics.record(
                "firestore_disk_reading_unavailable",
                level: .warning,
                details: ["cache_mode": mode.analyticsValue],
                mirrorToCrashlytics: true
            )
        }
        return mode
    }

    /// Whether a Firestore operation that would write the local cache may run right now.
    func allowsLocalCacheWrite() -> Bool {
        guard isEnabled else { return true }
        let (cacheMode, freeSpace) = state.withLock { ($0.cacheMode, $0.volume) }
        if let cacheMode, !cacheMode.usesLocalDisk { return true }

        let availableBytes = freeSpace.availableBytes()
        let allowed = FirestoreDiskPolicy.allowsLocalCacheWrite(
            cacheMode: cacheMode,
            availableBytes: availableBytes,
            isEnabled: true
        )
        if !allowed { reportReadGateOnce(cacheMode: cacheMode, availableBytes: availableBytes) }
        return allowed
    }

    private var isEnabled: Bool {
        featureFlags.isEnabled(.firestoreMemoryCacheOnLowDisk)
    }

    /// One report per activation: the gate is asked several times a second during a climb, and
    /// the first refusal is the fact; the rest are the same fact.
    private func reportReadGateOnce(cacheMode: FirestoreCacheMode?, availableBytes: Int64?) {
        let isFirst = state.withLock { state in
            guard !state.hasReportedReadGate else { return false }
            state.hasReportedReadGate = true
            return true
        }
        guard isFirst else { return }
        report(
            trigger: .readGate,
            cacheMode: cacheMode ?? .persistent(sizeBytes: FirestoreDiskPolicy.sdkDefaultPersistentCacheSizeBytes),
            availableBytes: availableBytes
        )
    }

    private func report(trigger: FirestoreDiskAnalyticsEvent.Trigger, cacheMode: FirestoreCacheMode, availableBytes: Int64?) {
        let importantUsageBytes = state.withLock { $0.volume }.availableBytesForImportantUsage()
        diagnostics.record(
            "firestore_low_disk_mode",
            level: .warning,
            details: [
                "trigger": trigger.rawValue,
                "cache_mode": cacheMode.analyticsValue,
                "free_bytes": availableBytes.map(String.init) ?? "unknown",
                "important_free_bytes": importantUsageBytes.map(String.init) ?? "unknown"
            ],
            mirrorToCrashlytics: true
        )
        telemetry(
            FirestoreDiskAnalyticsEvent.lowDiskMode(
                trigger: trigger,
                cacheMode: cacheMode,
                availableBytes: availableBytes,
                availableBytesForImportantUsage: importantUsageBytes
            ).record
        )
    }
}
