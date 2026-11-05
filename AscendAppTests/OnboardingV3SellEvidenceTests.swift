import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The selling screens (01 to 05) on screen: at the smallest phone Ascend supports, at an
/// accessibility text size, and on a current phone. Copy is read from the accessibility tree, and
/// photographs are written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3SellEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)

    /// The smallest phone and the iPhone 16 Pro the other evidence suites render at.
    nonisolated private static let phones = [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)]

    private func coordinator(at target: OnboardingV3Step) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-sell-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: .welcome)
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

    /// A day inside the bundled catalogue's Thanksgiving event, which is too small to show gear.
    nonisolated private static let aNovemberDay = Calendar.current.date(from: DateComponents(year: 2_026, month: 11, day: 4, hour: 12))!

    /// A day inside the bundled catalogue's Halloween event, which has gear beyond its showcase.
    nonisolated private static let anOctoberDay = Calendar.current.date(from: DateComponents(year: 2_026, month: 10, day: 15, hour: 12))!

    private func somethingToChase(on day: Date) -> some View {
        OnboardingV3SellFramed(
            screen: OnboardingSomethingToChaseScreen(
                coordinator: coordinator(at: .somethingToChase),
                catalog: HostedUnlockCatalogRepository.bundledCatalog(),
                today: day
            )
        )
    }

    /// Where each of `labels` sits, in window points and whether or not it is scrolled into view,
    /// once all of them are there.
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

    /// A phone as a full-bleed screen meets it: how much of the top and bottom the system keeps.
    struct PhoneShape: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let size: CGSize
        let top: CGFloat
        let bottom: CGFloat
    }

    nonisolated static let phoneShapes = [
        PhoneShape(testDescription: "Dynamic Island", size: CGSize(width: 402, height: 874), top: 62, bottom: 34),
        PhoneShape(testDescription: "home button", size: CGSize(width: 375, height: 667), top: 20, bottom: 0)
    ]

    // MARK: - 01 Welcome

    @Test(arguments: Self.phones)
    func welcomeShowsTheWordmarkTheLineAndBothActions(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.welcome), size: size, settle: .turns(30)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("ascend"), "the real wordmark is labelled Ascend: \(copy)")
            #expect(copy.contains("stop staring at the clock."), "\(copy)")
            #expect(copy.contains("get started"), "\(copy)")
            #expect(copy.contains("already climbing? sign in"), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "01 has no bar: \(copy)")
            try screen.photograph(named: "onboarding-v3-sell-01-welcome-\(Int(size.height))")
        }
    }

    @Test
    func welcomeAtAnAccessibilityTextSizeKeepsBothActionsReachable() async throws {
        try await RenderedScreen.host(
            flow(.welcome).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("get started"), "\(copy)")
            #expect(copy.contains("already climbing? sign in"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-sell-01-welcome-se-accessibility3")
        }
    }

    /// The hero is a filled photo: it must fill the top and never widen the screen. The top of the
    /// screen is photo, not the black of the page.
    @Test
    func theWelcomePhotoFillsTheTopOfTheScreen() async throws {
        try await RenderedScreen.host(flow(.welcome), size: CGSize(width: 402, height: 874), settle: .turns(30)) { screen in
            _ = try await screen.copy()
            let topMiddle = try screen.color(at: CGPoint(x: 200, y: 60))
            let topRight = try screen.color(at: CGPoint(x: 380, y: 60))
            #expect(!topMiddle.isNearBlack, "the sky: \(topMiddle)")
            #expect(!topRight.isNearBlack, "the sky reaches the right edge: \(topRight)")
        }
    }

    /// The photo runs under the status bar and the home indicator; the wordmark and the actions do
    /// not. A photograph cannot show this, since `RenderedScreen` draws no status bar.
    @Test(arguments: Self.phoneShapes)
    func theWelcomeWordmarkAndActionsStayInsideTheSafeArea(phone: PhoneShape) async throws {
        let controller = UIHostingController(rootView: flow(.welcome))
        try await RenderedScreen.host(controller, size: phone.size, settle: .turns(30)) { screen in
            let own = screen.window.safeAreaInsets
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: phone.top - own.top, left: 0, bottom: phone.bottom - own.bottom, right: 0)
            try await screen.settle(.turns(20))
            let insets = controller.view.safeAreaInsets
            try #require(insets.top == phone.top && insets.bottom == phone.bottom, "hosted with \(insets)")

            let signInLabel = "Already climbing? Sign in"
            let frames = try await Self.frames(on: screen, of: ["Ascend", signInLabel])
            let wordmark = try #require(frames["Ascend"])
            let signIn = try #require(frames[signInLabel])
            #expect(wordmark.minY >= phone.top, "the wordmark \(wordmark) is under the \(phone.top) pt status bar")
            #expect(signIn.maxY <= phone.size.height - phone.bottom, "sign in \(signIn) is under the home indicator")

            let underTheStatusBar = try screen.color(at: CGPoint(x: phone.size.width / 2, y: phone.top / 2))
            #expect(!underTheStatusBar.isNearBlack, "the photo stops at the status bar: \(underTheStatusBar)")
        }
    }

    // MARK: - 02 Go harder

    @Test(arguments: Self.phones)
    func goHarderShowsTheHeadlineTheChipsAndContinue(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.goHarder), size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("go harder than you would alone."), "\(copy)")
            #expect(copy.contains("real climbers' best climbs move up beside you"), "\(copy)")
            #expect(copy.contains("more climbers ahead"), "the real crowd chip: \(copy)")
            #expect(copy.contains("pacer · 80 spm"), "\(copy)")
            #expect(copy.contains("your best"), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            #expect(copy.contains("onboarding progress"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-sell-02-go-harder-\(Int(size.height))")
        }
    }

    @Test
    func goHarderAtAnAccessibilityTextSizeKeepsContinueReachable() async throws {
        try await RenderedScreen.host(
            flow(.goHarder).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            let copy = try await screen.copy()
            #expect(copy.contains("continue"), "\(copy)")
            #expect(recognized.contains("continue"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-sell-02-go-harder-se-accessibility3")
        }
    }

    // MARK: - 03 Get better

    @Test(arguments: Self.phones)
    func getBetterShowsFourCardsEachWithItsNumber(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.getBetter), size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("see yourself get better."), "\(copy)")
            #expect(copy.contains("7,309 steps"), "\(copy)")
            #expect(copy.contains("40:08"), "\(copy)")
            #expect(copy.contains("5,004 steps"), "\(copy)")
            #expect(copy.contains("24:33"), "\(copy)")
            #expect(copy.contains("2nd all-time"), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            #expect(!copy.contains("{"), "no broken glyph where the medal goes: \(copy)")
            try screen.photograph(named: "onboarding-v3-sell-03-get-better-\(Int(size.height))")
        }
    }

    @Test
    func getBetterAtAnAccessibilityTextSizeKeepsContinueReachable() async throws {
        try await RenderedScreen.host(
            flow(.getBetter).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("continue"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-sell-03-get-better-se-accessibility3")
        }
    }

    /// The cards are taller than the room the smallest phone leaves them, so the middle scrolls
    /// rather than drawing them over the headline.
    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func getBetterCardsNeverReachTheHeadlineOnTheSmallestPhone(textSize: DynamicTypeSize) async throws {
        let headlineLabel = "See yourself get better."
        let cardLabels = SellRecordCard.examples.map(\.accessibilitySummary)
        try await RenderedScreen.host(
            flow(.getBetter).environment(\.dynamicTypeSize, textSize),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let frames = try await Self.frames(on: screen, of: cardLabels + [headlineLabel])
            let headline = try #require(frames[headlineLabel])
            for label in cardLabels {
                let card = try #require(frames[label])
                #expect(card.maxY <= headline.minY, "\(label) \(card) reaches the headline \(headline)")
            }
        }
    }

    // MARK: - 04 Something to chase

    /// Thanksgiving has six items, none to spare from the showcase 11 shows, so the reasons are
    /// the art: above the headline, and only once.
    @Test(arguments: Self.phones)
    func somethingToChaseInASmallEventMakesTheReasonsTheArt(size: CGSize) async throws {
        let chips = SellScreenCopy.SomethingToChase.chips
        let headlineLabel = "Always something to chase next."
        try await RenderedScreen.host(somethingToChase(on: Self.aNovemberDay), size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("always something to chase next."), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            for gone in ["golden turkey", "25k steps", "open ascend", "10 climbs", "1 climb"] {
                #expect(!copy.contains(gone), "\(gone) is gear: \(copy)")
            }

            let frames = try await Self.frames(on: screen, of: chips + [headlineLabel])
            let headline = try #require(frames[headlineLabel])
            for chip in chips {
                let frame = try #require(frames[chip])
                #expect(frame.maxY <= headline.minY, "\(chip) \(frame) is not above the headline \(headline)")
            }
            let elements = try await screen.elements()
            for chip in chips {
                #expect(elements.filter { $0.accessibilityLabel == chip }.count == 1, "\(chip) is not drawn once")
            }
            try screen.photograph(named: "onboarding-v3-sell-04-something-to-chase-november-\(Int(size.height))")
        }
    }

    /// Halloween has gear beyond its showcase: each piece is labelled with what it takes, none is
    /// one 11 shows, and the reasons stay in their row under the message.
    @Test(arguments: Self.phones)
    func somethingToChaseInABigEventShowsGearOutsideTheShowcase(size: CGSize) async throws {
        let headlineLabel = "Always something to chase next."
        try await RenderedScreen.host(somethingToChase(on: Self.anOctoberDay), size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            for line in ["25k steps", "1 climb", "5 climbs", "15 climbs", "best efforts to beat", "monthly gear", "continue"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            for showcase in ["open ascend", "3 climbs", "10 climbs", "witch hat", "jack-o'-lantern"] {
                #expect(!copy.contains(showcase), "\(showcase) is 11's: \(copy)")
            }

            let frames = try await Self.frames(on: screen, of: ["Monthly gear", headlineLabel])
            let chip = try #require(frames["Monthly gear"])
            let headline = try #require(frames[headlineLabel])
            #expect(chip.minY >= headline.maxY, "the chip \(chip) is not under the headline \(headline)")
            try screen.photograph(named: "onboarding-v3-sell-04-something-to-chase-october-\(Int(size.height))")
        }
    }

    @Test(arguments: [Self.aNovemberDay, Self.anOctoberDay])
    func somethingToChaseAtAnAccessibilityTextSizeKeepsContinueReachable(day: Date) async throws {
        try await RenderedScreen.host(
            somethingToChase(on: day).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("continue"), "\(copy)")
            let month = Calendar.current.component(.month, from: day)
            try hosted.photograph(named: "onboarding-v3-sell-04-something-to-chase-month-\(month)-se-accessibility3")
        }
    }

    // MARK: - 05 Count methods

    @Test(arguments: Self.phones)
    func countMethodsListsTheThreeWaysWithoutLive(size: CGSize) async throws {
        try await RenderedScreen.host(flow(.countMethods), size: size, settle: .turns(40)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("climb with what you've got."), "\(copy)")
            #expect(copy.contains("headphones"), "\(copy)")
            #expect(copy.contains("airpods or beats count every step, and other climbers move up beside you."), "\(copy)")
            #expect(copy.contains("apple health"), "\(copy)")
            #expect(copy.contains("nothing at all"), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-sell-05-count-methods-\(Int(size.height))")
        }
    }

    @Test
    func countMethodsAtAnAccessibilityTextSizeKeepsContinueReachable() async throws {
        try await RenderedScreen.host(
            flow(.countMethods).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            let copy = try await screen.copy()
            #expect(copy.contains("continue"), "\(copy)")
            #expect(recognized.contains("continue"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-sell-05-count-methods-se-accessibility3")
        }
    }
}

/// Hosts one screen with the flow's palette and coordinator environment around it, for a screen
/// whose initialiser takes a catalogue the flow would otherwise read from disk.
private struct OnboardingV3SellFramed<Screen: View>: View {
    let screen: Screen

    var body: some View {
        ZStack {
            OnboardingV3Palette.background.ignoresSafeArea()
            screen
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}
