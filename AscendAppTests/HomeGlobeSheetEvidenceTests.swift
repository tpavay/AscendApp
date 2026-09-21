import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Evidence for Home's sheet in each of its three positions, read off the accessibility
/// tree of the real `HomeView` hosted above the real tab bar. The globe itself is a
/// MapKit view whose annotations do not survive a hierarchy capture; its evidence is
/// `HomeGlobeSnapshotEvidenceTests`.
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
            #expect(copy.contains("pin colors by steps"))
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

    private func makeScreen(feed: HomeTodayActivityFeed, detent: BrowseSheetDetent) async throws -> some View {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let dashboard = HomeDashboardViewModel()
        let tabRouter = TabRouter()
        let todayActivity = HomeTodayActivityViewModel(service: StaticHomeTodayActivityService(feed: feed))
        // Hydrated with no blocks, so the rows show the names the server sent rather
        // than the masked identity an unhydrated block list shows.
        let moderationStore = ModerationStore(repository: EmptyHomeModerationRepository())
        await moderationStore.hydrate(for: "home-evidence-user")

        return HostedHomeScreen(
            dashboard: dashboard,
            tabRouter: tabRouter,
            todayActivity: todayActivity,
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
    let detent: BrowseSheetDetent

    @State private var tabBarOverlayHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            HomeView(
                homeDashboard: dashboard,
                tabRouter: tabRouter,
                todayActivity: todayActivity,
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
