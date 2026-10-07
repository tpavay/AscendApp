import Foundation

/// Re-derives a climber's paid access after the server refused a paid read.
///
/// Paid reads are authorized by a server-owned grant (`users/{uid}/entitlements/app_access`).
/// When that grant goes missing while the device still holds an entitlement, every paid read is
/// refused until `reconcileAppAccess` runs - and launch used to be its only caller, so on
/// 2026-09-25 the repair reached a climber only when they force-quit and reopened the app.
@MainActor
protocol RefusedAccessRecovering: AnyObject {
    /// Asks the server to re-derive this climber's access, once.
    ///
    /// - Parameter userInitiated: Whether the climber asked for the read that was refused, which
    ///   bypasses the client-side spacing between reconciliations. The server keeps its own.
    /// - Returns: `false`, having asked nothing, when the device holds no entitlement to
    ///   re-derive from - a refusal is then the paywall working, and retrying is pointless.
    func recoverRefusedAccess(userInitiated: Bool) async -> Bool
}
