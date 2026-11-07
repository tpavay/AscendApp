import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The sign-in screen on the simulator, in both of the design's states - everything given, and
/// everything skipped - on a phone the design was drawn for and on the smallest phone, plus an
/// accessibility text size. Photographs are written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingAuthEvidenceTests {
    struct PhoneShape: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let suffix: String
        let size: CGSize
        let top: CGFloat
        let bottom: CGFloat
        /// Whether the whole list fits above the pinned buttons, as the design shows it.
        let fitsTheWholeList: Bool
    }

    nonisolated static let phones = [
        PhoneShape(testDescription: "iPhone 16", suffix: "iphone16", size: CGSize(width: 393, height: 852), top: 59, bottom: 34, fitsTheWholeList: true),
        PhoneShape(testDescription: "SE", suffix: "se", size: CGSize(width: 375, height: 667), top: 20, bottom: 0, fitsTheWholeList: false)
    ]

    private static let smallestPhone = phones[1]

    private static let everyAccountGets = [
        "Every climb from today, Steps, time, streak and new bests",
        "Your spot on the boards, Leaderboards and live climbs"
    ]
    private static let boardsRow = "Your spot on the boards, Leaderboards and live climbs"
    private static let appleButton = "Continue with Apple"

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

    /// Hosts the screen with `phone`'s safe area on whichever simulator the suite runs, making up
    /// the difference from that simulator's own, so the pinned buttons sit where they would on it.
    private func host<Result>(
        _ view: some View,
        on phone: PhoneShape,
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        let controller = UIHostingController(rootView: view)
        return try await RenderedScreen.host(controller, size: phone.size, settle: .turns(40)) { hosted in
            let own = hosted.window.safeAreaInsets
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: phone.top - own.top, left: 0, bottom: phone.bottom - own.bottom, right: 0)
            try await hosted.settle(.turns(20))
            let insets = controller.view.safeAreaInsets
            try #require(insets.top == phone.top && insets.bottom == phone.bottom, "hosted with \(insets), not the \(phone.testDescription) safe area")
            return try await body(hosted)
        }
    }

    /// Where each of `labels` sits on screen, in window points, once all of them are there.
    private static func frames(on screen: HostedScreen, of labels: [String]) async throws -> [String: CGRect] {
        func read(_ elements: [NSObject]) -> [String: CGRect] {
            Dictionary(elements.compactMap { element in
                guard let label = element.accessibilityLabel, labels.contains(label) else { return nil }
                return (label, screen.window.convert(element.accessibilityFrame, from: nil))
            }, uniquingKeysWith: { first, _ in first })
        }
        let elements = try await screen.elements(reading: 400) { read($0).count == labels.count }
        return read(elements)
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private static func scrollToBottom(_ screen: HostedScreen) async throws {
        let scrollView = try #require(firstScrollView(in: screen.window))
        let bottom = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        try await screen.settle(.turns(6))
    }

    /// On a phone the design was drawn for the whole list sits above the buttons; on the smallest
    /// phone it runs under them and scrolling brings the last row out, whole, with the buttons
    /// still pinned.
    private static func expectTheListReachable(on screen: HostedScreen, phone: PhoneShape, lastRow: String) async throws {
        let atRest = try await frames(on: screen, of: [lastRow, appleButton])
        let row = try #require(atRest[lastRow])
        let apple = try #require(atRest[appleButton])
        if phone.fitsTheWholeList {
            #expect(row.maxY <= apple.minY, "the last row \(row) runs under the buttons \(apple) on the \(phone.testDescription)")
        } else {
            try await scrollToBottom(screen)
            let scrolled = try await frames(on: screen, of: [lastRow, appleButton])
            let rowScrolled = try #require(scrolled[lastRow])
            let appleScrolled = try #require(scrolled[appleButton])
            #expect(rowScrolled.maxY <= appleScrolled.minY, "the last row \(rowScrolled) is still under the buttons \(appleScrolled) after scrolling")
            #expect(appleScrolled.minY == apple.minY, "the buttons stay pinned")
        }
    }

    @Test(arguments: Self.phones)
    func everythingGivenListsTheHistoryAndTheProfileBetweenTheTwoThingsEveryAccountGets(phone: PhoneShape) async throws {
        try await host(screen(from: .notificationPrimer, answers: Self.everythingGiven()), on: phone) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("last step"), "\(copy)")
            #expect(copy.contains("save every climb."), "\(copy)")
            #expect(copy.contains("none of it is kept"), "\(copy)")
            #expect(copy.contains("every climb from today, steps, time, streak and new bests · 4 days a week"), "\(copy)")
            #expect(copy.contains("214 past climbs · 698,240 steps, from apple health, with past bests"), "\(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(copy.contains("ascend"), "the wordmark: \(copy)")
            #expect(copy.contains("back"), "a way back to the setup screens: \(copy)")
            #expect(!copy.contains("claim your"), "the old headline is gone: \(copy)")
            #expect(!copy.contains("your name here"), "no name prompt: \(copy)")
            if phone.fitsTheWholeList {
                #expect(copy.contains("m · 30, your profile · denver"), "\(copy)")
                #expect(copy.contains("your spot on the boards, leaderboards and live climbs"), "\(copy)")
            }
            try hosted.photograph(named: "onboarding-v3-auth-everything-given-\(phone.suffix)")
            try await Self.expectTheListReachable(on: hosted, phone: phone, lastRow: Self.boardsRow)
            if !phone.fitsTheWholeList {
                let scrolled = try await hosted.copy()
                #expect(scrolled.contains("m · 30, your profile · denver"), "\(scrolled)")
                try hosted.photograph(named: "onboarding-v3-auth-everything-given-\(phone.suffix)-scrolled")
            }
        }
    }

    @Test(arguments: Self.phones)
    func everythingSkippedListsOnlyWhatEveryAccountGetsAndNeverShowsASkippedItemAsDone(phone: PhoneShape) async throws {
        try await host(screen(from: .notificationPrimer), on: phone) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("save every climb."), "\(copy)")
            #expect(copy.contains("every climb from today, steps, time, streak and new bests"), "\(copy)")
            #expect(copy.contains("your spot on the boards"), "\(copy)")
            #expect(!copy.contains("past climb"), "no history row: \(copy)")
            #expect(!copy.contains("apple health"), "no history row: \(copy)")
            #expect(!copy.contains("your profile"), "no profile row: \(copy)")
            #expect(!copy.contains("days a week"), "no target: \(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-skipped-\(phone.suffix)")
            // Two rows fit above the buttons on every phone.
            let frames = try await Self.frames(on: hosted, of: [Self.boardsRow, Self.appleButton])
            let row = try #require(frames[Self.boardsRow])
            let apple = try #require(frames[Self.appleButton])
            #expect(row.maxY <= apple.minY, "the boards row \(row) runs under the buttons \(apple) on the \(phone.testDescription)")
        }
    }

    @Test
    func nothingOnTheScreenTakesTypedInput() async throws {
        try await RenderedScreen.host(screen(from: .notificationPrimer, answers: Self.everythingGiven()), size: Self.smallestPhone.size, settle: .turns(40)) { hosted in
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
        try await RenderedScreen.host(screen(from: .welcome, answers: Self.everythingGiven()), size: Self.smallestPhone.size, settle: .turns(40)) { hosted in
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
            size: Self.smallestPhone.size,
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
            try await Self.scrollToBottom(hosted)
            let scrolled = try await hosted.copy()
            #expect(scrolled.contains("your spot on the boards, leaderboards and live climbs"), "\(scrolled)")
            #expect(scrolled.contains("continue with apple"), "the buttons stay pinned: \(scrolled)")
            try hosted.photograph(named: "onboarding-v3-auth-everything-given-se-accessibility3-scrolled")
        }
    }
}
