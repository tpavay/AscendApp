import Foundation

/// What Apple is still deciding on: an Ask to Buy waiting for a parent, or a charge RevenueCat has
/// not confirmed. While it is here nothing else can be bought, so a relaunch cannot turn one
/// purchase into two.
///
/// Local only: nothing here reaches Firestore, and it holds no identity - a product id and a kind.
struct PendingPurchaseHold: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case askToBuy
        case unconfirmedCharge
    }

    var productID: String
    var kind: Kind
}

/// One JSON value under one key: an undecodable value reads as "nothing is pending" rather than
/// failing the paywall.
///
/// The hold belongs to the session that bought, so sign-out clears it
/// (``OnboardingV3Coordinator/sessionEnded()``): a marker left behind would lock the next account's
/// paywall on a purchase it never made.
struct PendingPurchaseHoldStore: @unchecked Sendable {
    static let storageKey = "onboardingPaywall.v2.pendingPurchase"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hold() -> PendingPurchaseHold? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(PendingPurchaseHold.self, from: data)
    }

    func mark(_ hold: PendingPurchaseHold) {
        guard let data = try? JSONEncoder().encode(hold) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
