import CoreLocation
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
    @Test
    func theSheetOpensCollapsedToTheThisWeekLine() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .compact)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            let copy = try await hosted.copy()

            // Collapsed: the This Week line is on screen, the rest of the sheet is below the fold.
            #expect(copy.contains("this week"))
            #expect(!copy.contains("on the globe today"))
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
            #expect(mediumCopy.contains("on the globe today"))
            try hosted.photograph(named: "home-globe-sheet-medium")
        }
    }

    @Test
    func expandedTheSheetCarriesTheThreeRowsThenTheTilesThenTheCatalog() async throws {
        let screen = try await makeScreen(feed: Self.sampleFeed, detent: .expanded)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
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

            let todayIndex = try #require(expandedCopy.range(of: "on the globe today")?.lowerBound)
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
            let texts = try await hosted.texts { texts in
                texts.contains { $0.text.caseInsensitiveCompare("on the globe today") == .orderedSame }
            }
            let section = try #require(texts.first { $0.text.caseInsensitiveCompare("on the globe today") == .orderedSame }?.frame)

            // The line's accessibility frame is its glyphs, centred in the 30pt row, and the
            // card's includes the half-point of stroke outside its layout edge. 22pt step
            // plus the 2pt under-fold spacer: 24pt, where it was 38pt.
            let lineToCard = (card.minY + 0.5) - (line.midY + 15)
            #expect(abs(lineToCard - 24) <= 1, "This Week line to Today's Climb card is \(lineToCard)pt, line \(line) card \(card)")

            // The card-to-next-section gap stays at the 22pt step.
            let cardToSection = section.minY - (card.maxY - 0.5)
            #expect(abs(cardToSection - 22) <= 3, "Today's Climb card to ON THE GLOBE TODAY is \(cardToSection)pt, card \(card) section \(section)")

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

    // MARK: - Screen

    private func makeScreen(
        feed: HomeTodayActivityFeed,
        detent: BrowseSheetDetent,
        globeViewModel: GlobeViewModel = makeGlobeViewModel()
    ) async throws -> some View {
        let container = try ModelContainer(
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
            detent: detent
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

    @State private var tabBarOverlayHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            HomeView(
                homeDashboard: dashboard,
                tabRouter: tabRouter,
                todayActivity: todayActivity,
                globeViewModel: globeViewModel,
                enrichmentService: enrichmentService,
                initialSheetDetent: detent
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
