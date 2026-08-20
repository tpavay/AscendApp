import Foundation
import Testing
@testable import AscendApp

/// Apple supplies the name once, on the first authorization, and never again.
/// So the capture has to survive everything that happens between that moment and
/// the profile write landing: a failed write, a relaunch, a sign-out.
@MainActor
struct SignInIdentityStoreTests {
    @Test
    func aCaptureSurvivesToTheNextLaunch() {
        let defaults = makeDefaults()
        let appleUserID = "000123.apple"

        SignInIdentityStore(userDefaults: defaults).record(
            SignInSuppliedIdentity(
                providerUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: "8xk2p9qz7t@privaterelay.appleid.com"
            )
        )

        // A fresh store is what the next launch builds.
        let relaunched = SignInIdentityStore(userDefaults: defaults)
        let restored = relaunched.identity(forProviderUserID: appleUserID)

        #expect(restored?.firstName == "Maya")
        #expect(restored?.lastName == "Chen")
        #expect(restored?.email == "8xk2p9qz7t@privaterelay.appleid.com")
    }

    /// The returning sign-in that follows a failed write hands back nothing.
    /// Recording it must not blank the stored copy.
    @Test
    func aReturningAuthorizationCannotBlankTheStoredCapture() {
        let defaults = makeDefaults()
        let store = SignInIdentityStore(userDefaults: defaults)
        let appleUserID = "000123.apple"

        store.record(
            SignInSuppliedIdentity(
                providerUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: "maya@example.com"
            )
        )
        store.record(
            SignInSuppliedIdentity(
                providerUserID: appleUserID,
                firstName: nil,
                lastName: nil,
                email: nil
            )
        )

        #expect(store.identity(forProviderUserID: appleUserID)?.firstName == "Maya")
        #expect(store.identity(forProviderUserID: appleUserID)?.lastName == "Chen")
        #expect(store.identity(forProviderUserID: appleUserID)?.email == "maya@example.com")
    }

    @Test
    func anAuthorizationThatSuppliedNothingStoresNothing() {
        let defaults = makeDefaults()
        let store = SignInIdentityStore(userDefaults: defaults)

        store.record(
            SignInSuppliedIdentity(
                providerUserID: "000123.apple",
                firstName: nil,
                lastName: nil,
                email: nil
            )
        )

        #expect(store.identity(forProviderUserID: "000123.apple") == nil)
    }

    @Test
    func aCaptureIsForgottenOnceItHasReachedTheProfile() {
        let defaults = makeDefaults()
        let store = SignInIdentityStore(userDefaults: defaults)
        let appleUserID = "000123.apple"

        store.record(
            SignInSuppliedIdentity(
                providerUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: nil
            )
        )
        store.forget(providerUserID: appleUserID)

        #expect(store.identity(forProviderUserID: appleUserID) == nil)
        #expect(SignInIdentityStore(userDefaults: defaults)
            .identity(forProviderUserID: appleUserID) == nil)
    }

    @Test
    func oneAppleIDsCaptureIsNeverHandedToAnother() {
        let defaults = makeDefaults()
        let store = SignInIdentityStore(userDefaults: defaults)

        store.record(
            SignInSuppliedIdentity(
                providerUserID: "000123.apple",
                firstName: "Maya",
                lastName: "Chen",
                email: nil
            )
        )

        #expect(store.identity(forProviderUserID: "000999.apple") == nil)
        #expect(store.identity(forProviderUserID: nil) == nil)
        #expect(store.identity(forProviderUserID: "") == nil)
    }

    /// Captures that never reach a profile would otherwise accumulate for the
    /// life of the install. The newest are the ones still worth holding.
    @Test
    func staleCapturesDoNotAccumulateForever() {
        let defaults = makeDefaults()
        let store = SignInIdentityStore(userDefaults: defaults)

        for index in 0..<8 {
            store.record(
                SignInSuppliedIdentity(
                    providerUserID: "id-\(index).apple",
                    firstName: "Climber\(index)",
                    lastName: "Chen",
                    email: nil,
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index) * 100)
                )
            )
        }

        #expect(store.identity(forProviderUserID: "id-7.apple")?.firstName == "Climber7")
        #expect(store.identity(forProviderUserID: "id-0.apple") == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SignInIdentityStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
