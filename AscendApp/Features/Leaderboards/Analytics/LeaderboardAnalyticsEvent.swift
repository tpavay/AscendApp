import Foundation

struct LeaderboardAnalyticsContext: Sendable, Hashable {
    let metric: String
    let timeFrame: String
    let ageGroup: String
    let bodyWeightFilter: String
    let locationFilter: String
    let activeFilterCount: Int

    init(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        ageGroup: LeaderboardAgeGroup?,
        bodyWeightFilter: LeaderboardBodyWeightFilter,
        locationFilter: LeaderboardLocationFilter
    ) {
        self.metric = metric.rawValue
        self.timeFrame = timeFrame.rawValue
        self.ageGroup = ageGroup?.rawValue ?? "all"
        self.bodyWeightFilter = bodyWeightFilter.rawValue
        self.locationFilter = locationFilter.rawValue
        self.activeFilterCount = [
            ageGroup != nil,
            bodyWeightFilter != .all,
            locationFilter != .all
        ].filter { $0 }.count
    }
}

enum LeaderboardAnalyticsEvent: TelemetryEvent {
    case demographicFilterChanged(
        context: LeaderboardAnalyticsContext,
        filterType: FilterType,
        selectedValue: String
    )
    case demographicFiltersCleared(context: LeaderboardAnalyticsContext)

    var record: TelemetryRecord {
        switch self {
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
    enum FilterType: String, Sendable {
        case ageGroup = "age_group"
        case bodyWeight = "body_weight"
        case location
    }
}

private extension LeaderboardAnalyticsContext {
    var parameters: [String: TelemetryValue] {
        [
            "metric": .string(metric),
            "time_frame": .string(timeFrame),
            "age_group": .string(ageGroup),
            "body_weight_filter": .string(bodyWeightFilter),
            "location_filter": .string(locationFilter),
            "active_filter_count": .int(activeFilterCount)
        ]
    }
}
