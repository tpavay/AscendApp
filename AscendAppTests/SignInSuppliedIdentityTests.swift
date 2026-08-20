import Foundation
import Testing
@testable import AscendApp

/// Guideline 4 rejection, 2026-08-20: the 1.0 build asked every Sign in with
/// Apple climber to type a name Authentication Services was never even asked for.
/// `AuthenticationService.appleRequestedScopes` omitted `.fullName`, so
/// `ASAuthorizationAppleIDCredential.fullName` was always nil and the name step
/// ran unconditionally.
///
/// These hold the shapes Apple actually returns - a first authorization with a
/// name, a first authorization with Hide My Email, a returning sign-in where both
/// come back nil, and a climber who declined to share a name - and the shape
/// Google returns, because the rule is one rule. Google supplies a display name
/// too, so asking a Google climber to retype it is exactly as redundant, and a
/// second per-provider branch is a second thing to drift.
struct SignInSuppliedIdentityTests {
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
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "maya@example.com"
        )

        #expect(supplied.adoptableName?.firstName == "Maya")
        #expect(supplied.adoptableName?.lastName == "Chen")
        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )
    }

    /// Apple hands the name through `PersonNameComponents`, which carries no
    /// promise about whitespace or line breaks. The board name is composed from
    /// these halves, so they are normalized on the way in rather than at the
    /// point of publication.
    @Test
    func suppliedNamePartsAreTrimmedAndFlattenedToASingleLine() {
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
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
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: String(repeating: "A", count: DisplayNamePolicy.maximumLength),
            lastName: "Chen",
            email: nil
        )

        #expect(supplied.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - First authorization, Hide My Email

    @Test
    func hideMyEmailRelayAddressIsAcceptedLikeAnyOtherAddress() {
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000456.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "8xk2p9qz7t@privaterelay.appleid.com"
        )

        #expect(supplied.email == "8xk2p9qz7t@privaterelay.appleid.com")
        #expect(supplied.carriesSomething)
        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )
    }

    // MARK: - Returning sign-in, Apple returns nil for both

    @Test
    func returningSignInCarriesNothingAndAsksForNothing() {
        let returning = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
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
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: nil
        )

        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .present)
                == .discard
        )
    }

    /// An existing account created before this fix must not be re-prompted or
    /// rewritten. It has no capture at all, so nothing here reaches it.
    @Test
    func anAccountFromBeforeThisFixIsLeftCompletelyAlone() {
        #expect(
            SuppliedNameAdoption.decide(supplied: nil, storedName: .present)
                == .askTheClimber
        )
        #expect(
            SuppliedNameAdoption.decide(supplied: nil, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - Declined to share a name

    /// Apple's requirement is that the app not demand what the framework already
    /// gave it - not that a name can never be asked for. A climber who shared
    /// nothing is still asked, because nothing was supplied to reuse.
    @Test
    func aClimberWhoDeclinedToShareANameIsStillAsked() {
        let declined = SignInSuppliedIdentity(
            providerUserID: "000789.apple",
            firstName: nil,
            lastName: nil,
            email: "maya@example.com"
        )

        #expect(declined.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: declined, storedName: .absent)
                == .askTheClimber
        )
    }

    /// Ascend's board name needs both halves. A climber who cleared one of them
    /// in Apple's sheet is asked for the half they withheld, and the retained
    /// half is what seeds the field they are not asked to retype.
    @Test
    func onlyTheWithheldHalfIsEverAskedForAgain() {
        let halfShared = SignInSuppliedIdentity(
            providerUserID: "000789.apple",
            firstName: "Maya",
            lastName: nil,
            email: nil
        )

        #expect(halfShared.firstName == "Maya")
        #expect(halfShared.lastName == nil)
        #expect(halfShared.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: halfShared, storedName: .absent)
                == .askTheClimber
        )
    }

    // MARK: - Never lose what Apple supplied

    /// A read that failed says nothing about whether the profile has a name, and
    /// guessing would overwrite one. The capture survives for the next sign-in.
    @Test
    func anUnreadableProfileDefersRatherThanGuesses() {
        let supplied = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: nil
        )

        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .unreadable)
                == .retryLater
        )
    }

    /// Every authorization after the first returns nil for everything. Merging
    /// that over the stored capture would erase the only copy in existence.
    @Test
    func aLaterNilAuthorizationCannotEraseWhatTheFirstOneGave() {
        let first = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: "Maya",
            lastName: "Chen",
            email: "maya@example.com",
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let returning = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
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
        let other = SignInSuppliedIdentity(
            providerUserID: "000999.apple",
            firstName: "Someone",
            lastName: "Else",
            email: "someone@example.com"
        )
        let fresh = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: nil,
            lastName: nil,
            email: nil
        )

        let merged = fresh.mergingRetainedValues(from: other)

        #expect(merged.firstName == nil)
        #expect(merged.lastName == nil)
        #expect(merged.email == nil)
    }

    // MARK: - Google, through the same rule

    /// Google hands Firebase one string. It splits into the two halves Ascend's
    /// board name needs and reaches the identical decision Apple's credential
    /// does - there is no `if provider == .apple` anywhere on this path.
    @Test
    func aGoogleDisplayNameIsAdoptedByTheSameRuleAsApples() {
        let google = SignInSuppliedIdentity(
            providerUserID: "google-uid",
            fullName: "Maya Chen",
            email: "maya@gmail.com"
        )

        #expect(google.firstName == "Maya")
        #expect(google.lastName == "Chen")
        #expect(google.email == "maya@gmail.com")
        #expect(
            SuppliedNameAdoption.decide(supplied: google, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )
    }

    /// A family name of more than one word survives whole. Splitting on the LAST
    /// space instead would file "Maya Van Der Berg" under the surname "Berg".
    @Test
    func aMultiWordFamilyNameSurvivesTheSplit() {
        let google = SignInSuppliedIdentity(
            providerUserID: "google-uid",
            fullName: "  Maya   Van Der Berg ",
            email: nil
        )

        #expect(google.firstName == "Maya")
        #expect(google.lastName == "Van Der Berg")
        #expect(
            SuppliedNameAdoption.decide(supplied: google, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Van Der Berg")
        )
    }

    /// One word is half a name, and half a name is treated the same whoever
    /// supplied it: the climber is asked for the half that is missing, with the
    /// half they gave already in the field.
    @Test
    func aOneWordProviderNameIsTreatedAsHalfANameNotAWholeOne() {
        let google = SignInSuppliedIdentity(
            providerUserID: "google-uid",
            fullName: "Maya",
            email: nil
        )

        #expect(google.firstName == "Maya")
        #expect(google.lastName == nil)
        #expect(google.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: google, storedName: .absent)
                == .askTheClimber
        )
    }

    /// A provider that supplied nothing at all is not a value worth holding, so
    /// the account-derived read yields nothing rather than an empty identity that
    /// would look like a capture.
    @Test
    func anAccountWithNoNameAndNoEmailCarriesNothing() {
        let empty = SignInSuppliedIdentity(
            providerUserID: "google-uid",
            fullName: nil,
            email: nil
        )

        #expect(!empty.carriesSomething)
        #expect(empty.adoptableName == nil)
    }

    // MARK: - Resolution step 1: the profile Ascend already has

    /// Delete-and-reinstall. Apple has already spent its one first authorization
    /// on this Apple ID, so the credential is empty - but Ascend still knows the
    /// climber, and the name it already holds wins over everything below it. The
    /// placeholder is never reached, so it is never applied.
    @Test
    func aReinstallingClimberKeepsTheNameAscendAlreadyHas() {
        let nothingFromApple = SignInSuppliedIdentity(
            providerUserID: "000123.apple",
            firstName: nil,
            lastName: nil,
            email: nil
        )

        #expect(
            SuppliedNameAdoption.decide(supplied: nothingFromApple, storedName: .present)
                == .discard,
            "an existing profile name is resolution step 1 and outranks both steps below it"
        )
        #expect(
            SuppliedNameAdoption.decide(supplied: nil, storedName: .present)
                == .askTheClimber,
            "no capture at all leaves the stored profile completely untouched"
        )

        // And with a name on the profile the stage is completed without ever
        // rendering, so the placeholder has nothing to overwrite.
        #expect(SignInNamePlaceholder.boardName == "CHANGE ME")
    }
}
