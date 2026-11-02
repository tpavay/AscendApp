import Foundation

/// Today's pick for each of the Climb sheet's two lists, already worded for the row.
///
/// A nil line means the row has no pick to name and falls back to what it is for.
struct HomeStartPicks: Equatable, Sendable {
    var landmarkLine: String?
    var routineLine: String?

    static let none = HomeStartPicks()

    init(landmarkLine: String? = nil, routineLine: String? = nil) {
        self.landmarkLine = landmarkLine
        self.routineLine = routineLine
    }

    init(landmark: Climb?, routine: DailyRoutineRecommendationPolicy.Pick?) {
        self.init(
            landmarkLine: landmark.map {
                "Today: \($0.name) · \($0.referenceStepCount.formatted()) steps"
            },
            routineLine: routine.map {
                "Today: \($0.name) · \($0.durationMinutes) min"
            }
        )
    }

    func line(for action: HomeStartAction) -> String? {
        switch action {
        case .justClimb:
            return nil
        case .browseClimbs:
            return landmarkLine
        case .routines:
            return routineLine
        }
    }
}
