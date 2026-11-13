import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The whole v3 onboarding walked end to end in its own `OnboardingV3FlowView`, by activating the
/// real controls through the accessibility tree the way a climber taps them, with the coordinator's
/// step checked after every tap and a photograph of every screen when `ASCEND_EVIDENCE_DIR` is set.
///
/// Two screens cannot be reached by tapping in a hosted window and are hosted in the flow's
/// environment instead: 07a reads the device's Health, which a simulator does not have, so it gets a
/// fake reader; and the sign-in screen's design state needs answers and a picked photo, which the
/// walk has deliberately skipped. The app-access paywall that follows sign-in is a Superwall paywall
/// the dashboard owns, so it is not a screen of this flow and is not photographed here.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3FlowEvidenceTests {
    private static let iPhone16 = CGSize(width: 393, height: 852)

    private struct Fixture {
        let coordinator: OnboardingV3Coordinator
        let photos: OnboardingProfilePhotoStore
    }

    private func fixture(startingAt step: OnboardingV3Step = .welcome) throws -> Fixture {
        let suite = "onboarding-v3-flow-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let directory = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photos = OnboardingProfilePhotoStore(directory: directory)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            photos: photos,
            startingAt: step,
            now: everyTapAfterTheTransition()
        )
        return Fixture(coordinator: coordinator, photos: photos)
    }

    private func flow(_ coordinator: OnboardingV3Coordinator) -> some View {
        OnboardingV3FlowView(coordinator: coordinator)
            .environment(AuthenticationViewModel())
    }

    /// Taps `label` on the hosted flow and waits for the transition, then checks where the
    /// coordinator went and photographs what is on screen.
    private func tap(
        _ label: String,
        on screen: HostedScreen,
        expecting step: OnboardingV3Step,
        in coordinator: OnboardingV3Coordinator,
        photograph name: String
    ) async throws {
        try activateAccessibilityElement(labelled: label, in: screen.root)
        try await screen.settle(.turns(40))
        #expect(coordinator.step == step, "\(label) should lead to \(step), not \(coordinator.step)")
        try screen.photograph(named: name)
    }

    @Test
    func theWholeFlowWalksFromWelcomeToSignInThroughBothBranchesByTappingTheRealControls() async throws {
        let fixture = try fixture()
        let coordinator = fixture.coordinator

        try await RenderedScreen.host(flow(coordinator), size: Self.iPhone16, settle: .turns(40)) { screen in
            #expect(coordinator.step == .welcome)
            try screen.photograph(named: "onboarding-v3-flow-01-welcome")

            try await tap("Get started", on: screen, expecting: .goHarder, in: coordinator, photograph: "onboarding-v3-flow-02-go-harder")
            try await tap("Continue", on: screen, expecting: .getBetter, in: coordinator, photograph: "onboarding-v3-flow-03-get-better")
            try await tap("Continue", on: screen, expecting: .somethingToChase, in: coordinator, photograph: "onboarding-v3-flow-04-something-to-chase")
            try await tap("Continue", on: screen, expecting: .countMethods, in: coordinator, photograph: "onboarding-v3-flow-05-count-methods")
            try await tap("Continue", on: screen, expecting: .healthConnect, in: coordinator, photograph: "onboarding-v3-flow-06-health-connect")

            // The Health branch: connecting opens the two-taps screen. Its own "Got it" asks iOS for
            // Health access, which a hosted window cannot answer, so the walk comes back and skips.
            try await tap("CONNECT APPLE HEALTH", on: screen, expecting: .healthPermission, in: coordinator, photograph: "onboarding-v3-flow-06b-health-permission")
            try await tap("Back", on: screen, expecting: .healthConnect, in: coordinator, photograph: "onboarding-v3-flow-06-health-connect-after-back")
            try await tap("Skip", on: screen, expecting: .usualClimb, in: coordinator, photograph: "onboarding-v3-flow-07b-usual-climb")

            try activateAccessibilityElement(labelled: "15 to 30 min, ~1,800 steps", in: screen.root)
            try await screen.settle(.turns(20))
            try await tap("CONTINUE", on: screen, expecting: .profileSetup, in: coordinator, photograph: "onboarding-v3-flow-08-profile-setup")
            #expect(coordinator.answers.usualClimbMinutes != nil, "CONTINUE writes the picked usual climb as an answer")
            try await tap("Skip", on: screen, expecting: .claimCity, in: coordinator, photograph: "onboarding-v3-flow-09-claim-city")
            try await tap("Skip", on: screen, expecting: .weeklyTarget, in: coordinator, photograph: "onboarding-v3-flow-10-weekly-target")
            try await tap("No target for now", on: screen, expecting: .thisMonthEvent, in: coordinator, photograph: "onboarding-v3-flow-11-this-month-event")
            try await tap("LET'S CLIMB", on: screen, expecting: .notificationPrimer, in: coordinator, photograph: "onboarding-v3-flow-12-notification-primer")
            try await tap("Not now", on: screen, expecting: .auth, in: coordinator, photograph: "onboarding-v3-flow-15-save-every-climb")

            // Sign-in ends the flow: nothing on the screen moves the coordinator on.
            #expect(coordinator.step.primaryDestination == nil)
            let copy = try await screen.copy()
            #expect(copy.contains("save every"))
            #expect(copy.contains("continue with apple"))
            #expect(!copy.contains("stub"), "no placeholder screen survives in the shipped flow")
        }
    }

    @Test
    func theWelcomeScreensSignInLinkOpensTheReturningModeAndBackReturnsToWelcome() async throws {
        let coordinator = try fixture().coordinator

        try await RenderedScreen.host(flow(coordinator), size: Self.iPhone16, settle: .turns(40)) { screen in
            try await tap("Already have an account? Sign in", on: screen, expecting: .auth, in: coordinator, photograph: "onboarding-v3-flow-15-returning")
            let copy = try await screen.copy()
            #expect(copy.contains("welcome back"))
            #expect(!copy.contains("every climb from today"), "a returning climber is not shown a saved-items list")
            try await tap("Back", on: screen, expecting: .welcome, in: coordinator, photograph: "onboarding-v3-flow-01-welcome-after-back")
        }
    }

    @Test
    func theHealthHistoryScreenRendersInTheFlowsEnvironmentWithAFoundHistory() async throws {
        let coordinator = try fixture(startingAt: .healthHistory).coordinator
        let reader = FakeHealthWorkoutReader()
        reader.workouts = (0..<14).map { index in
            let start = Date().addingTimeInterval(-Double(index * 5 + 1) * 86_400)
            return HealthWorkoutSnapshot(
                uuid: UUID(),
                startDate: start,
                endDate: start.addingTimeInterval(32 * 60),
                duration: 32 * 60,
                steps: index % 4 == 3 ? nil : 1_600 + index * 40
            )
        }
        let screen = ZStack {
            OnboardingV3Palette.background.ignoresSafeArea()
            OnboardingHealthHistoryScreen(
                coordinator: coordinator,
                viewModel: OnboardingHealthHistoryViewModel(reader: reader, loadClimbs: { [] })
            )
        }
        .environment(\.onboardingV3Coordinator, coordinator)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)

        try await RenderedScreen.host(screen, size: Self.iPhone16, settle: .turns(60)) { hosted in
            let copy = try await hosted.copy { $0.contains("we found your climbs") }
            #expect(copy.contains("14 stair stepper workouts"))
            #expect(copy.contains("add 14 to my history"))
            #expect(copy.contains("skip history, just import new workouts"))
            try hosted.photograph(named: "onboarding-v3-flow-07a-health-history")
        }
    }

    @Test
    func theSignInScreensProfileRowShowsTheTypedNameAndThePickedPhoto() async throws {
        let fixture = try fixture(startingAt: .notificationPrimer)
        let coordinator = fixture.coordinator
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor(red: 0.85, green: 0.2, blue: 0.55, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let jpeg = try #require(picture.jpegData(compressionQuality: 0.9))
        let fileName = try #require(fixture.photos.save(jpeg))
        coordinator.update {
            $0.firstName = "Tess"
            $0.lastName = "Parker"
            $0.gender = .man
            $0.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 9)
            $0.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
            $0.weeklyTargetDays = 4
            $0.profilePhotoFileName = fileName
        }
        coordinator.go(to: .auth)
        #expect(coordinator.profilePhotoURL != nil, "the picked photo is on the device")

        try await RenderedScreen.host(flow(coordinator), size: Self.iPhone16, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("tess parker · m ·"))
            #expect(copy.contains("your profile · denver"))
            #expect(copy.contains("4 days a week"))

            // The row's mark is the photo: the magenta picture, never the lime initials disc.
            // The row is one accessibility element that starts at its mark, 44 points wide.
            let row = try #require(try await screen.frame(ofElementLabelled: "Tess Parker"))
            let mark = CGPoint(x: row.minX + 22, y: row.midY)
            let colour = try screen.color(at: mark)
            #expect(colour.red > colour.green, "the mark at \(mark) draws the picked photo, read \(colour)")
            try screen.photograph(named: "onboarding-v3-flow-15-save-every-climb-with-photo")
        }
    }
}
