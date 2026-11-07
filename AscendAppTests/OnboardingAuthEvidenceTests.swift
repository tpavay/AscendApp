import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The sign-in screen on the simulator, at the smallest phone and at an accessibility text size,
/// in both of the design's states: everything given, and everything skipped. Photographs are
/// written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingAuthEvidenceTests {
    private static let smallestPhone = CGSize(width: 375, height: 667)

    /// The design's left state: Apple Health history added, the climber card filled in, a city and
    /// a target.
    private static func everythingGiven() -> PreAuthOnboardingAnswers {
        var answers = PreAuthOnboardingAnswers()
        answers.gender = .man
        answers.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 9)
        answers.heightCm = 180
        answers.weightKg = 80
        answers.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
        answers.weeklyTargetDays = 4
        answers.recordFoundHealthHistory(workoutIDs: (0..<214).map { "w\($0)" }, knownSteps: 698_240)
        return answers
    }

    private func coordinator(
        from origin: OnboardingV3Step,
        answers: PreAuthOnboardingAnswers = PreAuthOnboardingAnswers()
    ) -> OnboardingV3Coordinator {
        let suite = "onboarding-auth-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.save(answers)
        let coordinator = OnboardingV3Coordinator(store: store, startingAt: origin)
        coordinator.go(to: .auth)
        return coordinator
    }

    private func screen(
        from origin: OnboardingV3Step,
        answers: PreAuthOnboardingAnswers = PreAuthOnboardingAnswers()
    ) -> some View {
        OnboardingAuthScreen(coordinator: coordinator(from: origin, answers: answers))
            .environment(AuthenticationViewModel())
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }

    @Test
    func everythingGivenListsTheHistoryAndTheProfileBetweenTheTwoThingsEveryAccountGets() async throws {
        try await RenderedScreen.host(screen(from: .notificationPrimer, answers: Self.everythingGiven()), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("last step"), "\(copy)")
            #expect(copy.contains("save every climb."), "\(copy)")
            #expect(copy.contains("none of it is kept"), "\(copy)")
            #expect(copy.contains("every climb from today, steps, time, streak and new bests · 4 days a week"), "\(copy)")
            #expect(copy.contains("214 past climbs · 698,240 steps, from apple health, with past bests"), "\(copy)")
            #expect(copy.contains("m · 30, your profile · denver"), "\(copy)")
            #expect(copy.contains("your spot on the boards, leaderboards and live climbs"), "\(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(copy.contains("ascend"), "the wordmark: \(copy)")
            #expect(copy.contains("back"), "a way back to the setup screens: \(copy)")
            #expect(!copy.contains("claim your"), "the old headline is gone: \(copy)")
            #expect(!copy.contains("your name here"), "no name prompt: \(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-given-se")
        }
    }

    @Test
    func everythingSkippedListsOnlyWhatEveryAccountGetsAndNeverShowsASkippedItemAsDone() async throws {
        try await RenderedScreen.host(screen(from: .notificationPrimer), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("save every climb."), "\(copy)")
            #expect(copy.contains("every climb from today, steps, time, streak and new bests"), "\(copy)")
            #expect(copy.contains("your spot on the boards"), "\(copy)")
            #expect(!copy.contains("past climb"), "no history row: \(copy)")
            #expect(!copy.contains("apple health"), "no history row: \(copy)")
            #expect(!copy.contains("your profile"), "no profile row: \(copy)")
            #expect(!copy.contains("days a week"), "no target: \(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-skipped-se")
        }
    }

    @Test
    func nothingOnTheScreenTakesTypedInput() async throws {
        try await RenderedScreen.host(screen(from: .notificationPrimer, answers: Self.everythingGiven()), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            _ = try await hosted.copy()
            func inputs(in view: UIView) -> Int {
                let own = (view is UITextField || view is UITextView || view is UISearchBar) ? 1 : 0
                return own + view.subviews.reduce(0) { $0 + inputs(in: $1) }
            }
            #expect(inputs(in: hosted.window) == 0)
        }
    }

    @Test
    func returningModeFromTheFirstScreenShowsNoList() async throws {
        try await RenderedScreen.host(screen(from: .welcome, answers: Self.everythingGiven()), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("welcome back"), "\(copy)")
            #expect(copy.contains("keep climbing"), "\(copy)")
            #expect(!copy.contains("every climb from today"), "no list: \(copy)")
            #expect(!copy.contains("past climbs"), "no list: \(copy)")
            #expect(!copy.contains("last step"), "\(copy)")
            let texts = try await hosted.texts()
            #expect(texts.contains { $0.text == "Back" && $0.traits.contains(.button) }, "a way back: \(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-returning-se")
        }
    }

    @Test
    func everyControlStaysReachableAtAnAccessibilityTextSize() async throws {
        try await RenderedScreen.host(
            screen(from: .notificationPrimer, answers: Self.everythingGiven()).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("save every climb."), "\(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            let recognized = try await hosted.recognizedText(scale: 2).lowercased()
            #expect(recognized.contains("save"), "legible, not just in the tree: \(recognized)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-given-se-accessibility3")

            // The list sits below the fold at this size and the buttons stay pinned over it, so
            // the rows are reached by scrolling, every one of them whole.
            let scrollView = try #require(Self.firstScrollView(in: hosted.window))
            let bottom = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await hosted.settle(.turns(6))
            let scrolled = try await hosted.copy()
            #expect(scrolled.contains("your spot on the boards, leaderboards and live climbs"), "\(scrolled)")
            #expect(scrolled.contains("continue with apple"), "the buttons stay pinned: \(scrolled)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-given-se-accessibility3-scrolled")
        }
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
