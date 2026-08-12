import Foundation

struct LeaderboardViewAnalyticsRecorder {
    private var hasRecordedVisibleVisit = false

    mutating func recordVisibleVisitIfNeeded(
        context: LeaderboardAnalyticsContext,
        source: LeaderboardAnalyticsEvent.ViewSource,
        telemetry: TelemetryManager = .shared
    ) {
        guard hasRecordedVisibleVisit == false else { return }
        hasRecordedVisibleVisit = true

        telemetry.track(
            LeaderboardAnalyticsEvent.viewed(
                context: context,
                source: source
            )
        )
    }
}
