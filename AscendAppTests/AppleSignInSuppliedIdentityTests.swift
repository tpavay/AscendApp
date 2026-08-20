import Foundation
import Testing
@testable import AscendApp

/// Guideline 4 rejection, 2026-08-20: the 1.0 build asked every Sign in with
/// Apple climber to type a name Authentication Services was never even asked for.
/// `AuthenticationService.appleRequestedScopes` omitted `.fullName`, so
/// `ASAuthorizationAppleIDCredential.fullName` was always nil and the name step
/// ran unconditionally.
///
/// These hold the four shapes Apple actually returns: a first authorization with
/// a name, a first authorization with Hide My Email, a returning sign-in where
/// both come back nil, and a climber who declined to share a name.
struct AppleSignInSuppliedIdentityTests {
    /// The whole defect in one assertion: the request has to ask for the name,
    /// or every branch below is unreachable in production.
    @MainActor
    @Test
    func appleAuthorizationRequestsBothTheNameAndTheEmail() {
        #expect(AuthenticationService.appleRequestedScopes.contains(.fullName))
        #expect(AuthenticationService.appleRequestedScopes.contains(.email))
    }

    // MARK: - First authorization, name shared

    @Test
    func firstAuthorizationWithANameIsWrittenAndTheNameStepNeverRuns() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "maya@example.com"
        )

        #expect(supplied.adoptableName?.firstName == "Maya")
        #expect(supplied.adoptableName?.lastName == "Chen")
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )
    }

    /// Apple hands the name through `PersonNameComponents`, which carries no
    /// promise about whitespace or line breaks. The board name is composed from
    /// these halves, so they are normalized on the way in rather than at the
    /// point of publication.
    @Test
    func suppliedNamePartsAreTrimmedAndFlattenedToASingleLine() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: "  Maya\n",
            lastName: "\rChen  ",
            email: "  maya@example.com "
        )

        #expect(supplied.firstName == "Maya")
        #expect(supplied.lastName == "Chen")
        #expect(supplied.email == "maya@example.com")
    }

    @Test
    func aNameTooLongToPublishIsNotWrittenBehindTheClimbersBack() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: String(repeating: "A", count: DisplayNamePolicy.maximumLength),
            lastName: "Chen",
            email: nil
        )

        #expect(supplied.adoptableName == nil)
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - First authorization, Hide My Email

    @Test
    func hideMyEmailRelayAddressIsAcceptedLikeAnyOtherAddress() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000456.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "8xk2p9qz7t@privaterelay.appleid.com"
        )

        #expect(supplied.email == "8xk2p9qz7t@privaterelay.appleid.com")
        #expect(supplied.carriesSomething)
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )
    }

    // MARK: - Returning sign-in, Apple returns nil for both

    @Test
    func returningSignInCarriesNothingAndAsksForNothing() {
        let returning = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: nil,
            lastName: nil,
            email: nil
        )

        #expect(!returning.carriesSomething)
        #expect(returning.adoptableName == nil)
    }

    /// The account already has a name, so nothing is re-asked and nothing is
    /// overwritten - the capture is simply dropped.
    @Test
    func aProfileThatAlreadyCarriesANameKeepsIt() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: nil
        )

        #expect(
            AppleSuppliedNameAdoption.decide(supplied: supplied, storedName: .present)
                == .discard
        )
    }

    /// An existing account created before this fix must not be re-prompted or
    /// rewritten. It has no capture at all, so nothing here reaches it.
    @Test
    func anAccountFromBeforeThisFixIsLeftCompletelyAlone() {
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: nil, storedName: .present)
                == .askTheClimber
        )
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: nil, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - Declined to share a name

    /// Apple's requirement is that the app not demand what the framework already
    /// gave it - not that a name can never be asked for. A climber who shared
    /// nothing is still asked, because nothing was supplied to reuse.
    @Test
    func aClimberWhoDeclinedToShareANameIsStillAsked() {
        let declined = AppleSignInSuppliedIdentity(
            appleUserID: "000789.apple",
            firstName: nil,
            lastName: nil,
            email: "maya@example.com"
        )

        #expect(declined.adoptableName == nil)
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: declined, storedName: .absent)
                == .askTheClimber
        )
    }

    /// Ascend's board name needs both halves. A climber who cleared one of them
    /// in Apple's sheet is asked for the half they withheld, and the retained
    /// half is what seeds the field they are not asked to retype.
    @Test
    func onlyTheWithheldHalfIsEverAskedForAgain() {
        let halfShared = AppleSignInSuppliedIdentity(
            appleUserID: "000789.apple",
            firstName: "Maya",
            lastName: nil,
            email: nil
        )

        #expect(halfShared.firstName == "Maya")
        #expect(halfShared.lastName == nil)
        #expect(halfShared.adoptableName == nil)
        #expect(
            AppleSuppliedNameAdoption.decide(supplied: halfShared, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - Never lose what Apple supplied

    /// A read that failed says nothing about whether the profile has a name, and
    /// guessing would overwrite one. The capture survives for the next sign-in.
    @Test
    func anUnreadableProfileDefersRatherThanGuesses() {
        let supplied = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: nil
        )

        #expect(
            AppleSuppliedNameAdoption.decide(supplied: supplied, storedName: .unreadable)
                == .retryLater
        )
    }

    /// Every authorization after the first returns nil for everything. Merging
    /// that over the stored capture would erase the only copy in existence.
    @Test
    func aLaterNilAuthorizationCannotEraseWhatTheFirstOneGave() {
        let first = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "maya@example.com",
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let returning = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: nil,
            lastName: nil,
            email: nil,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )

        let merged = returning.mergingRetainedValues(from: first)

        #expect(merged.firstName == "Maya")
        #expect(merged.lastName == "Chen")
        #expect(merged.email == "maya@example.com")
    }

    @Test
    func aCaptureForADifferentAppleIDIsNeverMergedIn() {
        let other = AppleSignInSuppliedIdentity(
            appleUserID: "000999.apple",
            firstName: "Someone",
            lastName: "Else",
            email: "someone@example.com"
        )
        let fresh = AppleSignInSuppliedIdentity(
            appleUserID: "000123.apple",
            firstName: nil,
            lastName: nil,
            email: nil
        )

        let merged = fresh.mergingRetainedValues(from: other)

        #expect(merged.firstName == nil)
        #expect(merged.lastName == nil)
        #expect(merged.email == nil)
    }
}
