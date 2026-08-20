import Foundation

/// Holds what a sign-in provider handed back until the climber's profile
/// actually carries it.
///
/// This exists for Sign in with Apple specifically, because Apple's offer stands
/// exactly once: the name and email are populated on the first authorization for
/// an Apple ID and app pair, so if the profile write fails - offline, a dropped
/// connection, the app killed between the two - there is no second chance to
/// ask. The capture stays here and the next sign-in retries it. Google needs
/// nothing stored; Firebase carries its display name on every sign-in.
///
/// Deliberately NOT cleared on sign-out: signing out and back in is exactly the
/// case where Apple returns nil for everything. Account deletion does clear it,
/// through `AppAccountDeletionLocalCleanup.clearUserDefaults` wiping the app's
/// whole UserDefaults domain.
@MainActor
final class SignInIdentityStore {
    static let shared = SignInIdentityStore()

    private enum Keys {
        /// Renamed with the type. Nothing shipped ever wrote the old key: the
        /// capture landed on the branch that fixes the rejected build and never
        /// reached a release, so there is no stored record to migrate.
        static let suppliedIdentities = "auth.signInSuppliedIdentities"
    }

    /// One device can see several accounts, but only captures still waiting to
    /// reach a profile are kept. The cap bounds a list that would otherwise only
    /// ever grow.
    private static let retainedCaptureLimit = 5

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Records what an authorization supplied, merged over any earlier capture
    /// for the same provider account so a later nil cannot erase a name already
    /// held.
    func record(_ identity: SignInSuppliedIdentity) {
        var stored = storedIdentities()
        let merged = identity.mergingRetainedValues(from: stored[identity.providerUserID])
        guard merged.carriesSomething else { return }

        stored[identity.providerUserID] = merged
        save(stored)
    }

    func identity(forProviderUserID providerUserID: String?) -> SignInSuppliedIdentity? {
        guard let providerUserID, !providerUserID.isEmpty else { return nil }
        return storedIdentities()[providerUserID]
    }

    /// Called once the capture has reached the climber's profile, or once the
    /// profile turns out to carry a name already.
    func forget(providerUserID: String) {
        var stored = storedIdentities()
        guard stored.removeValue(forKey: providerUserID) != nil else { return }
        save(stored)
    }

    private func storedIdentities() -> [String: SignInSuppliedIdentity] {
        guard let data = userDefaults.data(forKey: Keys.suppliedIdentities),
              let decoded = try? JSONDecoder().decode(
                  [String: SignInSuppliedIdentity].self,
                  from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private func save(_ identities: [String: SignInSuppliedIdentity]) {
        let retained = identities
            .sorted { $0.value.capturedAt > $1.value.capturedAt }
            .prefix(Self.retainedCaptureLimit)

        guard !retained.isEmpty else {
            userDefaults.removeObject(forKey: Keys.suppliedIdentities)
            return
        }

        guard let data = try? JSONEncoder().encode(
            Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        ) else {
            return
        }
        userDefaults.set(data, forKey: Keys.suppliedIdentities)
    }
}
