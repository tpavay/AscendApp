import Foundation
import SwiftUI
import Testing
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

    /// A day inside the bundled catalogue's Thanksgiving event, for the gear screen.
    private static let aNovemberDay = Calendar.current.date(from: DateComponents(year: 2_026, month: 11, day: 4, hour: 12))!

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

    // MARK: - 04 Something to chase

    @Test(arguments: Self.phones)
    func somethingToChaseLabelsEachPieceWithWhatItTakes(size: CGSize) async throws {
        let screen = OnboardingSomethingToChaseScreen(
            coordinator: coordinator(at: .somethingToChase),
            catalog: HostedUnlockCatalogRepository.bundledCatalog(),
            today: Self.aNovemberDay
        )
        try await RenderedScreen.host(
            OnboardingV3SellFramed(screen: screen),
            size: size,
            settle: .turns(60)
        ) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("always something to chase next."), "\(copy)")
            #expect(copy.contains("golden turkey"), "\(copy)")
            #expect(copy.contains("25k steps"), "\(copy)")
            #expect(copy.contains("open ascend"), "\(copy)")
            #expect(copy.contains("10 climbs"), "\(copy)")
            #expect(copy.contains("best efforts to beat"), "\(copy)")
            #expect(copy.contains("monthly gear"), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-sell-04-something-to-chase-\(Int(size.height))")
        }
    }

    @Test
    func somethingToChaseAtAnAccessibilityTextSizeKeepsContinueReachable() async throws {
        let screen = OnboardingSomethingToChaseScreen(
            coordinator: coordinator(at: .somethingToChase),
            catalog: HostedUnlockCatalogRepository.bundledCatalog(),
            today: Self.aNovemberDay
        )
        try await RenderedScreen.host(
            OnboardingV3SellFramed(screen: screen)
                .environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("continue"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-sell-04-something-to-chase-se-accessibility3")
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
