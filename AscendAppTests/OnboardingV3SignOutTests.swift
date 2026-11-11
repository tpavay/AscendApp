import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// One phone across launches: the preferences and the photo folder outlive the process, and each
/// launch builds a coordinator and a latch over them the way the root does.
@MainActor
private struct SignOutDevice {
    let defaults: UserDefaults
    let photos: OnboardingProfilePhotoStore

    init() throws {
        let suite = "onboarding-v3-sign-out-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let directory = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.defaults = defaults
        photos = OnboardingProfilePhotoStore(directory: directory)
    }

    var store: PreAuthOnboardingStore { PreAuthOnboardingStore(userDefaults: defaults) }

    /// A cold launch. `switchAnswer` is what the backend last told this device about
    /// `onboarding_v3_enabled`, or `nil` for a device it has never answered.
    func launch(signedIn: Bool, switchAnswer: Bool? = true) -> SignOutLaunch {
        let flags = switchAnswer.map { answer in
            RemoteFeatureFlagStore(snapshot: .resolving(remoteValues: [RemoteFeatureFlag.onboardingV3.key: answer]))
        } ?? RemoteFeatureFlagStore()
        let launch = SignOutLaunch(
            coordinator: OnboardingV3Coordinator(
                store: store,
                photos: photos,
                now: everyTapAfterTheTransition()
            ),
            latch: OnboardingV3RouteLatch(store: flags, firstFetch: {}, holdLimit: .seconds(600))
        )
        // What the root's first task does before anything is routed.
        if !signedIn { launch.coordinator.launchedSignedOut() }
        return launch
    }
}

/// What the root holds for one process, resolved through the same resolver from the same input.
@MainActor
private struct SignOutLaunch {
    let coordinator: OnboardingV3Coordinator
    let latch: OnboardingV3RouteLatch

    func route(_ state: AuthenticationState, userId: String? = nil) -> AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: state,
            userId: userId,
            postAuthOnboardingPhase: .complete,
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            showsPreAuthOnboardingV3: latch.showsFlow
        )
    }

    /// Walks the setup screens to sign-in, answering as it goes, then signs in at the end.
    func walkTheFlowAndSignIn() {
        coordinator.update {
            $0.firstName = "Tyler"
            $0.weeklyTargetDays = 4
            $0.usualClimbSteps = 1_800
        }
        while coordinator.step.primaryDestination != nil {
            coordinator.advance()
        }
        // The root, the moment the account appears.
        coordinator.sessionBegan()
        coordinator.finish()
    }
}

/// Signing out with `onboarding_v3_enabled` on.
///
/// The report this exists for, on a staging phone on 2026-11-11: the captain finished the v3
/// onboarding, signed in, signed out from Settings and was shown the onboarding the switch
/// replaced - the old landing screen, "Get fit with the stair stepper" behind Get Started, the old
/// sign-in behind Sign In - and closing and reopening the app showed it again. The pass he had
/// finished was read as "the signed-out screens are over", and it was kept across sign-out and
/// across launches, so the route fell through to the landing screen for good.
@MainActor
struct OnboardingV3SignOutTests {
    // MARK: - The reproduction

    @Test("Signing out after finishing the v3 flow returns to its Welcome, never the old landing")
    func signingOutAfterAFinishedPassRoutesBackToTheFlow() throws {
        let device = try SignOutDevice()
        let launch = device.launch(signedIn: false)
        #expect(launch.route(.unauthenticated) == .preAuthOnboarding)

        launch.walkTheFlowAndSignIn()
        #expect(launch.route(.authenticated, userId: "captain") == .paywall)

        // Sign out, from Settings.
        launch.coordinator.sessionEnded()

        #expect(launch.route(.unauthenticated) == .preAuthOnboarding)
        #expect(launch.coordinator.step == .welcome)
        #expect(!launch.coordinator.canGoBack, "nothing behind Welcome leads back into the last climber's pass")
    }

    @Test("Closing and reopening the app after that sign-out still opens the v3 flow")
    func aRelaunchAfterSigningOutStillRoutesToTheFlow() throws {
        let device = try SignOutDevice()
        let first = device.launch(signedIn: false)
        first.walkTheFlowAndSignIn()
        first.coordinator.sessionEnded()

        let relaunch = device.launch(signedIn: false)

        #expect(relaunch.route(.unauthenticated) == .preAuthOnboarding)
        #expect(relaunch.coordinator.step == .welcome)
    }

