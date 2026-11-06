import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The Apple Health screens (06, 06b, 07a) on screen: at the smallest phone Ascend supports, at an
/// accessibility text size, with Reduce Motion, and on a current phone. Copy is read from the
/// accessibility tree, glyphs through OCR only where legibility is the contract, and photographs
/// are written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3HealthEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)
    nonisolated private static let phones = [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)]
    nonisolated private static let accessibilitySizes: [DynamicTypeSize] = [.accessibility3, .accessibility5]

    private func coordinator(at target: OnboardingV3Step) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-health-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: .welcome, now: everyTapAfterTheTransition())
        var path: [OnboardingV3Step] = []
        var current: OnboardingV3Step? = .welcome
        while let step = current, step != target {
            path.append(step)
            current = step.primaryDestination
        }
        for _ in path { coordinator.advance() }
        return coordinator
    }

    /// The flow's own view, so the header, the transition and the environment are the real ones.
    private func flow(_ step: OnboardingV3Step) -> some View {
        OnboardingV3FlowView(coordinator: coordinator(at: step))
    }

    /// 07a with a Health database of exactly `workouts`, in the flow's environment. The flow itself
    /// reads the device's own Health, which has nothing in a simulator.
    private func history(
        _ workouts: [HealthWorkoutSnapshot],
        climbs: [Climb] = [],
        reduceMotion: Bool = false
    ) -> some View {
        let reader = FakeHealthWorkoutReader()
        reader.workouts = workouts
        let flow = coordinator(at: .healthHistory)
        return ZStack {
            OnboardingV3Palette.background.ignoresSafeArea()
            OnboardingHealthHistoryScreen(
                coordinator: flow,
                viewModel: OnboardingHealthHistoryViewModel(reader: reader, loadClimbs: { climbs })
            )
        }
        .environment(\.onboardingV3Coordinator, flow)
        .environment(\.onboardingReduceMotionOverride, reduceMotion ? true : nil)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private static func workout(daysAgo: Double, steps: Int?, minutes: Double) -> HealthWorkoutSnapshot {
        let start = Date().addingTimeInterval(-daysAgo * 86_400)
        return HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps
        )
    }

    /// Thirty long workouts that each report steps: 690,000 steps, 14 times over Everest.
    private static var manyWithSteps: [HealthWorkoutSnapshot] {
        (0..<30).map { workout(daysAgo: Double(40 + $0 * 3), steps: 23_000, minutes: 200) }
    }

    /// Ten workouts of which two report steps.
    private static var mostlyWithoutSteps: [HealthWorkoutSnapshot] {
        (0..<10).map { workout(daysAgo: Double(2 + $0 * 3), steps: $0 < 2 ? 3_000 : nil, minutes: 41) }
    }

    /// The drawn sheet is an image to VoiceOver, so `copy()` leaves it out by design; it is read
    /// from the elements, by the description it speaks.
    private static func expectTheSheetPicture(on screen: HostedScreen) async throws {
        let elements = try await screen.elements { $0.contains { $0.accessibilityLabel == HealthPermissionSheetMock.accessibilityDescription } }
        let picture = try #require(elements.first { $0.accessibilityLabel == HealthPermissionSheetMock.accessibilityDescription })
        #expect(picture.accessibilityTraits.contains(.image))
        #expect(screen.bounds.intersects(picture.accessibilityFrame), "the sheet picture is on screen")
    }

    // MARK: - 06 Your workouts, counted for you

    @Test(arguments: Self.phones)
    func connectShowsTheDesignsCopyTheBarAndBothActions(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.healthConnect), size: size, settle: .turns(40)) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("your workouts,"), "\(copy)")
            #expect(copy.contains("counted for you."), "\(copy)")
            #expect(copy.contains("any device or app that saves there show up in ascend. no typing."), "\(copy)")
            for chip in ["workouts", "steps", "heart rate"] { #expect(copy.contains(chip), "\(copy)") }
            #expect(copy.contains("connect apple health"), "\(copy)")
            #expect(copy.contains("i don't track workouts"), "\(copy)")
            #expect(copy.contains("onboarding progress"), "the bar replaces the X: \(copy)")
            #expect(copy.contains("back"), "\(copy)")
            #expect(!copy.contains("not now"), "onboarding's quiet link is the other one: \(copy)")
            #expect(!copy.contains("close"), "no X in onboarding: \(copy)")
            #expect(!copy.contains("tap turn on all"), "06b shows the sheet, so the hint is left out: \(copy)")
            try screen.photograph(named: "onboarding-v3-health-06-connect-\(Int(size.height))")
        }
    }

    @Test
    func theClimbSheetsCopyOfTheSameScreenKeepsItsXAndNotNow() async throws {
        try await RenderedScreen.host(AppleHealthConnectView(onConnect: {}, onClose: {}), settle: .turns(40)) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("close"), "\(copy)")
            #expect(copy.contains("not now"), "\(copy)")
            #expect(copy.contains("tap turn on all, then allow."), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "\(copy)")
            #expect(!copy.contains("i don't track workouts"), "\(copy)")
        }
    }

    @Test(arguments: Self.accessibilitySizes)
    func connectAtAnAccessibilityTextSizeKeepsBothActionsReachable(size: DynamicTypeSize) async throws {
        try await RenderedScreen.host(
            flow(.healthConnect).environment(\.dynamicTypeSize, size),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("connect apple health"), "\(copy)")
            #expect(copy.contains("i don't track workouts"), "\(copy)")
            let primary = try #require(try await screen.frame(ofElementLabelled: "Connect Apple Health"))
            #expect(screen.bounds.contains(primary), "the primary button \(primary) runs off the screen")
            try screen.photograph(named: "onboarding-v3-health-06-connect-se-\(size)")
        }
    }

    @Test
    func connectArrivesWithReduceMotion() async throws {
        try await RenderedScreen.host(
            flow(.healthConnect).environment(\.onboardingReduceMotionOverride, true),
            size: CGSize(width: 402, height: 874),
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("counted for you."), "\(copy)")
            try screen.photograph(named: "onboarding-v3-health-06-connect-reduce-motion")
        }
    }

    // MARK: - 06b Two taps and you're set

    @Test(arguments: Self.phones)
    func twoTapsShowsTheStepsTheBarAndGotIt(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.healthPermission), size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy { $0.contains("got it") }
            #expect(copy.contains("two taps and you're set."), "\(copy)")
            #expect(copy.contains("step 1. tap turn on all"), "\(copy)")
            #expect(copy.contains("step 2. tap allow at the bottom"), "\(copy)")
            try await Self.expectTheSheetPicture(on: screen)
            #expect(copy.contains("got it"), "\(copy)")
            #expect(copy.contains("onboarding progress"), "\(copy)")
            #expect(!copy.contains("update"), "Ascend never writes to Health: \(copy)")
            let primary = try #require(try await screen.frame(ofElementLabelled: "Got it"))
            #expect(screen.bounds.contains(primary), "the button \(primary) runs off the screen")
            try screen.photograph(named: "onboarding-v3-health-06b-two-taps-\(Int(size.height))")
        }
    }

    /// The picture of Apple's sheet lists the four types Ascend asks for and nothing else. Its words
    /// are drawn, not labelled, so only the pixels can prove them.
    @Test
    func theMockedSheetNamesTheRealReadSetAndNoFlightsClimbed() async throws {
        try await RenderedScreen.host(flow(.healthPermission), size: CGSize(width: 402, height: 874), settle: .turns(60)) { screen in
            let recognized = try await screen.recognizedText(scale: 3).lowercased()
            for name in HealthPermissionSheetMock.categories {
                #expect(recognized.contains(name.lowercased()), "\(name) is missing from the sheet picture: \(recognized)")
            }
            #expect(!recognized.contains("flights"), "\(recognized)")
            #expect(!recognized.contains("update"), "\(recognized)")
        }
    }

    @Test(arguments: Self.accessibilitySizes)
    func twoTapsAtAnAccessibilityTextSizeKeepsGotItReachable(size: DynamicTypeSize) async throws {
        try await RenderedScreen.host(
            flow(.healthPermission).environment(\.dynamicTypeSize, size),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("got it") }
            #expect(copy.contains("got it"), "\(copy)")
            let primary = try #require(try await screen.frame(ofElementLabelled: "Got it"))
            #expect(screen.bounds.contains(primary), "the button \(primary) runs off the screen")
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            #expect(recognized.contains("got it"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-health-06b-two-taps-se-\(size)")
        }
    }

    @Test
    func twoTapsArrivesWithReduceMotion() async throws {
        try await RenderedScreen.host(
            flow(.healthPermission).environment(\.onboardingReduceMotionOverride, true),
            size: CGSize(width: 402, height: 874),
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("got it") }
            #expect(copy.contains("two taps and you're set."), "\(copy)")
            try await Self.expectTheSheetPicture(on: screen)
            try screen.photograph(named: "onboarding-v3-health-06b-reduce-motion")
        }
    }

    // MARK: - 07a We found your climbs

    @Test(arguments: Self.phones)
    func historyLeadsWithTheStepsWhenMostWorkoutsCarryThem(size: CGSize) async throws {
        try await RenderedScreen.host(
            history(Self.manyWithSteps, reduceMotion: true),
            size: size,
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(copy.contains("we found your climbs"), "\(copy)")
            #expect(copy.contains("690,000"), "\(copy)")
            #expect(copy.contains("steps in 30 stair stepper workouts"), "\(copy)")
            #expect(copy.contains("that's everest"), "\(copy)")
            #expect(copy.contains("14 times over."), "\(copy)")
            #expect(copy.contains("your best hour"), "\(copy)")
            #expect(copy.contains("6,900"), "23,000 steps in 200 minutes, spread over an hour: \(copy)")
            #expect(copy.contains("steps in 60 min"), "\(copy)")
            #expect(copy.contains("your usual climb"), "\(copy)")
            #expect(copy.contains("23,000"), "\(copy)")
            #expect(copy.contains("steps · 200 min"), "\(copy)")
            #expect(copy.contains("past climbs fill your history and personal bests."), "\(copy)")
            #expect(copy.contains("leaderboards count from today, so it's fair for everyone."), "\(copy)")
            #expect(!copy.contains("rank 2nd"), "the estimated rank card is dropped: \(copy)")
            #expect(!copy.contains("#2"), "\(copy)")
            let primary = try #require(try await screen.frame(ofElementLabelled: "Add to my history"))
            #expect(screen.bounds.contains(primary), "the button \(primary) runs off the screen")
            try screen.photograph(named: "onboarding-v3-health-07a-steps-\(Int(size.height))")
        }
    }

    @Test
    func historyLeadsWithTheWorkoutsAndHoursWhenMostCarryNoSteps() async throws {
        try await RenderedScreen.host(
            history(Self.mostlyWithoutSteps, reduceMotion: true),
            size: CGSize(width: 402, height: 874),
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(copy.contains("we found your climbs"), "\(copy)")
            #expect(copy.contains("10"), "\(copy)")
            #expect(copy.contains("stair stepper workouts · 7 hours"), "\(copy)")
            #expect(copy.contains("6,000 steps in the 2 that track them"), "the steps wait behind the workouts: \(copy)")
            try screen.photograph(named: "onboarding-v3-health-07a-workouts-first")
        }
    }

    @Test
    func historyWithNoStepsAtAllLeavesTheEverestCardAndTheStepsOut() async throws {
        let workouts = (0..<6).map { Self.workout(daysAgo: Double(2 + $0), steps: nil, minutes: 41) }
        try await RenderedScreen.host(history(workouts, reduceMotion: true), size: CGSize(width: 402, height: 874), settle: .turns(60)) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(copy.contains("stair stepper workouts · 4 hours"), "\(copy)")
            #expect(!copy.contains("everest"), "\(copy)")
            #expect(!copy.contains("times over"), "\(copy)")
            #expect(!copy.contains("your best hour"), "\(copy)")
            #expect(copy.contains("your usual climb"), "\(copy)")
            #expect(copy.contains("minutes"), "minutes alone when steps are unknown: \(copy)")
            try screen.photograph(named: "onboarding-v3-health-07a-no-steps")
        }
    }

    @Test
    func historyUnderOneEverestComparesWithTheTallestClimbCovered() async throws {
        let workouts = (0..<3).map { Self.workout(daysAgo: Double(30 + $0), steps: 1_700, minutes: 90) }
        try await RenderedScreen.host(
            history(workouts, climbs: [Climb.preview], reduceMotion: true),
            size: CGSize(width: 402, height: 874),
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(copy.contains("5,100"), "\(copy)")
            #expect(copy.contains("that's the empire state building"), "\(copy)")
            #expect(copy.contains("3 times over."), "\(copy)")
            #expect(!copy.contains("everest"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-health-07a-under-everest")
        }
    }

    @Test
    func historyWithNoWorkoutLongEnoughGivesTheUsualClimbTheWholeRow() async throws {
        let workouts = (0..<4).map { Self.workout(daysAgo: Double(2 + $0), steps: 2_400, minutes: 30) }
        try await RenderedScreen.host(history(workouts, reduceMotion: true), size: CGSize(width: 402, height: 874), settle: .turns(60)) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(!copy.contains("your best hour"), "\(copy)")
            #expect(copy.contains("your usual climb"), "\(copy)")
            let tile = try #require(try await screen.frame(ofElementLabelled: "Your usual climb"))
            #expect(tile.width > 300, "the tile takes the row: \(tile)")
            try screen.photograph(named: "onboarding-v3-health-07a-no-best-hour")
        }
    }

    @Test(arguments: Self.accessibilitySizes)
    func historyAtAnAccessibilityTextSizeKeepsTheButtonReachableAndTheWordsWhole(size: DynamicTypeSize) async throws {
        try await RenderedScreen.host(
            history(Self.manyWithSteps, reduceMotion: true).environment(\.dynamicTypeSize, size),
            size: CGSize(width: Self.smallestPhone.width, height: 2_600),
            settle: .turns(80)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add to my history") }
            #expect(copy.contains("add to my history"), "\(copy)")
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            for word in ["found", "everest", "usual", "history"] {
                #expect(recognized.contains(word), "\(word) is broken at \(size): \(recognized)")
            }
            try screen.photograph(named: "onboarding-v3-health-07a-se-\(size)")
        }

        try await RenderedScreen.host(
            history(Self.manyWithSteps, reduceMotion: true).environment(\.dynamicTypeSize, size),
            size: Self.smallestPhone,
            settle: .turns(80)
        ) { screen in
            let primary = try #require(try await screen.frame(ofElementLabelled: "Add to my history"))
            #expect(screen.bounds.contains(primary), "pinned and reachable on the smallest phone: \(primary)")
        }
    }

    /// The count and the peaks arrive: with motion on, the total passes through its count-up and
    /// settles on the real number, and the screen still reads whole.
    @Test
    func historyCountsUpAndSettlesOnTheRealTotal() async throws {
        try await RenderedScreen.host(
            history(Self.manyWithSteps),
            size: CGSize(width: 402, height: 874),
            settle: .turns(90)
        ) { screen in
            let copy = try await screen.copy { $0.contains("690,000") }
            #expect(copy.contains("690,000"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-health-07a-count-up")
        }
    }
}
