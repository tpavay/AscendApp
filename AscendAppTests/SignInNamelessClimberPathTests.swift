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
/// Requesting `.fullName`, persisting it, and skipping the step when a name
/// exists are the minimum that passes on a clean device. They do nothing here.
/// Two teams shipped exactly that and were rejected a second time
/// (Apple Developer Forums thread 712464). What has to be true is that a climber
/// nobody supplied a name for still reaches the app.
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
    func theReviewersCredentialCarriesNothingToPrefillOrAdopt() {
        #expect(!reviewerCredential.carriesSomething)
        #expect(reviewerCredential.adoptableName == nil)
        #expect(
            SuppliedNameAdoption.decide(supplied: reviewerCredential, storedName: .absent)
                == .askTheClimber
        )
    }

    /// Resolution step 3. The placeholder has to be a name the client policy AND
    /// the Cloud Functions screen both accept, or the write is denied and the
    /// climber is stuck on the screen anyway - the rejection all over again with
    /// an extra step.
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

    /// Ascend's board name needs both halves, so a climber nobody supplied a name
    /// for cannot compose one. That must not read as a failure they have to
    /// resolve before they can continue - which is exactly why the step carries a
    /// skip rather than relying on CONTINUE ever becoming live.
    @Test
    func aNamelessClimberCannotComposeABoardNameAndMustNotHaveTo() {
        var input = PostAuthNameInput()
        #expect(!input.canContinue)

        input.firstName = "Maya"
        #expect(!input.canContinue, "half a name still composes nothing")

        #expect(
            DisplayNamePolicy.composesAllowedBoardName(
                firstName: SignInNamePlaceholder.firstName,
                lastName: SignInNamePlaceholder.lastName
            ),
            "the way past cannot itself be blocked by the policy"
        )
    }

    /// Once the placeholder is on the profile, the ordinary skip path advances
    /// the stage with nothing typed, and the stage is marked done so it never
    /// returns.
    @MainActor
    @Test
    func skippingAdvancesPastTheNameStageForGood() {
        let suiteName = "SignInNamelessClimberPathTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: "reviewer")
        #expect(coordinator.phase == .onboarding(.displayName))

        coordinator.completeCurrentStage()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(store.snapshot(for: "reviewer").completedStages.contains(.displayName))

        // A relaunch resumes past it rather than re-asking.
        let relaunched = PostAuthOnboardingCoordinator(store: store)
        relaunched.resolve(userId: "reviewer")
        #expect(relaunched.phase == .onboarding(.stairStepperBaseline))
    }
}
