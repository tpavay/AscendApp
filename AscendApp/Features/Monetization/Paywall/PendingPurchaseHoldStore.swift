import Foundation

/// What Apple is still deciding on: an Ask to Buy waiting for a parent, or a charge RevenueCat has
/// not confirmed. While one is held the gate offers nothing to buy, so closing a paywall or
/// relaunching cannot turn one purchase into two.
enum PendingPurchaseHold: String, Codable, Sendable {
    case askToBuy
    case unconfirmedCharge
}

/// One raw value under one key: an unreadable value reads as "nothing is pending" rather than
/// failing the gate. Local only; it holds no identity.
///
/// The hold belongs to the session that bought, so sign-out clears it (`RootView`): a marker left
/// behind would lock the next account's gate on a purchase it never made.
struct PendingPurchaseHoldStore: @unchecked Sendable {
    static let storageKey = "appAccessGate.pendingPurchase"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hold() -> PendingPurchaseHold? {
        userDefaults.string(forKey: Self.storageKey).flatMap(PendingPurchaseHold.init(rawValue:))
    }

    func mark(_ hold: PendingPurchaseHold) {
        userDefaults.set(hold.rawValue, forKey: Self.storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