    /// The phone the report came from: it signed out on a build that kept the finished pass, so the
    /// pass is still on the device when the fixed build first launches.
    @Test("A finished pass an earlier build left behind neither hides the flow nor survives the launch")
    func aFinishedPassLeftOnASignedOutDeviceIsDiscardedAtLaunch() throws {
        let device = try SignOutDevice()
        device.store.update {
            $0.completedAt = Date(timeIntervalSinceReferenceDate: 816_113_420)
            $0.weeklyTargetDays = 4
            $0.notificationChoice = .skipped
        }

        let launch = device.launch(signedIn: false)

        #expect(launch.route(.unauthenticated) == .preAuthOnboarding)
        #expect(!launch.coordinator.isFinished)
        #expect(launch.coordinator.answers == PreAuthOnboardingAnswers())
        #expect(device.store.answers() == PreAuthOnboardingAnswers())
    }

    // MARK: - What a sign-out clears

    @Test
    func signingOutClearsTheStoreThePhotoAndTheLiveCopy() throws {
        let device = try SignOutDevice()
        let photo = try #require(device.photos.save(try Self.jpegData()))
        let launch = device.launch(signedIn: false)
        launch.coordinator.update {
            $0.profilePhotoFileName = photo
            $0.gender = .man
            $0.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["w1"], knownSteps: 2_000))
        }
        launch.walkTheFlowAndSignIn()
        #expect(device.store.answers().completedAt != nil)

        launch.coordinator.sessionEnded()

        #expect(device.defaults.object(forKey: PreAuthOnboardingStore.storageKey) == nil)
        #expect(device.store.answers() == PreAuthOnboardingAnswers())
        #expect(launch.coordinator.answers == PreAuthOnboardingAnswers())
        #expect(!launch.coordinator.isFinished)
        #expect(device.photos.url(for: photo) == nil)
    }

    @Test
    func theNextClimberOnThePhoneSignsInThroughWelcomesReturningLinkNotTheSetupScreens() throws {
        let device = try SignOutDevice()
        let launch = device.launch(signedIn: false)
        launch.walkTheFlowAndSignIn()
        launch.coordinator.sessionEnded()

        let signIn = try #require(OnboardingV3Step.welcome.alternateExits.first)
        launch.coordinator.go(to: signIn.destination)

        #expect(launch.coordinator.step == .auth)
        #expect(OnboardingAuthMode(arrivedFrom: launch.coordinator.previousStep) == .returning)
    }

    /// The flow goes back to Welcome when the account appears, while no route shows it, so the
    /// sign-out that follows has nothing to move on a screen that is on its way in.
    @Test
    func theFlowIsAlreadyAtWelcomeBeforeTheSignOutThatShowsItAgain() throws {
        let launch = try SignOutDevice().launch(signedIn: false)
        launch.coordinator.go(to: .auth)

        launch.coordinator.sessionBegan()

        #expect(launch.coordinator.step == .welcome)
        #expect(!launch.coordinator.canGoBack)
    }

    // MARK: - What a launch keeps

    @Test
    func aClimberPartwayThroughTheFlowKeepsTheirAnswersAcrossARelaunch() throws {
        let device = try SignOutDevice()
        device.store.update {
            $0.gender = .woman
            $0.weeklyTargetDays = 3
        }

        let launch = device.launch(signedIn: false)

        #expect(launch.coordinator.answers.gender == .woman)
        #expect(device.store.answers().weeklyTargetDays == 3)
    }

    /// Answers a switched-off or unreachable profile write left behind are still that climber's on
    /// the next launch, and the hand-off still has them to deliver.
    @Test
    func aFinishedPassStaysWhileItsClimberIsStillSignedIn() throws {
        let device = try SignOutDevice()
        let finishedAt = Date(timeIntervalSinceReferenceDate: 816_113_420)
        device.store.update {
            $0.completedAt = finishedAt
            $0.gender = .man
            $0.weeklyTargetDays = 4
        }

        let launch = device.launch(signedIn: true)

        #expect(launch.coordinator.isFinished)
        #expect(device.store.answers().completedAt == finishedAt)
        #expect(device.store.answers().gender == .man)
        #expect(device.store.answers().weeklyTargetDays == 4)
    }

    // MARK: - The route

    private static let everyAuthenticationState: [AuthenticationState] = [
        .unauthenticated,
        .authenticatingWithApple,
        .authenticatingWithGoogle,
        .authenticatingWithInternalQA,
        .restoringSession,
        .authenticated
    ]

    /// Nobody signed in, the switch on, a finished pass on the device: no authentication state
    /// reaches the old landing screen, an authenticated state with no account behind it included.
    @Test
    func noStateWithNobodySignedInReachesTheOldLandingWhileTheSwitchIsOn() throws {
        let device = try SignOutDevice()
        device.store.update { $0.completedAt = Date() }
        let launch = device.launch(signedIn: false)

        for state in Self.everyAuthenticationState {
            #expect(launch.route(state) != .signedOut, "\(state) reached the old landing screen")
        }
        #expect(launch.route(.authenticated) == .preAuthOnboarding)
    }

    /// The hold is unchanged: a device the backend has never answered still waits rather than
    /// guessing, whatever it finished before.
    @Test
    func aLaunchThatHasNotReadTheSwitchStillHolds() throws {
        let device = try SignOutDevice()
        device.store.update { $0.completedAt = Date() }

        let launch = device.launch(signedIn: false, switchAnswer: nil)

        #expect(launch.route(.unauthenticated) == .signedOutHold)
        #expect(launch.route(.authenticated) == .signedOutHold)
    }

    /// The switch off is still the onboarding that shipped before it, whole.
    @Test
    func theSwitchOffStillOpensTheLandingScreen() throws {
        let launch = try SignOutDevice().launch(signedIn: false, switchAnswer: false)

        #expect(launch.route(.unauthenticated) == .signedOut)
    }

    private static func jpegData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }
}

