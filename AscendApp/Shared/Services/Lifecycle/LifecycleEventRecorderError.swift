import Foundation

/// Failures raised before a lifecycle event reaches the network.
enum LifecycleEventRecorderError: Error, Equatable {
    /// Lifecycle events are per-user server state, and the callable rejects
    /// unauthenticated requests, so there is nothing to send while signed out.
    case signedOut
}
