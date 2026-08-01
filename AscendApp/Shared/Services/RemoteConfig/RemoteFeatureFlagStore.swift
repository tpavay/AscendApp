import Foundation
import os.lock

/// The app-wide source of truth for ``RemoteFeatureFlag`` values.
///
/// Reads are lock-guarded rather than actor-isolated on purpose: the gates live inside sync
/// coordinators, repositories, and migrations that run on several isolation domains, and a kill
/// switch that forces an `await` at every call site would be skipped in exactly the places it
/// matters. A read is one uncontended lock acquisition and a dictionary lookup, which is cheap
/// enough to sit in front of a write without measuring.
///
/// ``RemoteFeatureFlagService`` owns updating this store; nothing else should call ``apply(_:)``
/// outside tests.
final class RemoteFeatureFlagStore: @unchecked Sendable {
    static let shared = RemoteFeatureFlagStore()

    private let state: OSAllocatedUnfairLock<RemoteFeatureFlagSnapshot>

    init(snapshot: RemoteFeatureFlagSnapshot = .shippedDefaults) {
        state = OSAllocatedUnfairLock(initialState: snapshot)
    }

    var snapshot: RemoteFeatureFlagSnapshot {
        state.withLock { $0 }
    }

    func isEnabled(_ flag: RemoteFeatureFlag) -> Bool {
        state.withLock { $0.isEnabled(flag) }
    }

    /// Replaces the resolved flag state. Returns whether anything actually changed, so callers can
    /// stay quiet when a refresh confirms what the app already believed.
    @discardableResult
    func apply(_ snapshot: RemoteFeatureFlagSnapshot) -> Bool {
        state.withLock { current in
            guard current != snapshot else { return false }
            current = snapshot
            return true
        }
    }
}

extension Notification.Name {
    /// Posted on the main actor after ``RemoteFeatureFlagStore/shared`` changes.
    static let remoteFeatureFlagsDidChange = Notification.Name("remoteFeatureFlagsDidChange")
}
