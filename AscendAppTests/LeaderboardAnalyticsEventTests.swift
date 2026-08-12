import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

struct LeaderboardAnalyticsEventTests {
    @Test
    func visibleLeaderboardVisitCarriesTheCompleteBoundedContext() {
        let context = LeaderboardAnalyticsContext(
            metric: .pace,
            timeFrame: .monthly,
            ageGroup: .age30To34,
            bodyWeightFilter: .pounds200Plus,
            locationFilter: .currentCountry
        )

        let record = LeaderboardAnalyticsEvent.viewed(
            context: context,
            source: .homeRankCard
        ).record

        #expect(record.name == "leaderboard_viewed")
        #expect(
            record.parameters == [
                "source": .string("home_rank_card"),
                "metric": .string("pace"),
                "time_frame": .string("monthly"),
                "has_active_filters": .bool(true)
            ]
        )
        #expect(record.destinations == [.analytics])
    }

    @Test
    func leaderboardWithoutDemographicFiltersReportsNoActiveFilters() {
        let context = LeaderboardAnalyticsContext(
            metric: .climb,
            timeFrame: .weekly,
            ageGroup: nil,
            bodyWeightFilter: .all,
            locationFilter: .all
        )

        let record = LeaderboardAnalyticsEvent.viewed(
            context: context,
            source: .tab
        ).record

        #expect(record.parameters["has_active_filters"] == .bool(false))
    }

    /// The count is derived, so it cannot drift away from the filters it describes.
    @Test
    func activeFilterCountTracksTheTypedFilters() {
        #expect(
            LeaderboardAnalyticsContext(
                metric: .climb,
                timeFrame: .weekly,
                ageGroup: nil,
                bodyWeightFilter: .all,
                locationFilter: .all
            ).activeFilterCount == 0
        )

        #expect(
            LeaderboardAnalyticsContext(
                metric: .climb,
                timeFrame: .weekly,
                ageGroup: .age30To34,
                bodyWeightFilter: .all,
                locationFilter: .currentRegion
            ).activeFilterCount == 2
        )

        #expect(
            LeaderboardAnalyticsContext(
                metric: .climb,
                timeFrame: .weekly,
                ageGroup: .age40To44,
                bodyWeightFilter: .pounds200Plus,
                locationFilter: .currentCountry
            ).activeFilterCount == 3
        )
    }

    /// Pins the whole bounded set, so a third source cannot ship with an
    /// unasserted wire value.
    @Test
    func viewSourcesHaveStableBoundedValues() {
        let expectedValues: [LeaderboardAnalyticsEvent.ViewSource: String] = [
            .tab: "tab",
            .homeRankCard: "home_rank_card"
        ]

        #expect(Set(LeaderboardAnalyticsEvent.ViewSource.allCases) == Set(expectedValues.keys))

        for source in LeaderboardAnalyticsEvent.ViewSource.allCases {
            #expect(source.rawValue == expectedValues[source])
        }
    }

    /// The metric-detail route was removed from the app, so its source may not
    /// linger as a value nothing can produce.
    @Test
    func theRemovedMetricDetailSourceCannotExist() {
        #expect(
            LeaderboardAnalyticsEvent.ViewSource.allCases
                .contains { $0.rawValue == "metric_detail" } == false
        )
    }

    @MainActor
    @Test
    func eachRealEntryIntoTheBoardMapsToItsOwnSource() {
        let tapped = TabRouter()
        tapped.select(.leaderboard, reason: .tabBarTap)
        #expect(tapped.selectedTab == .leaderboard)
        #expect(LeaderboardAnalyticsEvent.ViewSource(tabSelection: tapped.selectionReason) == .tab)

        let rankCard = TabRouter()
        rankCard.select(.leaderboard, reason: .homeRankCard)
        #expect(rankCard.selectedTab == .leaderboard)
        #expect(
            LeaderboardAnalyticsEvent.ViewSource(tabSelection: rankCard.selectionReason) == .homeRankCard
        )
    }

    /// A tab change that names no entry point reports the tab rather than
    /// inheriting the last named entry's attribution.
    @MainActor
    @Test
    func anUnattributedTabChangeReportsTheTab() {
        let router = TabRouter()
        router.select(.leaderboard, reason: .homeRankCard)
        router.select(.home, reason: .appRouting)
        router.select(.leaderboard, reason: .appRouting)

        #expect(router.selectionReason == .appRouting)
        #expect(LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .tab)
        #expect(LeaderboardAnalyticsEvent.ViewSource(tabSelection: TabRouter().selectionReason) == .tab)
    }

    /// Re-selecting the tab already showing is what a SwiftUI selection binding
    /// echoes back, and it may not downgrade the entry that put the climber there.
    @MainActor
    @Test
    func reselectingTheShowingTabKeepsItsAttribution() {
        let router = TabRouter()
        router.select(.leaderboard, reason: .homeRankCard)
        router.select(.leaderboard, reason: .appRouting)
        router.select(.leaderboard, reason: .tabBarTap)

        #expect(router.selectionReason == .homeRankCard)
        #expect(
            LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .homeRankCard
        )
    }

    @Test(arguments: TabSelectionReason.allCases)
    func everyTabSelectionReasonResolvesToABoundedSource(reason: TabSelectionReason) {
        let source = LeaderboardAnalyticsEvent.ViewSource(tabSelection: reason)

        #expect(source == (reason == .homeRankCard ? .homeRankCard : .tab))
        #expect(LeaderboardAnalyticsEvent.ViewSource.allCases.contains(source))
    }

    @MainActor
    @Test
    func repeatedRendersAndFilterChangesEmitNoSecondViewEvent() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let filters = LeaderboardViewEventHarnessFilters()

        let window = hostWindow(
            LeaderboardViewEventHarness(filters: filters, telemetry: telemetry)
        )
        defer { teardown(window) }

        let emitted = try await pump(window) { sink.viewEventCount == 1 }
        #expect(emitted)

        let rendersBeforeFilterChange = filters.renderCount
        filters.metric = .duration
        filters.ageGroup = .age40To44

        let rerendered = try await pump(window) { filters.renderCount > rendersBeforeFilterChange }
        #expect(rerendered)

        try await drain(window)

        let viewEvents = sink.records.filter { $0.name == "leaderboard_viewed" }
        #expect(viewEvents.count == 1)
        #expect(viewEvents.first?.parameters["metric"] == .string("climb"))
        #expect(viewEvents.first?.parameters["source"] == .string("tab"))
        #expect(viewEvents.first?.parameters["has_active_filters"] == .bool(false))
    }

    /// The dedupe belongs to the route instance, not to the app: a board rebuilt
    /// for a later visit reports that visit.
    @MainActor
    @Test
    func aReconstructedRouteVisitEmitsAgain() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        for visit in 1...2 {
            let window = hostWindow(
                LeaderboardViewEventHarness(
                    filters: LeaderboardViewEventHarnessFilters(),
                    telemetry: telemetry
                )
            )
            let emitted = try await pump(window) { sink.viewEventCount == visit }
            teardown(window)

            #expect(emitted)
        }

        #expect(sink.viewEventCount == 2)
    }

    /// Screen views ride the same once-per-instance guard, so view-level tracking
    /// has one mechanism rather than two.
    @MainActor
    @Test
    func screenViewsEmitOnceThroughTheSameGuard() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let filters = LeaderboardViewEventHarnessFilters()

        let window = hostWindow(
            TrackOnceScreenHarness(filters: filters, telemetry: telemetry)
        )
        defer { teardown(window) }

        let emitted = try await pump(window) { sink.screens.isEmpty == false }
        #expect(emitted)

        let rendersBeforeChange = filters.renderCount
        filters.metric = .duration
        let rerendered = try await pump(window) { filters.renderCount > rendersBeforeChange }
        #expect(rerendered)

        try await drain(window)

        #expect(sink.screens.count == 1)
        #expect(sink.screens.first?.name == "leaderboard")
    }

    /// The rank-card entry survives the selection binding `MainTabView` hands to
    /// SwiftUI, which is the one place an echoed write could downgrade it to `tab`.
    @MainActor
    @Test
    func mainTabViewKeepsTheRankCardEntryDistinctFromTheTab() async throws {
        let router = TabRouter()
        router.select(.leaderboard, reason: .homeRankCard)

        let window = hostWindow(try mainTabView(tabRouter: router))
        defer { teardown(window) }

        try await drain(window)

        #expect(router.selectedTab == .leaderboard)
        #expect(router.selectionReason == .homeRankCard)
        #expect(
            LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .homeRankCard
        )

        router.select(.home, reason: .appRouting)
        router.select(.leaderboard, reason: .tabBarTap)
        try await drain(window)

        #expect(router.selectionReason == .tabBarTap)
        #expect(LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .tab)
    }

    // MARK: - Rendering

    @MainActor
    private func mainTabView(tabRouter: TabRouter) throws -> some View {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ActiveHeadphoneWorkoutDraft.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            LeaderboardStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return MainTabView(tabRouter: tabRouter)
            .environment(AuthenticationViewModel())
            .environment(ModerationStore.shared)
            .environment(NetworkConnectivityService.shared)
            .modelContainer(container)
    }

    @MainActor
    private func hostWindow(_ view: some View) -> UIWindow {
        let size = CGSize(width: 390, height: 640)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    @MainActor
    private func teardown(_ window: UIWindow) {
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Drives layout until the condition holds, so a slow machine costs latency
    /// rather than a red build.
    @MainActor
    private func pump(
        _ window: UIWindow,
        iterations: Int = 200,
        until isSatisfied: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<iterations {
            window.setNeedsLayout()
            window.layoutIfNeeded()

            if isSatisfied() {
                return true
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return false
    }

    /// A bounded drain for the assertions that something did NOT happen - there
    /// is no condition to wait on, only a window in which it could have.
    @MainActor
    private func drain(_ window: UIWindow, iterations: Int = 12) async throws {
        _ = try await pump(window, iterations: iterations) { false }
    }
}

private extension InMemoryTelemetrySink {
    var viewEventCount: Int {
        records.filter { $0.name == "leaderboard_viewed" }.count
    }
}

@MainActor
@Observable
private final class LeaderboardViewEventHarnessFilters {
    var metric: LeaderboardMetric = .climb
    var ageGroup: LeaderboardAgeGroup?

    /// Deliberately outside observation: the exclusion assertions are vacuous
    /// unless the harness proves a second render actually happened.
    @ObservationIgnored private(set) var renderCount = 0

    func recordRender() {
        renderCount += 1
    }
}

/// Exercises the shipped `trackOnce` modifier the board uses, so the exclusion
/// cases are proven against the real mechanism rather than a stand-in.
private struct LeaderboardViewEventHarness: View {
    let filters: LeaderboardViewEventHarnessFilters
    let telemetry: TelemetryManager

    var body: some View {
        let _ = filters.recordRender()

        Color.clear
            .frame(width: 100, height: 100)
            .trackOnce(
                LeaderboardAnalyticsEvent.viewed(
                    context: LeaderboardAnalyticsContext(
                        metric: filters.metric,
                        timeFrame: .weekly,
                        ageGroup: filters.ageGroup,
                        bodyWeightFilter: .all,
                        locationFilter: .all
                    ),
                    source: .tab
                ),
                telemetry: telemetry
            )
    }
}

private struct TrackOnceScreenHarness: View {
    let filters: LeaderboardViewEventHarnessFilters
    let telemetry: TelemetryManager

    var body: some View {
        let _ = filters.recordRender()

        Color.clear
            .frame(width: 100, height: 100)
            .trackOnce(
                screen: TelemetryScreen(
                    name: "leaderboard",
                    screenClass: "LeaderboardView",
                    parameters: ["metric": .string(filters.metric.rawValue)]
                ),
                telemetry: telemetry
            )
    }
}
