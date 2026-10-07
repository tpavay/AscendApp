import CoreLocation
import FirebaseFirestore
import HealthKit
import MapKit
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Evidence for Home's sheet in each of its three positions, read off the accessibility
/// tree of the real `HomeView` hosted above the real tab bar. The globe itself is a
/// MapKit view whose annotations do not survive a hierarchy capture; its evidence is
/// `HomeGlobeSnapshotEvidenceTests`.
///
/// Every service the hosted Home would reach for is a stub: the feed answers once,
/// the boards and the community summary answer from memory, and the Health
/// enrichment service is this suite's own instance, so the shared one is never
/// pointed at the throwaway store.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct HomeGlobeSheetEvidenceTests {
    /// The event Home's sheet carries a card for today, if one is running: the card sits between
    /// Today's Climb and ASCEND ACTIVITY TODAY while it does.
    private static var runningEvent: UnlockEvent? {
        let unlocks = UnlockStore.shared
        guard unlocks.isEnabled else { return nil }
        return unlocks.catalog.events.first { $0.contains(.now) && !unlocks.catalog.items(earnedIn: $0).isEmpty }
    }

    @Test
    func theSheetOpensCollapsedToTheThisWeekLine() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .compact)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let copy = try await hosted.copy()

            // Collapsed: the This Week line is on screen, the rest of the sheet is below the fold.
            #expect(copy.contains("this week"))
            #expect(!copy.contains("ascend activity today"))
            #expect(!copy.contains("ranked"))

            // The globe's chrome: the legend names the tiers on the globe, and Start is reachable.
            #expect(copy.contains("marker colors by steps"))
            #expect(copy.contains("start"))

            try hosted.photograph(named: "home-globe-sheet-collapsed")
        }
    }

    @Test
    func pulledUpTheSheetShowsTodaysClimbAndTheRows() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .medium)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let mediumCopy = try await hosted.copy()

            #expect(mediumCopy.contains("today's climb"))
            if let event = Self.runningEvent {
                #expect(mediumCopy.contains("\(event.title.lowercased()) is on."), "the running event's card follows Today's Climb: \(mediumCopy)")
            } else {
                #expect(mediumCopy.contains("ascend activity today"))
            }
            try hosted.photograph(named: "home-globe-sheet-medium")
        }
    }

    @Test
    func expandedTheSheetCarriesTheThreeRowsThenTheTilesThenTheCatalog() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .expanded)

        // Tall enough to reach the catalog past a running event's card.
        try await RenderedScreen.host(screen, size: CGSize(width: 402, height: 1_100), settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let expandedCopy = try await hosted.copy()

            // Exactly three today rows, newest first, and SEE ALL because the server holds more.
            #expect(expandedCopy.contains("urjeta"))
            #expect(expandedCopy.contains("tomáš"))
            #expect(expandedCopy.contains("maya"))
            #expect(!expandedCopy.contains("fourth climber"))
            #expect(expandedCopy.contains("see all"))

            // Then the tiles (no signed-in climber, so the rank tile reads its unranked
            // copy), then the catalog with search, in that order.
            #expect(expandedCopy.contains("ranked"))
            #expect(expandedCopy.contains("streak"))
            #expect(expandedCopy.contains("search climbs"))
            #expect(expandedCopy.contains("browse by steps"))

            let todayIndex = try #require(expandedCopy.range(of: "ascend activity today")?.lowerBound)
            let rankIndex = try #require(expandedCopy.range(of: "ranked")?.lowerBound)
            let browseIndex = try #require(expandedCopy.range(of: "browse by steps")?.lowerBound)
            #expect(todayIndex < rankIndex)
            #expect(rankIndex < browseIndex)

            try hosted.photograph(named: "home-globe-sheet-expanded")
        }
    }

    @Test
    func collapsedTheMapEndsAtTheSheetAndTheLineSitsInsideTheFold() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .compact)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let line = try #require(await hosted.frame(ofElementLabelled: "This week:"))
            let sheet = try #require(await hosted.frame(ofElementLabelled: "Home sheet"))
            let mapView = try #require(Self.firstMapView(under: hosted.window))
            let map = mapView.convert(mapView.bounds, to: hosted.window)

            // The map is the band above the collapsed sheet, not the whole screen, so the
            // whole globe fits the width of the phone and MapKit's attribution stays
            // above the sheet's fold.
            #expect(abs(map.maxY - sheet.minY) <= 1, "map ends at the collapsed sheet's top, got map \(map) sheet \(sheet)")
            #expect(map.maxY < hosted.bounds.maxY - 80, "the map is no longer full screen")
            #expect(map.minY <= 0, "the map still reaches the top edge")
            #expect(map.width == hosted.bounds.width)

            // The line sits inside the collapsed fold: the 30pt row starts 8pt under the
            // 26pt grabber, so its centre is 49pt below the sheet's top and its bottom
            // edge 22pt above the 86pt fold.
            #expect(abs(line.midY - (sheet.minY + 49)) <= 1, "the line's centre sits 49pt under the sheet top, got \(line) in \(sheet)")
            #expect(line.midY + 15 <= sheet.minY + 86, "the line is above the 86pt fold")
        }
    }

    @Test
    func pulledUpTodaysClimbFollowsTheLineAtTheSheetsOwnStep() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .medium)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let line = try #require(await hosted.frame(ofElementLabelled: "This week:"))
            let card = try #require(await hosted.frame(ofElementLabelled: "Today's climb:"))
            // What follows Today's Climb: a running event's card, else ASCEND ACTIVITY TODAY.
            let section: CGRect
            if let event = Self.runningEvent {
                section = try #require(await hosted.frame(ofElementLabelled: "\(event.title) is on."))
            } else {
                let texts = try await hosted.texts { texts in
                    texts.contains { $0.text.caseInsensitiveCompare("ascend activity today") == .orderedSame }
                }
                section = try #require(texts.first { $0.text.caseInsensitiveCompare("ascend activity today") == .orderedSame }?.frame)
            }

            // The line's accessibility frame is its glyphs, centred in the 30pt row, and the
            // card's includes the half-point of stroke outside its layout edge. 22pt step
            // plus the 2pt under-fold spacer: 24pt, where it was 38pt.
            let lineToCard = (card.minY + 0.5) - (line.midY + 15)
            #expect(abs(lineToCard - 24) <= 1, "This Week line to Today's Climb card is \(lineToCard)pt, line \(line) card \(card)")

            // The card-to-next-section gap stays at the 22pt step.
            let cardToSection = section.minY - (card.maxY - 0.5)
            #expect(abs(cardToSection - 22) <= 3, "Today's Climb card to the next section is \(cardToSection)pt, card \(card) section \(section)")

            try hosted.photograph(named: "home-globe-sheet-medium-gap")
        }
    }

    /// Zoomed in, the band above the collapsed sheet is bright map all the way down,
    /// and the bottom vignette has to reach the map's bottom edge: a gradient ending
    /// one safe-area inset short of it left a 34pt strip of map at full brightness
    /// directly under the gradient's darkest stop, a bright line across the bottom of
    /// the globe just above the fold. Tiles need the network, so the probe is what
    /// MapKit draws itself: the attribution at the map's bottom edge, dim under the
    /// vignette and white when nothing covers it.
    @Test
    func zoomedInTheVignetteReachesTheMapsBottomEdge() async throws {
        let globeViewModel = Self.makeGlobeViewModel()
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .compact, globeViewModel: globeViewModel)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            globeViewModel.userDidInteract()
            globeViewModel.cameraPosition = .camera(
                MapCamera(centerCoordinate: Self.zoomedInCentre, distance: Self.zoomedInDistance, heading: 0, pitch: 0)
            )
            try await hosted.settle(.turns(60, interval: .milliseconds(100)))

            let sheet = try #require(await hosted.frame(ofElementLabelled: "Home sheet"))
            let mapView = try #require(Self.firstMapView(under: hosted.window))
            let map = mapView.convert(mapView.bounds, to: hosted.window)
            #expect(abs(map.maxY - sheet.minY) <= 1, "map ends at the collapsed sheet's top, got map \(map) sheet \(sheet)")

            let attribution = try #require(
                Self.attributionFrames(in: mapView, window: hosted.window).first,
                "MapKit draws its attribution at the map's bottom edge"
            )
            let report = try hosted.withPixels { pixels in
                pixels.inkReport(in: attribution, contrast: 0)
            }
            let brightest = try hosted.withPixels { pixels in
                pixels.luminanceRange(in: attribution).upperBound
            }
            #expect(
                brightest < 96,
                "the attribution at the map's bottom edge sits under the vignette, not in an uncovered strip: \(report)"
            )

            try hosted.photograph(named: "home-globe-zoomed-in-bottom-edge")
        }
    }

    /// Continent altitude over the Gulf of Mexico: land and sea fill the band above the
    /// sheet, the way the captain's own zoom did.
    private static let zoomedInCentre = CLLocationCoordinate2D(latitude: 18, longitude: -92)
    private static let zoomedInDistance: CLLocationDistance = 6_000_000

    private static func makeGlobeViewModel() -> GlobeViewModel {
        GlobeViewModel(
            communityStatsService: StaticLiveClimbCommunityStatsService(),
            leaderboardService: StubLiveReplayLeaderboardService()
        )
    }

    /// MapKit's attribution views (the Apple Maps logo and the Legal link): the small
    /// views it hangs off the bottom edge of the map, in window points.
    private static func attributionFrames(in mapView: MKMapView, window: UIWindow) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                let frame = subview.convert(subview.bounds, to: window)
                let mapFrame = mapView.convert(mapView.bounds, to: window)
                if !subview.isHidden,
                   subview.alpha > 0,
                   frame.height > 0, frame.height <= 32,
                   frame.width > 0, frame.width <= 160,
                   mapFrame.maxY - frame.maxY <= 24,
                   frame.maxY <= mapFrame.maxY + 0.5 {
                    frames.append(frame)
                }
                walk(subview)
            }
        }
        walk(mapView)
        return frames.sorted { $0.minX < $1.minX }
    }

    private static func firstMapView(under view: UIView) -> MKMapView? {
        if let map = view as? MKMapView { return map }
        for subview in view.subviews {
            if let map = firstMapView(under: subview) { return map }
        }
        return nil
    }

    @Test
    func aPersonalRoutineRowOpensNothingWhileTheOthersAreDoors() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .expanded)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let rows = try await hosted.elements { elements in
                elements.contains { ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains("maya") }
            }
            let mayaRow = try #require(rows.first { ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains("maya") })
            let urjetaRow = try #require(rows.first { ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains("urjeta") })

            #expect((urjetaRow.accessibilityHint ?? "").contains("Open climb detail"))
            #expect((mayaRow.accessibilityHint ?? "").isEmpty, "a personal routine is private, so its row is not a door")
        }
    }

    @Test
    func sessionsStoppedShortReachTheTodayRowsAndSayHowFarTheyGot() async throws {
        let screen = try await makeScreen(feed: Self.partialSessionFeed, detent: .expanded)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let copy = try await hosted.copy()

            // The Live Climb stopped short on its landmark reads its progress against the
            // climb's step count, never as a finish.
            #expect(copy.contains("shanghai tower"))
            #expect(copy.contains("2,342 of 3,398 steps"))
            // The template routine stopped early reads its time against the plan.
            #expect(copy.contains("07:00 of 20:00"))
            // The Just Climb stopped before its goal still reads "x of y".
            #expect(copy.contains("500 of 1,000 steps"))

            try hosted.photograph(named: "home-globe-sheet-partial-sessions")
        }
    }

    // MARK: - Screen

    private func makeScreen(
        feed: HomeTodayActivityFeed,
        detent: BrowseSheetDetent,
        globeViewModel: GlobeViewModel = makeGlobeViewModel(),
        container: ModelContainer? = nil,
        makeJustClimbSession: @escaping HomeView.JustClimbSessionFactory = HomeView.liveJustClimbSession
    ) async throws -> some View {
        let container = try container ?? ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let dashboard = HomeDashboardViewModel()
        let tabRouter = TabRouter()
        let todayActivity = HomeTodayActivityViewModel(service: StaticHomeTodayActivityService(feed: feed))
        let enrichmentService = AppleHealthEnrichmentService(
            authorizationController: EvidenceHealthAuthorization(),
            metricsReader: EvidenceMetricsReader(),
            attemptStore: AppleHealthEnrichmentAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator()
        )
        // Hydrated with no blocks, so the rows show the names the server sent rather
        // than the masked identity an unhydrated block list shows.
        let moderationStore = ModerationStore(repository: EmptyHomeModerationRepository())
        await moderationStore.hydrate(for: "home-evidence-user")

        return HostedHomeScreen(
            dashboard: dashboard,
            tabRouter: tabRouter,
            todayActivity: todayActivity,
            globeViewModel: globeViewModel,
            enrichmentService: enrichmentService,
            detent: detent,
            makeJustClimbSession: makeJustClimbSession
        )
        .preferredColorScheme(.dark)
        .environment(AuthenticationViewModel())
        .environment(NetworkConnectivityService.shared)
        .environment(moderationStore)
        .environment(tabRouter)
        .modelContainer(container)
    }

    private static let sampleFeed: HomeTodayActivityFeed = {
        let now = Date()
        func row(
            _ workoutId: String,
            userId: String,
            name: String,
            kind: HomeTodayActivityKind,
            climbId: String? = nil,
            templateId: String? = nil,
            goal: HomeTodayJustClimbGoalKind? = nil,
            goalValue: Int? = nil,
            minutesAgo: Int
        ) -> HomeTodayActivityRow {
            HomeTodayActivityRow(
                workoutId: workoutId,
                userId: userId,
                kind: kind,
                climbId: climbId,
                routineTemplateId: templateId,
                steps: 1_665,
                durationSeconds: 768,
                completedAt: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
                publishedAt: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
                justClimbGoalKind: goal,
                justClimbGoalValue: goalValue,
                displayName: name,
                photoURL: nil,
                avatarToken: String(name.prefix(2)).uppercased(),
                isSynthetic: false
            )
        }
        return HomeTodayActivityFeed(
            rows: [
                row("w1", userId: "user-1", name: "Urjeta Patel", kind: .liveClimb, climbId: Climb.preview.id, minutesAgo: 2),
                row("w2", userId: "user-2", name: "Tomáš Král", kind: .justClimb, goal: .duration, goalValue: 30, minutesAgo: 9),
                row("w3", userId: "user-3", name: "Maya Lindqvist", kind: .routine, minutesAgo: 60),
                row("w4", userId: "user-4", name: "Fourth Climber", kind: .liveClimb, climbId: Climb.preview.id, minutesAgo: 120),
            ],
            updatedAt: now
        )
    }()
}

