import Foundation

extension MonetizationManager: RefusedAccessRecovering {
    func recoverRefusedAccess(userInitiated: Bool) async -> Bool {
        guard entitlementState.hasActiveEntitlement(configuration.revenueCatEntitlementID) else {
            return false
        }

        await reconcileServerAppAccess(force: userInitiated)
        return true
    }
}
