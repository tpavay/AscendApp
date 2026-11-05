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

    /// A day before the bundled catalogue's first event opens, so there is no event to show.
    nonisolated private static let anAugustDay = Calendar.current.date(from: DateComponents(year: 2_026, month: 8, day: 1, hour: 12))!

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

    /// Reads `words` off the pixels of a screen as wide as the smallest phone and tall enough to
    /// show all of it. A word broken across lines is whole in the accessibility tree and only OCR
    /// can see the break.
    private func expectWholeWords(
        _ words: [String],
        in view: some View,
        at textSize: DynamicTypeSize,
        photographedAs name: String
    ) async throws {
        try await RenderedScreen.host(
            view.environment(\.dynamicTypeSize, textSize),
            size: CGSize(width: Self.smallestPhone.width, height: 2_600),
            settle: .turns(60)
        ) { screen in
            _ = try await screen.copy()
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            for word in words {
                #expect(recognized.contains(word), "\(word) is broken at \(textSize): \(recognized)")
            }
            try screen.photograph(named: "\(name)-\(textSize)")
        }
    }

    nonisolated private static let accessibilitySizes: [DynamicTypeSize] = [.accessibility3, .accessibility5]

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
            let crowdChip = try #require(try await screen.frame(ofElementLabelled: "more climbers ahead"))
            #expect(screen.bounds.contains(crowdChip), "the crowd chip \(crowdChip) runs off the screen")
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

    /// All three chips stay whole on the smallest phone at the largest text size, where the art is
    /// at its smallest, and none lands on another.
    @Test
    func goHarderChipsStayOnScreenAndApartAtTheLargestTextSize() async throws {
        try await RenderedScreen.host(
            flow(.goHarder).environment(\.dynamicTypeSize, .accessibility5),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let labels = ["Pacer", "Your Best", "more climbers ahead"]
            var chips: [CGRect] = []
            for label in labels {
                let chip = try #require(try await screen.frame(ofElementLabelled: label), "\(label) is not on screen")
                #expect(chip.minX >= 0 && chip.maxX <= Self.smallestPhone.width, "\(label) \(chip) runs off the screen")
                #expect(chips.allSatisfy { !$0.intersects(chip) }, "\(label) \(chip) lands on another chip: \(chips)")
                chips.append(chip)
            }
            try screen.photograph(named: "onboarding-v3-sell-02-go-harder-chips-se-accessibility5")
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

    @Test(arguments: Self.accessibilitySizes)
    func getBetterCardsNeverBreakAWord(textSize: DynamicTypeSize) async throws {
        try await expectWholeWords(
            ["time", "fastest", "steps"],
            in: flow(.getBetter),
            at: textSize,
            photographedAs: "onboarding-v3-sell-03-whole-words"
        )
    }

    // MARK: - 04 Something to chase

    /// Thanksgiving has six items, none to spare from the showcase 11 shows, and before the first
    /// event there is nothing to show at all. Either way the reasons are the art: above the
    /// headline, and only once.
    @Test(arguments: Self.phones, [Self.aNovemberDay, Self.anAugustDay])
    func somethingToChaseWithNoGearMakesTheReasonsTheArt(size: CGSize, day: Date) async throws {
        let chips = SellScreenCopy.SomethingToChase.chips
        let headlineLabel = "Always something to chase next."
        try await RenderedScreen.host(somethingToChase(on: day), size: size, settle: .turns(60)) { screen in
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
            let month = Calendar.current.component(.month, from: day)
            try screen.photograph(named: "onboarding-v3-sell-04-something-to-chase-month-\(month)-\(Int(size.height))")
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

    @Test(arguments: Self.accessibilitySizes)
    func somethingToChaseChipsNeverBreakAWord(textSize: DynamicTypeSize) async throws {
        for (day, month) in [(Self.aNovemberDay, "november"), (Self.anOctoberDay, "october")] {
            try await expectWholeWords(
                ["leaderboards", "achievements"],
                in: somethingToChase(on: day),
                at: textSize,
                photographedAs: "onboarding-v3-sell-04-whole-words-\(month)"
            )
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

    @Test(arguments: Self.accessibilitySizes)
    func countMethodsTitlesNeverBreakAWord(textSize: DynamicTypeSize) async throws {
        try await expectWholeWords(
            ["headphones", "health", "nothing", "best"],
            in: flow(.countMethods),
            at: textSize,
            photographedAs: "onboarding-v3-sell-05-whole-words"
        )
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

    // MARK: - Reduce Motion

    /// With motion off every line still arrives: `copy` reads only what is painted, so an element
    /// stuck at opacity 0 never satisfies the wait.
    private func expectEverythingArrivesWithReduceMotion(
        _ lines: [String],
        in view: some View,
        photographedAs name: String,
        also check: @MainActor (HostedScreen) throws -> Void = { _ in }
    ) async throws {
        try await RenderedScreen.host(
            view.environment(\.onboardingReduceMotionOverride, true),
            size: CGSize(width: 402, height: 874),
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy { copy in lines.allSatisfy(copy.contains) }
            for line in lines {
                #expect(copy.contains(line), "\(line) never arrived: \(copy)")
            }
            try check(screen)
            try screen.photograph(named: "onboarding-v3-sell-reduce-motion-\(name)")
        }
    }

    @Test
    func welcomeArrivesWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            ["ascend", "stop staring at the clock.", "ascend turns every stair stepper session", "get started", "already climbing? sign in"],
            in: flow(.welcome),
            photographedAs: "01-welcome"
        ) { screen in
            let sky = try screen.color(at: CGPoint(x: 200, y: 60))
            #expect(!sky.isNearBlack, "the photo never arrived: \(sky)")
        }
    }

    @Test
    func goHarderArrivesWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            [
                SellScreenCopy.GoHarder.screenshotDescription.lowercased(),
                "more climbers ahead", "your best", "pacer · 80 spm",
                "go harder than you would alone.", "real climbers' best climbs move up beside you", "continue"
            ],
            in: flow(.goHarder),
            photographedAs: "02-go-harder"
        )
    }

    @Test
    func getBetterArrivesWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            SellRecordCard.examples.map { $0.accessibilitySummary.lowercased() }
                + ["see yourself get better.", "the machine forgets every workout.", "continue"],
            in: flow(.getBetter),
            photographedAs: "03-get-better"
        )
    }

    /// Reduce Motion lays the cards flat and motion tilts them, which proves the override reaches
    /// the screen: the same read with motion on sees cards of different widths.
    @Test(arguments: [true, false])
    func getBetterCardsLieFlatOnlyWithReduceMotion(reduceMotion: Bool) async throws {
        let labels = SellRecordCard.examples.map(\.accessibilitySummary)
        try await RenderedScreen.host(
            flow(.getBetter).environment(\.onboardingReduceMotionOverride, reduceMotion),
            size: CGSize(width: 402, height: 874),
            settle: .turns(60)
        ) { screen in
            let frames = try await Self.frames(on: screen, of: labels)
            let widths = Set(frames.values.map { Int($0.width.rounded()) })
            #expect((widths.count == 1) == reduceMotion, "card widths \(widths)")
        }
    }

    @Test
    func somethingToChaseReasonsArriveWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            SellScreenCopy.SomethingToChase.chips.map { $0.lowercased() }
                + ["always something to chase next.", "continue"],
            in: somethingToChase(on: Self.aNovemberDay),
            photographedAs: "04-reasons"
        )
    }

    @Test
    func somethingToChaseGearArrivesWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            ["25k steps", "1 climb", "5 climbs", "15 climbs", "monthly gear", "always something to chase next.", "continue"],
            in: somethingToChase(on: Self.anOctoberDay),
            photographedAs: "04-gear"
        )
    }

    @Test
    func countMethodsArrivesWithReduceMotion() async throws {
        try await expectEverythingArrivesWithReduceMotion(
            ["climb with what you've got.", "headphones", "apple health", "nothing at all", "continue"],
            in: flow(.countMethods),
            photographedAs: "05-count-methods"
        )
    }

    // MARK: - Reduce Motion changing while a screen is up

    /// A climber can change the setting and come back to the same screen. What has already arrived
    /// stays: `copy` reads only what is painted, so a rebuilt entrance stuck at opacity 0 never
    /// satisfies the wait.
    private func expectEverythingSurvivesAFlip(
        from start: Bool,
        of lines: [String],
        in view: some View
    ) async throws {
        let reduceMotion = ReduceMotionSwitch(isOn: start)
        try await RenderedScreen.host(
            OnboardingV3ReduceMotionSwitched(reduceMotion: reduceMotion, content: view),
            size: CGSize(width: 402, height: 874),
            settle: .turns(30)
        ) { screen in
            _ = try await screen.copy { copy in lines.allSatisfy(copy.contains) }
            try await Task.sleep(for: .seconds(2))

            reduceMotion.isOn.toggle()
            try await screen.settle(.turns(30))

            let copy = try await screen.copy { copy in lines.allSatisfy(copy.contains) }
            for line in lines {
                #expect(copy.contains(line), "\(line) is gone after the flip: \(copy)")
            }
        }
    }

    @Test(arguments: [true, false])
    func goHarderChipsSurviveAReduceMotionFlip(start: Bool) async throws {
        try await expectEverythingSurvivesAFlip(
            from: start,
            of: ["more climbers ahead", "your best", "pacer · 80 spm", "continue"],
            in: flow(.goHarder)
        )
    }

    @Test(arguments: [true, false])
    func getBetterCardsSurviveAReduceMotionFlip(start: Bool) async throws {
        try await expectEverythingSurvivesAFlip(
            from: start,
            of: SellRecordCard.examples.map { $0.accessibilitySummary.lowercased() } + ["continue"],
            in: flow(.getBetter)
        )
    }

    @Test(arguments: [true, false])
    func somethingToChaseReasonsSurviveAReduceMotionFlip(start: Bool) async throws {
        try await expectEverythingSurvivesAFlip(
            from: start,
            of: SellScreenCopy.SomethingToChase.chips.map { $0.lowercased() } + ["continue"],
            in: somethingToChase(on: Self.aNovemberDay)
        )
    }

    @Test(arguments: [true, false])
    func somethingToChaseGearSurvivesAReduceMotionFlip(start: Bool) async throws {
        try await expectEverythingSurvivesAFlip(
            from: start,
            of: ["25k steps", "1 climb", "5 climbs", "15 climbs", "continue"],
            in: somethingToChase(on: Self.anOctoberDay)
        )
    }

    /// The photo that has settled stays settled when motion comes back on: the same pixels before
    /// and after, where a photo sent back to its 1.15 start would have moved under them.
    @Test
    func theWelcomePhotoStaysSettledWhenMotionComesBackOn() async throws {
        let reduceMotion = ReduceMotionSwitch(isOn: true)
        let points = stride(from: 150, through: 500, by: 70).map { CGPoint(x: 240, y: $0) }
        try await RenderedScreen.host(
            OnboardingV3ReduceMotionSwitched(reduceMotion: reduceMotion, content: flow(.welcome)),
            size: CGSize(width: 402, height: 874),
            settle: .turns(30)
        ) { screen in
            _ = try await screen.copy { $0.contains("get started") }
            let before = try points.map { try screen.color(at: $0) }

            reduceMotion.isOn = false
            try await screen.settle(.turns(30))

            let after = try points.map { try screen.color(at: $0) }
            for (first, second) in zip(before, after) {
                #expect(first.isClose(to: second, tolerance: 4), "the photo moved: \(first) became \(second)")
            }
        }
    }
}

/// Reduce Motion as a value a test can change while the screen stays mounted.
@Observable
private final class ReduceMotionSwitch {
    var isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }
}

private struct OnboardingV3ReduceMotionSwitched<Content: View>: View {
    let reduceMotion: ReduceMotionSwitch
    let content: Content

    var body: some View {
        content.environment(\.onboardingReduceMotionOverride, reduceMotion.isOn)
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