extension HomeGlobeSheetEvidenceTests {
    /// Rows exactly as `onWorkoutWrittenHomeTodayActivity` writes them for sessions that
    /// stopped short, read through the same decoder Home's listener uses.
    fileprivate static let partialSessionFeed: HomeTodayActivityFeed = {
        let now = Date()
        func row(_ workoutId: String, name: String, kind: String, minutesAgo: Double, _ extra: [String: Any]) -> [String: Any] {
            var data: [String: Any] = [
                "workoutId": workoutId,
                "userId": "user-\(workoutId)",
                "kind": kind,
                "completedAt": Timestamp(date: now.addingTimeInterval(-minutesAgo * 60)),
                "publishedAt": Timestamp(date: now.addingTimeInterval(-minutesAgo * 60)),
                "displayName": name,
                "avatarToken": String(name.prefix(2)).uppercased(),
                "photoURL": "",
                "identityState": "published",
                "isSynthetic": false,
            ]
            data.merge(extra) { _, new in new }
            return data
        }
        return HomeTodayActivityFeedDecoder.feed(from: [
            "rows": [
                row("shanghai", name: "Captain Tyler", kind: "live_climb", minutesAgo: 2, [
                    "attemptClimbId": "shanghai-tower", "isPartial": true, "targetSteps": 3_398,
                    "steps": 2_342, "durationSeconds": 1_580,
                ]),
                row("routine", name: "Tomáš Král", kind: "routine_template", minutesAgo: 9, [
                    "routineTemplateId": "pyramid_climb", "isPartial": true, "targetDurationSeconds": 1_200,
                    "steps": 700, "durationSeconds": 420,
                ]),
                row("justclimb", name: "Maya Lindqvist", kind: "just_climb", minutesAgo: 15, [
                    "justClimbGoalKind": "steps", "justClimbGoalValue": 1_000, "isPartial": true,
                    "steps": 500, "durationSeconds": 300,
                ]),
            ],
            "updatedAt": Timestamp(date: now),
        ])
    }()
}

