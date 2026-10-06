import Foundation

/// Marks an app-side deadline on a server read, so every feature's own timeout error classifies
/// as `ServerReadFailureClass.unreachable` without the classifier naming each feature.
protocol ServerReadTimeoutError: Error {}