/// What a signed-out climber is shown, drawn from the route the way the root draws it.
private struct SignedOutRouteScreen: View {
    let launch: SignOutLaunch

    var body: some View {
        switch launch.route(.unauthenticated) {
        case .preAuthOnboarding:
            OnboardingV3FlowView(coordinator: launch.coordinator)
        case .signedOut:
            LandingScreen()
        default:
            SignedOutHoldView()
        }
    }
}

/// The screen the sign-out lands on, read off the accessibility tree and photographed when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3SignOutEvidenceTests {
    private static let iPhone16 = CGSize(width: 393, height: 852)

    @Test("After a sign-out the screen is the v3 Welcome, and Sign in opens the returning sign-in")
    func theScreenAfterSigningOutIsTheV3Welcome() async throws {
        let launch = try SignOutDevice().launch(signedIn: false)
        launch.walkTheFlowAndSignIn()
        launch.coordinator.sessionEnded()

        let screen = SignedOutRouteScreen(launch: launch)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))

        try await RenderedScreen.host(screen, size: Self.iPhone16, settle: .turns(40)) { hosted in
            let welcome = try await hosted.copy { $0.contains("get started") }
            try hosted.photograph(named: "onboarding-v3-sign-out-01-welcome")
            #expect(welcome.contains("congratulations"))
            #expect(welcome.contains("get started"))
            #expect(welcome.contains("already have an account? sign in"))
            // Neither the sign-in screen the last climber left by, nor the onboarding the switch
            // replaced.
            #expect(!welcome.contains("save every"))
            #expect(!welcome.contains("stair stepper app"))
            #expect(!welcome.contains("get fit with the stair stepper"))

            try activateAccessibilityElement(labelled: "Already have an account? Sign in", in: hosted.root)
            try await hosted.settle(.turns(40))
            #expect(launch.coordinator.step == .auth)

            let signIn = try await hosted.copy { $0.contains("welcome back") }
            try hosted.photograph(named: "onboarding-v3-sign-out-02-returning-sign-in")
            #expect(signIn.contains("welcome back"))
            #expect(signIn.contains("continue with apple"))
            #expect(!signIn.contains("every climb from today"), "nothing of the last climber's pass is listed")
            #expect(!signIn.contains("internal qa sign in"), "the old sign-in screen's own button")
        }
    }
}