extension HomeGlobeSheetEvidenceTests {
    /// Start -> Just Climb -> START, tapped the way a climber taps it, and the session Home
    /// then builds and pushes.
    ///
    /// Home once kept the goal and the experience as two pieces of state and built the session
    /// inside the pushed destination, which SwiftUI evaluates with the state Home's last body
    /// pass captured. A climb started on the Mountain was therefore built Classic; the screen
    /// drew the Mountain anyway a moment later, and the Live Activity reopened that session as
    /// the Just Me page mid-climb (the captain's own climb, 2026-10-03). The tap now builds the
    /// session once, from what the sheet handed over, and the screen is that session.
    ///
    /// The stand-in session is Classic whatever was asked for, so no RealityKit scene is hosted
    /// and this runs on CI's virtual Macs (#629): what Home asked for is the assertion.
    @Test(
        "START builds one session, drawn the way the setup sheet said",
        arguments: [
            (JustClimbExperience?.none, JustClimbExperience.mountain),
            (JustClimbExperience.mountain, JustClimbExperience.mountain),
            (JustClimbExperience.classic, JustClimbExperience.classic),
        ]
    )
    func startBuildsOneSessionDrawnTheWayTheSetupSheetSaid(
        remembered: JustClimbExperience?,
        expected: JustClimbExperience
    ) async throws {
        let defaults = try #require(UserDefaults(suiteName: "home-just-climb-start-\(UUID().uuidString)"))
        if let remembered {
            defaults.set(remembered.rawValue, forKey: JustClimbSetupSheet.experienceKey)
        }
        let container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)
        let starts = JustClimbStartRecorder(container: container)
        let screen = try await makeScreen(
            feed: Self.sampleFeed,
            detent: .compact,
            container: container,
            makeJustClimbSession: starts.start
        )
        .defaultAppStorage(defaults)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            try activateAccessibilityElement(labelled: "Start", in: hosted.window)
            try await Self.activate(in: hosted) { $0.accessibilityLabel == "Just Climb" }
            try await Self.activate(in: hosted) {
                $0.accessibilityLabel == "START" && $0.accessibilityTraits.contains(.button)
            }

