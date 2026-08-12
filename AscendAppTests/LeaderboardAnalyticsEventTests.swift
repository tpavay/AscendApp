import Testing
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
            source: .metricDetail
        ).record

        #expect(record.name == "leaderboard_viewed")
        #expect(
            record.parameters == [
                "source": .string("metric_detail"),
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

    @Test
    func rerendersAndFilterChangesDoNotEmitAnotherViewEvent() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        var recorder = LeaderboardViewAnalyticsRecorder()

        recorder.recordVisibleVisitIfNeeded(
            context: LeaderboardAnalyticsContext(
                metric: .climb,
                timeFrame: .weekly,
                ageGroup: nil,
                bodyWeightFilter: .all,
                locationFilter: .all
            ),
            source: .tab,
            telemetry: telemetry
        )
        recorder.recordVisibleVisitIfNeeded(
            context: LeaderboardAnalyticsContext(
                metric: .duration,
                timeFrame: .allTime,
                ageGroup: .age40To44,
                bodyWeightFilter: .pounds200Plus,
                locationFilter: .currentRegion
            ),
            source: .tab,
            telemetry: telemetry
        )

        let viewEvents = sink.records.filter { $0.name == "leaderboard_viewed" }
        #expect(viewEvents.count == 1)
        #expect(viewEvents.first?.parameters["metric"] == .string("climb"))
        #expect(viewEvents.first?.parameters["has_active_filters"] == .bool(false))
    }

    @Test(
        arguments: [
            (LeaderboardAnalyticsEvent.ViewSource.tab, "tab"),
            (.metricDetail, "metric_detail")
        ]
    )
    func viewSourcesHaveStableBoundedValues(
        source: LeaderboardAnalyticsEvent.ViewSource,
        expectedValue: String
    ) {
        #expect(source.rawValue == expectedValue)
    }

    @Test
    func routeShapeSelectsTheBoundedViewSource() {
        #expect(LeaderboardAnalyticsEvent.ViewSource(lockedMetric: nil) == .tab)

        for metric in LeaderboardMetric.allCases {
            #expect(
                LeaderboardAnalyticsEvent.ViewSource(lockedMetric: metric) == .metricDetail
            )
        }
    }
}
