import Foundation

/// What a signed-out device remembers about the paywall, so a relaunch before sign-in resumes where
/// the climber was instead of replaying twelve screens.
///
/// Local only: nothing here reaches Firestore, and it holds no identity - a product id and two dates.
struct PreAuthPaywallProgress: Codable, Equatable, Sendable {
    /// The climber got as far as the paywall. A relaunch opens on it rather than on the welcome.
    var reachedPaywallAt: Date?

    /// Apple took the money as the anonymous RevenueCat customer. The purchase waits on the device
    /// until sign-in moves it onto the account, and a relaunch before then opens on sign-in.
    var purchase: PreAuthPurchase?
}

struct PreAuthPurchase: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case purchase
        /// Restore found a purchase on the Apple ID, so sign-in opens in returning mode.
        case restore
    }

    var source: Source = .purchase
    var productID: String
    var purchasedAt: Date
    /// Whether the product started a free trial, which is what the trial-ending reminder reads.
    var startedTrial: Bool
}

/// One JSON value under one key, like ``PreAuthOnboardingStore``: an undecodable value reads as
/// "nothing happened" rather than failing the flow.
struct PreAuthPurchaseLedger: @unchecked Sendable {
    static let storageKey = "preAuthPaywall.v1.progress"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func progress() -> PreAuthPaywallProgress {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let progress = try? JSONDecoder().decode(PreAuthPaywallProgress.self, from: data) else {
            return PreAuthPaywallProgress()
        }

        return progress
    }

    /// The step a relaunch opens the flow on, or `nil` for the beginning.
    ///
    /// A purchase waiting for sign-in wins over having reached the paywall: the climber has paid,
    /// so the only thing left to do is claim it.
    var resumeStep: OnboardingV3Step? {
        let progress = progress()
        if progress.purchase != nil { return .auth }
        if progress.reachedPaywallAt != nil { return .paywall }
        return nil
    }

    func markPaywallReached(at date: Date = Date()) {
        update { progress in
            guard progress.reachedPaywallAt == nil else { return }
            progress.reachedPaywallAt = date
        }
    }

    func recordPurchase(_ purchase: PreAuthPurchase) {
        update { $0.purchase = purchase }
    }

    /// The purchase has moved onto the account, or the climber is no longer in this flow.
    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }

    private func update(_ change: (inout PreAuthPaywallProgress) -> Void) {
        var progress = progress()
        change(&progress)
        guard let data = try? JSONEncoder().encode(progress) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
