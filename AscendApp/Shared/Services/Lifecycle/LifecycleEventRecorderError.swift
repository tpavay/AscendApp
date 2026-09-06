import Foundation

/// Failures raised before a lifecycle event reaches the network.
enum LifecycleEventRecorderError: Error, Equatable {
    /// Lifecycle events are per-user server state, and the callable rejects
    /// unauthenticated requests, so there is nothing to send while signed out.
    case signedOut
    /// The event belonged to a prior authenticated account and must not be written under the
    /// account that replaced it before fire-and-forget delivery began.
    case identityChanged
}
