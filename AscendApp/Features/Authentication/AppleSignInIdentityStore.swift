import Foundation

/// Holds what Apple handed back at a Sign in with Apple authorization until the
/// climber's profile actually carries it.
///
/// This has to outlive the sign-in that captured it. Apple populates the name
/// and email on the first authorization only, so if the profile write fails -
/// offline, a dropped connection, the app killed between the two - there is no
/// second chance to ask. The capture stays here and the next sign-in retries it.
///
/// Deliberately NOT cleared on sign-out: signing out and back in is exactly the
/// case where Apple returns nil for everything. Account deletion does clear it,
/// through `AppAccountDeletionLocalCleanup.clearUserDefaults` wiping the app's
/// whole UserDefaults domain.
@MainActor
final class AppleSignInIdentityStore {
    static let shared = AppleSignInIdentityStore()

    private enum Keys {
        static let suppliedIdentities = "auth.appleSuppliedIdentities"
    }

    /// One device can see several Apple IDs, but only captures still waiting to
    /// reach a profile are kept. The cap bounds a list that would otherwise only
    /// ever grow.
    private static let retainedCaptureLimit = 5

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Records what an authorization supplied, merged over any earlier capture
    /// for the same Apple ID so a later nil cannot erase a name already held.
    func record(_ identity: AppleSignInSuppliedIdentity) {
        var stored = storedIdentities()
        let merged = identity.mergingRetainedValues(from: stored[identity.appleUserID])
        guard merged.carriesSomething else { return }

        stored[identity.appleUserID] = merged
        save(stored)
    }

    func identity(forAppleUserID appleUserID: String?) -> AppleSignInSuppliedIdentity? {
        guard let appleUserID, !appleUserID.isEmpty else { return nil }
        return storedIdentities()[appleUserID]
    }

    /// Called once the capture has reached the climber's profile, or once the
    /// profile turns out to carry a name already.
    func forget(appleUserID: String) {
        var stored = storedIdentities()
        guard stored.removeValue(forKey: appleUserID) != nil else { return }
        save(stored)
    }

    private func storedIdentities() -> [String: AppleSignInSuppliedIdentity] {
        guard let data = userDefaults.data(forKey: Keys.suppliedIdentities),
              let decoded = try? JSONDecoder().decode(
                  [String: AppleSignInSuppliedIdentity].self,
                  from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private func save(_ identities: [String: AppleSignInSuppliedIdentity]) {
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
