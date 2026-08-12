import Foundation

struct LeaderboardAnalyticsContext: Sendable {
    let metric: LeaderboardMetric
    let timeFrame: LeaderboardTimeFrame
    let ageGroup: LeaderboardAgeGroup?
    let bodyWeightFilter: LeaderboardBodyWeightFilter
    let locationFilter: LeaderboardLocationFilter
    let activeFilterCount: Int

    init(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        ageGroup: LeaderboardAgeGroup?,
        bodyWeightFilter: LeaderboardBodyWeightFilter,
        locationFilter: LeaderboardLocationFilter
    ) {
        self.metric = metric
        self.timeFrame = timeFrame
        self.ageGroup = ageGroup
        self.bodyWeightFilter = bodyWeightFilter
        self.locationFilter = locationFilter
        self.activeFilterCount = [
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
        }
    }
}

extension LeaderboardAnalyticsEvent {
    enum ViewSource: String, CaseIterable, Sendable {
        case tab
        case metricDetail = "metric_detail"

        init(lockedMetric: LeaderboardMetric?) {
            switch lockedMetric {
            case .none:
                self = .tab
            case .some:
                self = .metricDetail
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
