import Foundation

/// Where a tap on one of the Climb sheet's rows, or its See all link, takes the climber.
enum HomeStartDestination: Equatable {
    case justClimbSetup
    case climbDetail(Climb, entryPoint: LiveClimbAnalyticsEvent.EntryPoint)
    case landmarkList
    case routine(templateId: String)
    case routinesTab

    init(
        action: HomeStartAction,
        seeAll: Bool,
        landmark: Climb?,
        routine: DailyRoutineRecommendationPolicy.Pick?
    ) {
        switch action {
        case .justClimb:
            self = .justClimbSetup
        case .browseClimbs:
            if !seeAll, let landmark {
                self = .climbDetail(landmark, entryPoint: .homeStartSheet)
            } else {
                self = .landmarkList
            }
        case .routines:
            if !seeAll, let routine {
                self = .routine(templateId: routine.templateId)
            } else {
                self = .routinesTab
            }
        }
    }
}