            let copy = try await hosted.copy { $0.contains("end attempt") }
            #expect(starts.requested == [expected], "what each START asked the session to be")
            #expect(copy.contains("1,842"), "the pushed screen is the session the tap built: \(copy)")
        }
        await starts.endSession()
    }

    /// Waits for a control to arrive and settle - a sheet animates in - then activates it.
    private static func activate(
        in hosted: HostedScreen,
        matching isMatch: @escaping (NSObject) -> Bool
    ) async throws {
        _ = try await hosted.elements { $0.contains(where: isMatch) }
        try await hosted.settle(.turns(10, interval: .milliseconds(100)))
        try activateAccessibilityElement(in: hosted.window, matching: isMatch)
    }
}

/// Hands Home one recording session, whatever it asks for, and remembers what it asked for.
@MainActor
private final class JustClimbStartRecorder {
    private(set) var requested: [JustClimbExperience] = []
    private let session: LiveClimbSessionViewModel
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stepCount = 1_842
        motionSession.duration = 504
        session = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            experience: .classic,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            backgroundSessionService: FakeLiveClimbBackgroundSession()
        )
        // Already recording, so the pushed screen draws the climb instead of the countdown and
        // the headphone gate the simulator cannot pass.
        session.start(modelContext: container.mainContext)
    }

    func start(_ goal: JustClimbGoal, _ experience: JustClimbExperience) -> LiveClimbSessionViewModel {
        requested.append(experience)
        return session
    }

    /// A running session is process-wide state; the next suite must not inherit it.
    func endSession() async {
        await session.discard(modelContext: container.mainContext)
    }
}

