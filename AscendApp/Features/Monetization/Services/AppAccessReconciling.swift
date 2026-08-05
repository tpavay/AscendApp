import Foundation

/// Asks the server to re-derive the signed-in user's paid access from RevenueCat.
///
/// The device entitlement is the responsive answer; the server projection is the authorization.
/// A purchase or a restore can outrun the webhook that publishes that projection, and a webhook
/// that never arrives has no other in-app remedy, so every path that can legitimately hold an
/// active device entitlement asks the server to catch up.
@MainActor
protocol AppAccessReconciling: AnyObject {
    /// - Parameter force: Bypasses the client-side spacing for a user-initiated restore.
    func reconcileAppAccess(force: Bool) async
}
