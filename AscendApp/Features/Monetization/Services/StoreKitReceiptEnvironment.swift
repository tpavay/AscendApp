import Foundation

/// What StoreKit environment this install looks like from the inside.
///
/// Purely diagnostic - nothing routes, gates, or grants from it. The RevenueCat SDK reads the same
/// receipt name to decide whether a purchase "belongs" to the running binary, and that comparison
/// is what hid an App Review purchase behind a payment (#506). Ascend no longer asks the question,
/// but it does record the answer, because no source states what an App Review device actually
/// reports and one field settles it.
enum StoreKitReceiptEnvironment {
    /// The receipt file name iOS handed this install, or `none` when there is no receipt URL at
    /// all - a real condition on a StoreKit 2 app that never refreshes one, and the case
    /// `BundleSandboxEnvironmentDetector` silently reads as production.
    static var receiptName: String {
        Bundle.main.appStoreReceiptURL?.lastPathComponent ?? "none"
    }
}
