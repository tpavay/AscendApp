import Foundation
import Testing
@testable import AscendApp

/// The path App Review actually walks.
///
/// Apple populates `fullName` on the FIRST authorization for an Apple ID and app
/// pair and never again. App Review's device has almost certainly already spent
/// that first authorization on Ascend - TestFlight, the rejected submission, the
/// same reviewer Apple ID - so the reviewer's credential carries NOTHING.
///
/// Requesting `.fullName`, persisting it, and prefilling a name step from it are
/// the minimum that passes on a clean device. They do nothing here. Two teams
/// shipped exactly that and were rejected a second time (Apple Developer Forums
/// thread 712464). What has to be true is that a climber nobody supplied a name
/// for reaches the app without being asked for one - which is why there is no
/// name step left to reach.
struct SignInNamelessClimberPathTests {
    /// The reviewer's credential: a returning authorization, everything nil.
    private var reviewerCredential: SignInSuppliedIdentity {
        SignInSuppliedIdentity(
            providerUserID: "000123.reviewer",
            firstName: nil,
            lastName: nil,
            email: nil
        )
    }

    @Test
    func theReviewersCredentialResolvesToThePlaceholderRatherThanAQuestion() {
        #expect(!reviewerCredential.carriesSomething)
        #expect(reviewerCredential.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: reviewerCredential, storedName: .absent)
                == .writePlaceholder
        )
    }

    /// No capture at all - a climber signing in on a device that never saw
    /// Apple's one-and-only credential - resolves the same way. There is no
    /// branch here that ends in a screen.
    @Test
    func noCaptureAtAllStillResolvesToAName() {
        #expect(
            SuppliedNameAdoption.decide(supplied: nil, storedName: .absent)
                == .writePlaceholder
        )
    }

    /// The rejection in one assertion: every reachable combination of what a
    /// provider supplied and what the profile holds terminates in a name or in a
    /// deliberate retry. None of them terminates in a question.
    @Test
    func everyResolutionTerminatesWithoutAskingTheClimber() {
        let supplied: [SignInSuppliedIdentity?] = [
            nil,
            reviewerCredential,
            SignInSuppliedIdentity(
                providerUserID: "p",
                firstName: "Maya",
                lastName: nil,
                email: nil
            ),
            SignInSuppliedIdentity(
                providerUserID: "p",
                firstName: "Maya",
                lastName: "Chen",
                email: nil
            )
        ]

        for identity in supplied {
            for storedName in [StoredProfileName.absent, .present, .unreadable] {
                let decision = SuppliedNameAdoption.decide(
                    supplied: identity,
                    storedName: storedName
                )

                switch decision {
                case .write, .writePlaceholder, .discard, .retryLater:
                    // `.retryLater` is the only one that does not end in a name,
                    // and it is reached solely when the profile could not be READ
                    // - it retries on the next launch rather than asking.
                    break
                }
            }
        }

        // A profile that could not be read is the only deferral, and it never
        // depends on what the provider supplied.
        for identity in supplied {
            #expect(
                SuppliedNameAdoption.decide(supplied: identity, storedName: .unreadable)
                    == .retryLater
            )
        }
    }

    /// Resolution step 3. The placeholder has to be a name the client policy AND
    /// the Cloud Functions screen both accept, or the write is denied and the
    /// climber ends up nameless - which is now the only failure mode left, since
    /// there is no screen to fall back to.
    @Test
    func thePlaceholderIsPublishable() {
        #expect(SignInNamePlaceholder.firstName == "CHANGE")
        #expect(SignInNamePlaceholder.lastName == "ME")
        #expect(SignInNamePlaceholder.boardName == "CHANGE ME")

        #expect(
            DisplayNamePolicy.composesAllowedBoardName(
                firstName: SignInNamePlaceholder.firstName,
                lastName: SignInNamePlaceholder.lastName
            ),
            "the display-name policy rejected the placeholder"
        )
        #expect(
            (try? DisplayNamePolicy.composedBoardName(
                firstName: SignInNamePlaceholder.firstName,
                lastName: SignInNamePlaceholder.lastName
            )) == SignInNamePlaceholder.boardName
        )
    }

    /// It is an instruction, not a plausible name. A climber who opens their own
    /// profile has to be able to tell that nothing was ever set - which a
    /// generated handle cannot tell them - and it must not collide with the
    /// reserved deleted-account sentinel, which both screens refuse.
    @Test
    func thePlaceholderReadsAsAnInstructionAndIsNotTheDeletedAccountSentinel() {
        #expect(SignInNamePlaceholder.boardName != PublicClimberIdentity.anonymousDisplayName)
        #expect(!DisplayNamePolicy.isAllowed(PublicClimberIdentity.anonymousDisplayName))
        #expect(SignInNamePlaceholder.boardName == SignInNamePlaceholder.boardName.uppercased())
    }

    /// Half a name is not a board name and there is no longer anywhere to ask for
    /// the other half, so it resolves to the placeholder like any other
    /// unpublishable answer. Deliberate: "Maya ME" would read as a real surname,
    /// where "CHANGE ME" reads as the instruction it is.
    @Test
    func halfANameResolvesToThePlaceholderRatherThanHalfAPlaceholder() {
        let halfShared = SignInSuppliedIdentity(
            providerUserID: "000789.apple",
            firstName: "Maya",
            lastName: nil,
            email: nil
        )

        #expect(
            SuppliedNameAdoption.decide(supplied: halfShared, storedName: .absent)
                == .writePlaceholder
        )
    }

    /// Onboarding opens on the first survey question, not on a name. The stage
    /// the rejection was about is gone from the flow entirely.
    @MainActor
    @Test
    func onboardingOpensWithoutEverAskingForAName() {
        let suiteName = "SignInNamelessClimberPathTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: "reviewer")

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!PostAuthOnboardingStage.allCases.contains { $0.rawValue == "displayName" })
    }
}
