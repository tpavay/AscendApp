import Foundation
import Testing
@testable import AscendApp

/// Apple supplies the name once, on the first authorization, and never again.
/// So the capture has to survive everything that happens between that moment and
/// the profile write landing: a failed write, a relaunch, a sign-out.
@MainActor
struct AppleSignInIdentityStoreTests {
    @Test
    func aCaptureSurvivesToTheNextLaunch() {
        let defaults = makeDefaults()
        let appleUserID = "000123.apple"

        AppleSignInIdentityStore(userDefaults: defaults).record(
            AppleSignInSuppliedIdentity(
                appleUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: "8xk2p9qz7t@privaterelay.appleid.com"
            )
        )

        // A fresh store is what the next launch builds.
        let relaunched = AppleSignInIdentityStore(userDefaults: defaults)
        let restored = relaunched.identity(forAppleUserID: appleUserID)

        #expect(restored?.firstName == "Maya")
        #expect(restored?.lastName == "Chen")
        #expect(restored?.email == "8xk2p9qz7t@privaterelay.appleid.com")
    }

    /// The returning sign-in that follows a failed write hands back nothing.
    /// Recording it must not blank the stored copy.
    @Test
    func aReturningAuthorizationCannotBlankTheStoredCapture() {
        let defaults = makeDefaults()
        let store = AppleSignInIdentityStore(userDefaults: defaults)
        let appleUserID = "000123.apple"

        store.record(
            AppleSignInSuppliedIdentity(
                appleUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: "maya@example.com"
            )
        )
        store.record(
            AppleSignInSuppliedIdentity(
                appleUserID: appleUserID,
                firstName: nil,
                lastName: nil,
                email: nil
            )
        )

        #expect(store.identity(forAppleUserID: appleUserID)?.firstName == "Maya")
        #expect(store.identity(forAppleUserID: appleUserID)?.lastName == "Chen")
        #expect(store.identity(forAppleUserID: appleUserID)?.email == "maya@example.com")
    }

    @Test
    func anAuthorizationThatSuppliedNothingStoresNothing() {
        let defaults = makeDefaults()
        let store = AppleSignInIdentityStore(userDefaults: defaults)

        store.record(
            AppleSignInSuppliedIdentity(
                appleUserID: "000123.apple",
                firstName: nil,
                lastName: nil,
                email: nil
            )
        )

        #expect(store.identity(forAppleUserID: "000123.apple") == nil)
    }

    @Test
    func aCaptureIsForgottenOnceItHasReachedTheProfile() {
        let defaults = makeDefaults()
        let store = AppleSignInIdentityStore(userDefaults: defaults)
        let appleUserID = "000123.apple"

        store.record(
            AppleSignInSuppliedIdentity(
                appleUserID: appleUserID,
                firstName: "Maya",
                lastName: "Chen",
                email: nil
            )
        )
        store.forget(appleUserID: appleUserID)

        #expect(store.identity(forAppleUserID: appleUserID) == nil)
        #expect(AppleSignInIdentityStore(userDefaults: defaults)
            .identity(forAppleUserID: appleUserID) == nil)
    }

    @Test
    func oneAppleIDsCaptureIsNeverHandedToAnother() {
        let defaults = makeDefaults()
        let store = AppleSignInIdentityStore(userDefaults: defaults)

        store.record(
            AppleSignInSuppliedIdentity(
                appleUserID: "000123.apple",
                firstName: "Maya",
                lastName: "Chen",
                email: nil
            )
        )

        #expect(store.identity(forAppleUserID: "000999.apple") == nil)
        #expect(store.identity(forAppleUserID: nil) == nil)
        #expect(store.identity(forAppleUserID: "") == nil)
    }

    /// Captures that never reach a profile would otherwise accumulate for the
    /// life of the install. The newest are the ones still worth holding.
    @Test
    func staleCapturesDoNotAccumulateForever() {
        let defaults = makeDefaults()
        let store = AppleSignInIdentityStore(userDefaults: defaults)

        for index in 0..<8 {
            store.record(
                AppleSignInSuppliedIdentity(
                    appleUserID: "id-\(index).apple",
                    firstName: "Climber\(index)",
                    lastName: "Chen",
                    email: nil,
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index) * 100)
                )
            )
        }

        #expect(store.identity(forAppleUserID: "id-7.apple")?.firstName == "Climber7")
        #expect(store.identity(forAppleUserID: "id-0.apple") == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppleSignInIdentityStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