/// The real Home above the real tab bar, wired the way `MainTabView` wires them: the
/// bar's measured height reaches Home through the environment so the sheet measures
/// its resting heights from the bar's top.
private struct HostedHomeScreen: View {
    let dashboard: HomeDashboardViewModel
    let tabRouter: TabRouter
    let todayActivity: HomeTodayActivityViewModel
    let globeViewModel: GlobeViewModel
    let enrichmentService: AppleHealthEnrichmentService
    let detent: BrowseSheetDetent
    let makeJustClimbSession: HomeView.JustClimbSessionFactory

    @State private var tabBarOverlayHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            HomeView(
                homeDashboard: dashboard,
                tabRouter: tabRouter,
                todayActivity: todayActivity,
                globeViewModel: globeViewModel,
                enrichmentService: enrichmentService,
                initialSheetDetent: detent,
                makeJustClimbSession: makeJustClimbSession
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBarView(
                tabs: TabItem.activeTabs,
                selectedTab: .home,
                effectiveColorScheme: .dark,
                status: nil,
                statusBackground: nil
            ) { _ in }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                tabBarOverlayHeight = height
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.tabBarOverlayHeight, tabBarOverlayHeight)
    }
}

/// A block list with nobody on it.
private actor EmptyHomeModerationRepository: ModerationRepositoryProtocol {
    func fetchBlockedClimbers(
        blockerUserId: String,
        source: BlockListReadSource
    ) async throws -> [BlockedClimber] {
        []
    }

    func block(blockerUserId: String, blockedUserId: String) async throws {}

    func unblock(blockerUserId: String, blockedUserId: String) async throws {}

    func submitReport(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) async throws {}
}

/// A feed that answers once with a fixed document, so the hosted Home never opens a
/// Firestore listener.
private struct StaticHomeTodayActivityService: HomeTodayActivityServicing {
    let feed: HomeTodayActivityFeed

    func feedUpdates() -> AsyncStream<HomeTodayActivityFeed> {
        AsyncStream { continuation in
            continuation.yield(feed)
        }
    }
}

/// A device that has never connected Apple Health, so the hosted Home schedules no
/// enrichment pass.
private final class EvidenceHealthAuthorization: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = false
    let hasRequestedAuthorization = false
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unknown
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .neverConnected

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { false }
}

@MainActor
private final class EvidenceMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        WorkoutMetrics()
    }
}
