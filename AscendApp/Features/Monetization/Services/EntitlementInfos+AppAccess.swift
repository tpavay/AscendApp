import Foundation
import RevenueCat

extension RevenueCat.EntitlementInfos {
    /// The entitlements this climber holds, in whichever StoreKit environment they bought them.
    ///
    /// Deliberately `activeInAnyEnvironment` rather than `activeInCurrentEnvironment`. The latter
    /// counts an entitlement only when its `isSandbox` flag matches the SDK's own reading of the
    /// running binary, and that reading is the App Store receipt path
    /// (`BundleSandboxEnvironmentDetector`). An App Review build is installed like an App Store
    /// build but transacts in the sandbox, so the reviewer's real, RevenueCat-verified purchase
    /// carried `isSandbox: true` under a binary the SDK read as production, and the entitlement
    /// vanished from the current-environment set. Ascend then told a reviewer it had just charged
    /// that it "couldn't confirm your subscription" - the Guideline 2.1(b) rejection of build
    /// 2026081401. TestFlight cannot reproduce it, because a TestFlight install carries a
    /// `sandboxReceipt` path and the two flags agree.
    ///
    /// Counting every environment loosens nothing. Paid access at the Firebase boundary is the
    /// server-owned grant, and `buildAppAccessProjection` derives that from RevenueCat's subscriber
    /// API without consulting `is_sandbox` either - so this is the reading that agrees with the
    /// authority, and the filtered one was the reading that silently disagreed with it.
    var appAccessEntitlementIDs: Set<String> {
        Set(activeInAnyEnvironment.keys)
    }

    /// The same reading, as the state every Ascend surface routes and reports from.
    var appAccessEntitlementState: MonetizationEntitlementState {
        let entitlementIDs = appAccessEntitlementIDs

        return entitlementIDs.isEmpty ? .inactive : .active(entitlementIDs)
    }

    /// Whether anything this climber holds was bought in Apple's sandbox.
    ///
    /// Reported beside ``StoreKitReceiptEnvironment/receiptName`` because that pair is exactly what
    /// the discarded filter compared, and neither half was observable anywhere in Ascend when it
    /// refused a paying reviewer. Recording both turns the next environment surprise into one
    /// glance instead of another review cycle.
    var holdsSandboxEntitlement: Bool {
        activeInAnyEnvironment.values.contains(where: \.isSandbox)
    }
}
