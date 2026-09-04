import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Hosts real windows (through `RenderedScreen`, never capturing them) for the
/// once-per-route-instance cases, so it takes the same gate every other hosting
/// suite takes rather than starving one mid-capture.
@MainActor
@Suite(.serialized, .hostsAWindow)
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

    @Test
    func repeatedRendersAndFilterChangesEmitNoSecondViewEvent() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let filters = LeaderboardViewEventHarnessFilters()

        try await RenderedScreen.host(
            LeaderboardViewEventHarness(filters: filters, telemetry: telemetry),
            size: Self.hostSize,
            settle: Self.oneTurn
        ) { screen in
            let emitted = try await pump(screen) { sink.viewEventCount == 1 }
            #expect(emitted)

            let rendersBeforeFilterChange = filters.renderCount
            filters.metric = .duration
            filters.ageGroup = .age40To44

            let rerendered = try await pump(screen) { filters.renderCount > rendersBeforeFilterChange }
            #expect(rerendered)

            try await drain(screen)

            let viewEvents = sink.records.filter { $0.name == "leaderboard_viewed" }
            #expect(viewEvents.count == 1)
            #expect(viewEvents.first?.parameters["metric"] == .string("climb"))
            #expect(viewEvents.first?.parameters["source"] == .string("tab"))
            #expect(viewEvents.first?.parameters["has_active_filters"] == .bool(false))
        }
    }

    /// The dedupe belongs to the route instance, not to the app: a board rebuilt
    /// for a later visit reports that visit.
    @Test
    func aReconstructedRouteVisitEmitsAgain() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        for visit in 1...2 {
            let emitted = try await RenderedScreen.host(
                LeaderboardViewEventHarness(
                    filters: LeaderboardViewEventHarnessFilters(),
                    telemetry: telemetry
                ),
                size: Self.hostSize,
                settle: Self.oneTurn
            ) { screen in
                try await pump(screen) { sink.viewEventCount == visit }
            }

            #expect(emitted)
        }

        #expect(sink.viewEventCount == 2)
    }

    /// Screen views ride the same once-per-instance guard, so view-level tracking
    /// has one mechanism rather than two.
    @Test
    func screenViewsEmitOnceThroughTheSameGuard() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let filters = LeaderboardViewEventHarnessFilters()

        try await RenderedScreen.host(
            TrackOnceScreenHarness(filters: filters, telemetry: telemetry),
            size: Self.hostSize,
            settle: Self.oneTurn
        ) { screen in
            let emitted = try await pump(screen) { sink.screens.isEmpty == false }
            #expect(emitted)

            let rendersBeforeChange = filters.renderCount
            filters.metric = .duration
            let rerendered = try await pump(screen) { filters.renderCount > rendersBeforeChange }
            #expect(rerendered)

            try await drain(screen)

            #expect(sink.screens.count == 1)
            #expect(sink.screens.first?.name == "leaderboard")
        }
    }

    /// The rank-card entry survives the selection binding `MainTabView` hands to
    /// SwiftUI, which is the one place an echoed write could downgrade it to `tab`.
    @Test
    func mainTabViewKeepsTheRankCardEntryDistinctFromTheTab() async throws {
        let router = TabRouter()
        router.select(.leaderboard, reason: .homeRankCard)

        try await RenderedScreen.host(
            try mainTabView(tabRouter: router),
            size: Self.hostSize,
            settle: Self.oneTurn
        ) { screen in
            try await drain(screen)

            #expect(router.selectedTab == .leaderboard)
            #expect(router.selectionReason == .homeRankCard)
            #expect(
                LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .homeRankCard
            )

            router.select(.home, reason: .appRouting)
            router.select(.leaderboard, reason: .tabBarTap)
            try await drain(screen)

            #expect(router.selectionReason == .tabBarTap)
            #expect(LeaderboardAnalyticsEvent.ViewSource(tabSelection: router.selectionReason) == .tab)
        }
    }

    // MARK: - Rendering

    private static let hostSize = CGSize(width: 390, height: 640)

    /// The pumps below wait on their own conditions, so the host hands over after one turn
    /// rather than the twelve a screenshot needs.
    private static let oneTurn = RenderedScreen.Settle.turns(1, interval: .milliseconds(10))

    private func mainTabView(tabRouter: TabRouter) throws -> some View {
        let container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)

        return MainTabView(tabRouter: tabRouter)
            .environment(AuthenticationViewModel())
            .environment(ModerationStore.shared)
            .environment(NetworkConnectivityService.shared)
            .modelContainer(container)
    }

    /// Drives layout until the condition holds, so a slow machine costs latency
    /// rather than a red build.
    private func pump(
        _ screen: HostedScreen,
        iterations: Int = 200,
        until isSatisfied: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<iterations {
            try await screen.settle(.turns(1, interval: .milliseconds(10)))

            if isSatisfied() {
                return true
            }
        }

        return false
    }

    /// A bounded drain for the assertions that something did NOT happen - there
    /// is no condition to wait on, only a window in which it could have.
    private func drain(_ screen: HostedScreen, iterations: Int = 12) async throws {
        _ = try await pump(screen, iterations: iterations) { false }
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
