import FirebaseAuth
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

    private func profileScreen(
        _ coordinator: OnboardingV3Coordinator,
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: "profile-evidence-\(UUID().uuidString)"))
    ) -> some View {
        ZStack {
            OnboardingV3Palette.background.ignoresSafeArea()
            OnboardingProfileSetupScreen(coordinator: coordinator, system: .imperial, photos: photos)
        }
        .environment(\.onboardingV3Coordinator, coordinator)
    }

    @Test(arguments: [nil, Self.accessibilitySize])
    func theEmptyProfileScreenShowsTheDefaultNameAndEveryRowNotSet(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .profileSetup)
        try await host(profileScreen(coordinator), size: size, name: "profile-setup") { copy in
            #expect(copy.contains("set up your profile."), "\(copy)")
            #expect(copy.contains("this is how you show up on every leaderboard and live climb."), "\(copy)")
            #expect(copy.contains("change me"), "\(copy)")
            #expect(copy.contains("first name"), "\(copy)")
            #expect(copy.contains("last name"), "\(copy)")
            // A compact-height phone at an accessibility size scrolls the rows below the name fields under a fade.
            if size == nil {
                #expect(copy.contains("birthday"), "\(copy)")
                #expect(copy.contains("not set"), "\(copy)")
            }
            #expect(copy.contains("all optional. change any of it in settings."), "\(copy)")
            #expect(copy.contains("skip"), "one skip: \(copy)")
            #expect(!copy.contains("climber card"), "\(copy)")
            #expect(!copy.contains("race"), "\(copy)")
        }
    }

    @Test
    func aFilledProfileReadsBackOnTheRowAndTheLeaderboardLine() async throws {
        let coordinator = coordinator(at: .profileSetup) {
            $0.firstName = "Tyler"
            $0.lastName = "Pavay"
            $0.gender = .man
            $0.heightCm = 177.8
            $0.birthday = PreAuthOnboardingBirthday(year: 1996, month: 6, day: 14)
        }
        try await host(profileScreen(coordinator), size: nil, name: "profile-setup-filled") { copy in
            #expect(copy.contains("tyler pavay"), "\(copy)")
            #expect(copy.contains("5'10\""), "\(copy)")
            #expect(!copy.contains("change me"), "\(copy)")
        }
    }

    @Test
    func aRefusedNameSaysSoAndTheRowKeepsTheDefault() async throws {
        let coordinator = coordinator(at: .profileSetup) { $0.firstName = "Fuck" }
        try await host(profileScreen(coordinator), size: nil, name: "profile-setup-refused-name") { copy in
            #expect(copy.contains("that name can't go on a leaderboard. pick another."), "\(copy)")
            #expect(copy.contains("change me"), "\(copy)")
        }
    }

    private static let iPhone16 = CGSize(width: 393, height: 852)
    /// The padding under the body in `OnboardingSetupLayout`: the last row has to clear the footnote
    /// by this much or the body overflows, scrolls and draws its fade over the row.
    private static let bodyBottomPadding: CGFloat = 20

    /// The whole phone, with its own status bar and home indicator instead of the host's.
    private func onPhone(_ screen: some View, top: CGFloat, bottom: CGFloat) -> some View {
        screen
            .safeAreaPadding(.top, top)
            .safeAreaPadding(.bottom, bottom)
            .ignoresSafeArea()
    }

    /// The iPhone 16 and its filled twin, beside the SE ones above, at the height its insets really
    /// leave: the screen fits without scrolling, because the rows all sit above the footnote.
    @Test(arguments: [false, true])
    func theIPhone16FitsEveryRowAboveTheFootnote(filled: Bool) async throws {
        let coordinator = coordinator(at: .profileSetup) {
            guard filled else { return }
            $0.firstName = "Tyler"
            $0.lastName = "Pavay"
            $0.gender = .man
            $0.heightCm = 177.8
            $0.birthday = PreAuthOnboardingBirthday(year: 1996, month: 6, day: 14)
        }
        try await RenderedScreen.host(onPhone(profileScreen(coordinator), top: 59, bottom: 34), size: Self.iPhone16, settle: .turns(40)) { screen in
            for row in ["Birthday", "Height", "Weight"] {
                let frame = try #require(try await screen.frame(ofElementLabelled: row))
                let footnote = try #require(try await screen.text(containing: "all optional")?.frame)
                #expect(frame.maxY + Self.bodyBottomPadding <= footnote.minY, "\(row) \(frame) footnote \(footnote)")
            }
            try screen.photograph(named: "onboarding-v3-profile-setup-iphone16-\(filled ? "filled" : "empty")")
        }
    }

    /// The screen fits with no scrolling at the handoff's size. On its own 390 x 844 canvas, with the
    /// insets that phone has, every row sits above the footnote that sits above CONTINUE. A
    /// compact-height phone is the one that scrolls, under a fade.
    @Test
    func everyRowSitsAboveTheFootnoteOnTheDesignsCanvas() async throws {
        let coordinator = coordinator(at: .profileSetup)
        try await RenderedScreen.host(
            onPhone(profileScreen(coordinator), top: 47, bottom: 34),
            size: CGSize(width: 390, height: 844),
            settle: .turns(40)
        ) { screen in
            let weight = try #require(try await screen.frame(ofElementLabelled: "Weight"))
            let footnote = try #require(try await screen.text(containing: "all optional")?.frame)
            #expect(weight.maxY + Self.bodyBottomPadding <= footnote.minY, "weight \(weight) footnote \(footnote)")

            let title = try #require(try await screen.text(containing: "set up your")?.frame)
            let header = try #require(try await screen.frame(ofElementLabelled: "Back"))
            #expect(title.minY >= header.maxY, "the title clears the back button: \(title) \(header)")
            try screen.photograph(named: "onboarding-v3-profile-setup-design-canvas")
        }
    }

    private func sheetHost<Content: View>(_ sheet: Content, name: String, check: @MainActor (String) -> Void = { _ in }) async throws {
        try await RenderedScreen.host(
            sheet.environment(\.colorScheme, .dark),
            size: CGSize(width: 390, height: 460),
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy()
            check(copy)
            try screen.photograph(named: "onboarding-v3-profile-sheet-\(name)")
        }
    }

    @Test
    func theHeightSheetOpensAtTheStoredHeightWithItsFrameCopy() async throws {
        try await sheetHost(
            ProfileHeightSheet(initialCentimeters: 177.8, system: .imperial, onUnitChange: { _ in }, onDone: { _ in }),
            name: "height"
        ) { copy in
            #expect(copy.contains("height"), "\(copy)")
            #expect(copy.contains("done"), "\(copy)")
            #expect(copy.contains("profile only, for comparing. not on leaderboards."), "\(copy)")
        }
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        (view as? UIScrollView) ?? view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    /// Reads the marks as drawn, not as modelled. Only a foot's long tick reaches this far left of
    /// the ruler's edge, so a bright pixel at the pointer's height means a foot mark is under it.
    /// 71 inches opens one row short of 6 ft; moving the real scroll view on one row, which is what
    /// a finger dragging up does, brings the 6 ft tick to the pointer from above.
    @Test
    func theDrawnMarkUnderThePointerFollowsTheScrollOneRowAtATime() async throws {
        let ruler = HeightRulerView(system: .imperial, value: .constant(71))
        try await RenderedScreen.host(
            ruler.background(Color.black).environment(\.colorScheme, .dark),
            size: CGSize(width: 390, height: 460),
            settle: .turns(40)
        ) { screen in
            let scroller = try #require(scrollView(in: screen.root))
            let strip = scroller.convert(scroller.bounds, to: nil)
            let longTickOnly = CGRect(x: strip.maxX - 40, y: strip.midY - 1, width: 6, height: 2)
            let brightPixels = {
                try screen.withPixels { pixels in pixels.count(in: longTickOnly) { $0.red > 150 } }
            }

            #expect(try brightPixels() == 0, "71 inches is no foot mark")
            try screen.photograph(named: "onboarding-v3-height-ruler-71")

            scroller.setContentOffset(
                CGPoint(x: 0, y: scroller.contentOffset.y + HeightRulerView.rowHeight),
                animated: false
            )
            try await Task.sleep(for: .milliseconds(200))

            #expect(try brightPixels() > 0, "one row on is 72 inches, the 6 ft mark")
            try screen.photograph(named: "onboarding-v3-height-ruler-72")
        }
    }

    @Test
    func theWeightSheetOpensAtTheStoredWeightWithItsFrameCopy() async throws {
        try await sheetHost(
            ProfileWeightSheet(initialKilograms: 79.37866, system: .imperial, onUnitChange: { _ in }, onDone: { _ in }),
            name: "weight"
        ) { copy in
            #expect(copy.contains("weight"), "\(copy)")
            #expect(copy.contains("done"), "\(copy)")
            #expect(copy.contains("profile only, for comparing. not on leaderboards."), "\(copy)")
        }
    }

    @Test
    func theBirthdaySheetSaysOnlyTheAgeShows() async throws {
        try await sheetHost(
            ProfileBirthdaySheet(initial: nil, onDone: { _ in }),
            name: "birthday"
        ) { copy in
            #expect(copy.contains("birthday"), "\(copy)")
            #expect(copy.contains("only your age shows. never the date."), "\(copy)")
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
    func theTargetScreenStartsUnchosenWithNoTopRightSkip(size: DynamicTypeSize?) async throws {
        let coordinator = coordinator(at: .weeklyTarget)
        try await host(OnboardingV3FlowView(coordinator: coordinator), size: size, name: "weekly-target") { copy in
            #expect(copy.contains("how many days a week?"), "\(copy)")
            #expect(copy.contains("set a target if you want one. hit your days and close your week."), "\(copy)")
            #expect(copy.contains("no target for now"), "\(copy)")
            #expect(!copy.contains("skip"), "no top-right Skip on this screen: \(copy)")
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
        try Auth.auth().signOut()
        #expect(Auth.auth().currentUser == nil)
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
                #expect(orange > 10_000, "only \(orange) photo pixels in the art")
                try screen.photograph(named: "onboarding-v3-this-month-hero-\(day.year ?? 0)-\(Int(phone.height))")
            }
        }
    }

    /// The art is always in the app, so the choice cannot depend on a session or the network: a
    /// haunted event draws its own, and every other version draws the screen's photograph.
    @Test(arguments: [
        (DateComponents(year: 2026, month: 10, day: 15, hour: 12), "Seasonal/HauntedStairwell"),
        (DateComponents(year: 2026, month: 11, day: 4, hour: 12), "OnboardingEventHero"),
        (DateComponents(year: 2027, month: 6, day: 10, hour: 12), "OnboardingEventHero")
    ])
    func theHeroArtShipsInTheApp(on day: DateComponents, expected: String) throws {
        let now = try #require(Calendar.current.date(from: day))
        let name = OnboardingMonthlyEvent
            .resolve(catalog: HostedUnlockCatalogRepository.bundledCatalog(), now: now)
            .heroImageName
        #expect(name == expected)
        #expect(UIImage(named: name) != nil)
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
