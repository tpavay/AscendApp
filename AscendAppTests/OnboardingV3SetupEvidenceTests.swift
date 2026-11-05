import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Screens 07b, 08, 09, 10 and 11 on screen, at the smallest phone and at an accessibility text
/// size, plus Home's weekly ring. Copy is asserted from the accessibility tree; photographs are
/// written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3SetupEvidenceTests {
    private static let smallestPhone = CGSize(width: 375, height: 667)
    private nonisolated static let accessibilitySize = DynamicTypeSize.accessibility3

    private func coordinator(
        at step: OnboardingV3Step,
        answers: (inout PreAuthOnboardingAnswers) -> Void = { _ in }
    ) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-setup-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: step)
        coordinator.update(answers)
        return coordinator
    }

    private func suffix(_ size: DynamicTypeSize?) -> String { size == nil ? "se" : "se-ax" }

    private func host<Content: View>(
        _ view: Content,
        size: DynamicTypeSize?,
        name: String,
        check: @MainActor (String) -> Void
    ) async throws {
        try await RenderedScreen.host(
            view.dynamicTypeSize(size ?? .large),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy()
            check(copy)
            try screen.photograph(named: "onboarding-v3-\(name)-\(suffix(size))")
        }
    }

    // MARK: - 07b

    @Test(arguments: [nil, Self.accessibilitySize])
    func theUsualClimbScreenShowsFiveRowsAndADimmedContinue(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .usualClimb)
        try await host(OnboardingV3FlowView(coordinator: coordinator), size: size, name: "usual-climb") { copy in
            #expect(copy.contains("how long is a usual climb?"), "\(copy)")
            #expect(copy.contains("we'll pick your first climb so it's hard, but doable."), "\(copy)")
            #expect(copy.contains("i'm new to this"), "\(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            // The last row sits below the fold at an accessibility size; the scroll reaches it.
            if size == nil { #expect(copy.contains("45 min or more"), "\(copy)") }
            #expect(!copy.contains("size your first goal"), "\(copy)")
        }
    }

    // MARK: - 08

    @Test(arguments: [nil, Self.accessibilitySize])
    func theClimberCardShowsEveryTileAndTheSettingsFooter(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .climberCard) {
            $0.gender = .woman
            $0.heightCm = 177.8
            $0.weightKg = 79.4
            $0.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 14)
        }
        let screen = OnboardingClimberCardScreen(coordinator: coordinator, system: .imperial)
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: size,
            name: "climber-card"
        ) { copy in
            #expect(copy.contains("set up your climber card."), "\(copy)")
            #expect(copy.contains("your climber card, joined today"), "\(copy)")
            #expect(copy.contains("gender female, age 30, height 5'10\", weight 175 lb"), "\(copy)")
            #expect(copy.contains("change any of it in settings."), "\(copy)")
            #expect(copy.contains("skip"), "one skip: \(copy)")
            #expect(!copy.contains("hide"), "\(copy)")
        }
    }

    @Test
    func anEmptyCardDrawsNoDashCharacter() async throws {
        let coordinator = coordinator(at: .climberCard)
        let screen = OnboardingClimberCardScreen(coordinator: coordinator, system: .imperial)
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: nil,
            name: "climber-card-empty"
        ) { copy in
            #expect(!copy.contains("\u{2014}"), "\(copy)")
            #expect(!copy.contains(" - "), "\(copy)")
        }
    }

    // MARK: - 09

    @Test(arguments: [nil, Self.accessibilitySize])
    func theCityScreenBeforeALocationOffersBothWaysIn(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .claimCity)
        try await host(OnboardingV3FlowView(coordinator: coordinator), size: size, name: "claim-city") { copy in
            #expect(copy.contains("claim your city."), "\(copy)")
            #expect(copy.contains("every city gets its own leaderboard."), "\(copy)")
            #expect(copy.contains("use my location"), "\(copy)")
            #expect(copy.contains("type my city instead"), "\(copy)")
            #expect(copy.contains("skip"), "\(copy)")
        }
    }

    private struct FixedReader: CityClimberCountReading {
        let result: CityClimberCount
        func count(for selection: PostAuthLocationSelection) async -> CityClimberCount { result }
    }

    @Test(arguments: [nil, Self.accessibilitySize])
    func anEmptyCityIsClaimableAndSaysSo(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .claimCity) {
            $0.city = PreAuthOnboardingCity(city: "Chicago", region: "IL", countryCode: "US", countryName: "United States")
        }
        let model = OnboardingCityClaimModel(reader: FixedReader(result: .climbers(0)), initialCity: coordinator.answers.city)
        let screen = OnboardingClaimCityScreen(coordinator: coordinator, model: model)
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: size,
            name: "claim-city-chicago"
        ) { copy in
            #expect(copy.contains("be among the first climbers in chicago."), "\(copy)")
            if size == nil { #expect(copy.contains("we only use your city, never your exact spot."), "\(copy)") }
            #expect(copy.contains("continue"), "\(copy)")
        }
    }

    // MARK: - 10

    @Test(arguments: [nil, Self.accessibilitySize])
    func theTargetScreenStartsUnchosenAndSkippable(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .weeklyTarget)
        try await host(OnboardingV3FlowView(coordinator: coordinator), size: size, name: "weekly-target") { copy in
            #expect(copy.contains("how many days a week?"), "\(copy)")
            #expect(copy.contains("set a target if you want one. hit your days and close your week."), "\(copy)")
            #expect(copy.contains("no target for now"), "\(copy)")
            #expect(copy.contains("skip"), "\(copy)")
            #expect(copy.contains("?"), "the number reads ? until a bar is tapped: \(copy)")
            #expect(!copy.contains("consistency beats intensity"), "\(copy)")
        }
    }

    @Test
    func aChosenTargetNamesItsTier() async throws {
        let coordinator = coordinator(at: .weeklyTarget) { $0.weeklyTargetDays = 3 }
        try await host(OnboardingV3FlowView(coordinator: coordinator), size: nil, name: "weekly-target-3") { copy in
            #expect(copy.contains("steady climber"), "\(copy)")
            #expect(copy.contains("set my target"), "\(copy)")
        }
    }

    // MARK: - 11

    private struct FixedUnlocks: UnlockCatalogRepository {
        let catalog: UnlockCatalog
        func loadInitialCatalog() -> UnlockCatalog { catalog }
        func refreshCatalog() async throws -> UnlockCatalog { catalog }
    }

    private struct NoLandmarks: ClimbCatalogRepository {
        func loadInitialCatalog() throws -> ClimbCatalogSnapshot { throw URLError(.fileDoesNotExist) }
        func refreshCatalog() async throws -> ClimbCatalogSnapshot { throw URLError(.notConnectedToInternet) }
    }

    private func eventScreen(on day: DateComponents, answers: (inout PreAuthOnboardingAnswers) -> Void) -> (OnboardingV3Coordinator, OnboardingThisMonthEventScreen) {
        let coordinator = coordinator(at: .thisMonthEvent, answers: answers)
        let model = OnboardingMonthlyEventModel(
            unlockRepository: FixedUnlocks(catalog: HostedUnlockCatalogRepository.bundledCatalog()),
            climbRepository: NoLandmarks(),
            isUnlocksEnabled: { true }
        )
        let now = Calendar.current.date(from: day) ?? .now
        return (coordinator, OnboardingThisMonthEventScreen(coordinator: coordinator, model: model, now: now))
    }

    @Test(arguments: [nil, Self.accessibilitySize])
    func thanksgivingIsOnInNovember(size: DynamicTypeSize?) async throws {
        let (coordinator, screen) = eventScreen(on: DateComponents(year: 2026, month: 11, day: 4, hour: 12)) { $0.weeklyTargetDays = 3 }
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: size,
            name: "this-month-thanksgiving"
        ) { copy in
            #expect(copy.contains("this month"), "\(copy)")
            #expect(copy.contains("thanksgiving is on."), "\(copy)")
            #expect(copy.contains("climb this november and earn gear for your athlete."), "\(copy)")
            #expect(copy.contains("let's climb"), "\(copy)")
            // Everything under the headline is below the fold at the smallest phone and scrolls.
            if size == nil {
                #expect(copy.contains("yours today"), "\(copy)")
                #expect(copy.contains("pieces to earn"), "\(copy)")
                #expect(copy.contains("days left"), "\(copy)")
            }
            #expect(!copy.contains("steps to top"), "no mountain: \(copy)")
            #expect(!copy.contains("first up"), "no first-up card: \(copy)")
        }
    }

    @Test
    func theWeekBeforeDecemberTheScreenSaysItIsComing() async throws {
        let (coordinator, screen) = eventScreen(on: DateComponents(year: 2026, month: 11, day: 26, hour: 12)) { _ in }
        // November still runs on the 26th, so the running version shows; the coming-soon version
        // needs a gap, which the unit tests drive. This photograph is the last week of November.
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: nil,
            name: "this-month-last-week"
        ) { copy in
            #expect(copy.contains("thanksgiving is on."), "\(copy)")
            #expect(copy.contains("5, days left"), "\(copy)")
        }
    }

    @Test(arguments: [nil, Self.accessibilitySize])
    func anEmptyMonthShowsTheNeutralScreen(size: DynamicTypeSize?) async throws {
        let (coordinator, screen) = eventScreen(on: DateComponents(year: 2027, month: 6, day: 10, hour: 12)) {
            $0.usualClimbSteps = 1_800
            $0.usualClimbMinutes = 22
        }
        try await host(
            ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                .environment(\.onboardingV3Coordinator, coordinator),
            size: size,
            name: "this-month-neutral"
        ) { copy in
            #expect(copy.contains("every climb counts"), "\(copy)")
            #expect(copy.contains("you're ready to climb."), "\(copy)")
            if size == nil { #expect(copy.contains("1,800"), "\(copy)") }
            #expect(!copy.contains("ends "), "nothing dated: \(copy)")
            #expect(!copy.contains("thanksgiving"), "no stale event: \(copy)")
        }
    }

    private struct OneLandmark: ClimbCatalogRepository {
        let snapshot: ClimbCatalogSnapshot
        func loadInitialCatalog() throws -> ClimbCatalogSnapshot { snapshot }
        func refreshCatalog() async throws -> ClimbCatalogSnapshot { snapshot }
    }

    /// Screen 11 runs signed out, and Storage refuses `climb-images/` to a signed-out caller, so a
    /// Storage-backed hero never loads and draws its placeholder - a climb's name in the middle of
    /// the art - behind the copy. The accessibility tree cannot see that, because the art is hidden
    /// from it, so this reads the glyphs. The landmark catalogue is present here on purpose: it is
    /// what a real install has and what the other renders in this suite leave out.
    @Test(arguments: [
        DateComponents(year: 2026, month: 11, day: 4, hour: 12),
        DateComponents(year: 2027, month: 6, day: 10, hour: 12)
    ])
    func theHeroIsAPhotographBeforeSignIn(on day: DateComponents) async throws {
        let catalogue = try HostedClimbCatalogRepository().loadInitialCatalog()
        let landmark = try #require(catalogue.availableClimbs.first)
        let coordinator = coordinator(at: .thisMonthEvent)
        let model = OnboardingMonthlyEventModel(
            unlockRepository: FixedUnlocks(catalog: HostedUnlockCatalogRepository.bundledCatalog()),
            climbRepository: OneLandmark(snapshot: ClimbCatalogSnapshot(
                climbs: [landmark],
                source: .bootstrap,
                catalogVersion: 1,
                featuredClimbId: landmark.id,
                updatedAt: nil
            )),
            isUnlocksEnabled: { true }
        )
        let now = try #require(Calendar.current.date(from: day))
        let screen = OnboardingThisMonthEventScreen(coordinator: coordinator, model: model, now: now)

        for phone in [Self.smallestPhone, RenderedScreen.iPhone16ProSize] {
            let photoRegion = CGRect(x: 0, y: 0, width: phone.width, height: phone.height * 0.4)

            try await RenderedScreen.host(
                ZStack { OnboardingV3Palette.background.ignoresSafeArea(); screen }
                    .environment(\.onboardingV3Coordinator, coordinator),
                size: phone,
                settle: .turns(40)
            ) { screen in
                let reading = try await screen.recognizedText(scale: 2)
                #expect(!reading.contains(landmark.name.lowercased()), "\(reading)")
                #expect(reading.contains("let's climb"), "\(reading)")

                // A photograph, not the bare gradient: the sunset is orange where the gradient is lime.
                let orange = try screen.withPixels { pixels in
                    pixels.count(in: photoRegion) { $0.red > 90 && Int($0.red) > Int($0.green) + 30 && Int($0.green) > Int($0.blue) + 10 }
                }
                #expect(orange > 500, "only \(orange) photo pixels in the art")
                try screen.photograph(named: "onboarding-v3-this-month-hero-\(day.year ?? 0)-\(Int(phone.height))")
            }
        }
    }

    // MARK: - Home

    @Test
    func homeDrawsTheWeeklyRingOnlyWithATarget() async throws {
        func section(_ progress: WeeklyTargetProgress?) -> some View {
            HomeRankStreakSection(
                weeklyRankSummary: nil, isRankLoading: false,
                streak: WeeklyStreak(weeks: 2, isCurrentWeekSecured: true),
                weeklyTargetProgress: progress,
                onRankTapped: {}, onStreakTapped: {}
            )
            .padding(16).frame(width: 402).background(Color.black)
            .environment(\.colorScheme, .dark)
        }
        let target = try #require(WeeklyTarget(days: 3))
        let withTarget = WeeklyTargetProgress(target: target, daysClimbed: 2)

        let with = try await RenderedScreen.host(section(withTarget)) { screen in
            try await screen.copy { $0.contains("weekly target") }
        }
        #expect(with.contains("weekly target: 2 of 3 days climbed this week."), "\(with)")
        try RenderedScreen.photograph(section(withTarget), named: "home-weekly-ring")

        let without = try await RenderedScreen.host(section(nil)) { screen in
            try await screen.copy { $0.contains("streak") }
        }
        #expect(!without.contains("weekly target"), "\(without)")
    }
}
