import Foundation

struct LeaderboardAnalyticsContext: Sendable {
    let metric: LeaderboardMetric
    let timeFrame: LeaderboardTimeFrame
    let ageGroup: LeaderboardAgeGroup?
    let bodyWeightFilter: LeaderboardBodyWeightFilter
    let locationFilter: LeaderboardLocationFilter

    var activeFilterCount: Int {
        [
            ageGroup != nil,
            bodyWeightFilter != .all,
            locationFilter != .all
        ].filter { $0 }.count
    }
}

enum LeaderboardAnalyticsEvent: TelemetryEvent {
    case viewed(
        context: LeaderboardAnalyticsContext,
        source: ViewSource
    )
    case demographicFilterChanged(
        context: LeaderboardAnalyticsContext,
        filterType: FilterType,
        selectedValue: String
    )
    case demographicFiltersCleared(context: LeaderboardAnalyticsContext)
    /// A load that did not get the server's standings on the first ask, so the rate of these is
    /// countable per release. Mirrors the non-fatal recorded under
    /// `LeaderboardRefreshFailure.errorCode`.
    case refreshFailed(
        context: LeaderboardAnalyticsContext,
        failure: LeaderboardRefreshFailure
    )

    var record: TelemetryRecord {
        switch self {
        case .viewed(let context, let source):
            return TelemetryRecord(
                name: "leaderboard_viewed",
                parameters: [
                    "source": .string(source.rawValue),
                    "metric": .string(context.metric.rawValue),
                    "time_frame": .string(context.timeFrame.rawValue),
                    "has_active_filters": .bool(context.activeFilterCount > 0)
                ]
            )

        case .demographicFilterChanged(let context, let filterType, let selectedValue):
            var parameters = context.parameters
            parameters["filter_group"] = .string("demographic")
            parameters["filter_type"] = .string(filterType.rawValue)
            parameters["selected_value"] = .string(selectedValue)
            parameters["has_active_filters"] = .bool(context.activeFilterCount > 0)

            return TelemetryRecord(
                name: "leaderboard_filter_changed",
                parameters: parameters
            )

        case .demographicFiltersCleared(let context):
            var parameters = context.parameters
            parameters["filter_group"] = .string("demographic")

            return TelemetryRecord(
                name: "leaderboard_filters_cleared",
                parameters: parameters
            )

        case .refreshFailed(let context, let failure):
            return TelemetryRecord(
                name: LeaderboardRefreshFailure.errorCode,
                parameters: [
                    "metric": .string(context.metric.rawValue),
                    "time_frame": .string(context.timeFrame.rawValue),
                    "failure_class": .string(failure.failureClass.rawValue),
                    "error_domain": .string(failure.errorDomain),
                    "error_code": .int(failure.errorCode),
                    "forced": .bool(failure.wasForced),
                    "retry_recovered": .bool(failure.retryRecovered),
                    "access_reconcile_attempted": .bool(failure.attemptedAccessRecovery),
                    "resolution": .string(failure.resolution.rawValue),
                    "network": .string(failure.context.networkInterface.rawValue),
                    "launch_age": .string(
                        LeaderboardRefreshFailure.ageBand(seconds: failure.context.secondsSinceLaunch)
                    ),
                    "foreground_age": .string(
                        LeaderboardRefreshFailure.ageBand(seconds: failure.context.secondsSinceForeground)
                    )
                ]
            )
        }
    }
}

extension LeaderboardAnalyticsEvent {
    /// The entry a climber used to reach the board. Exhaustive over
    /// `TabSelectionReason` on purpose: a new way into the leaderboard is a
    /// compile error here rather than an entry that silently reports as the tab.
    enum ViewSource: String, CaseIterable, Sendable {
        case tab
        case homeRankCard = "home_rank_card"

        init(tabSelection reason: TabSelectionReason) {
            switch reason {
            case .homeRankCard:
                self = .homeRankCard
            case .tabBarTap, .appLaunch, .appRouting:
                self = .tab
            }
        }
    }

    enum FilterType: String, Sendable {
        case ageGroup = "age_group"
        case bodyWeight = "body_weight"
        case location
    }
}

private extension LeaderboardAnalyticsContext {
    var parameters: [String: TelemetryValue] {
        [
            "metric": .string(metric.rawValue),
            "time_frame": .string(timeFrame.rawValue),
            "age_group": .string(ageGroup?.rawValue ?? "all"),
            "body_weight_filter": .string(bodyWeightFilter.rawValue),
            "location_filter": .string(locationFilter.rawValue),
            "active_filter_count": .int(activeFilterCount)
        ]
    }
}
