import Testing
@testable import AscendApp

struct HomeStartDestinationTests {
    private let routinePick = DailyRoutineRecommendationPolicy.Pick(
        templateId: "builtin-pyramid",
        name: "Pyramid",
        durationMinutes: 20
    )

    @Test
    func theLandmarkRowOpensTodaysPickAsAClimbSheetTapNotAHomeDailyTap() {
        let destination = HomeStartDestination(
            action: .browseClimbs,
            seeAll: false,
            landmark: .preview,
            routine: routinePick
        )

        #expect(destination == .climbDetail(.preview, entryPoint: .homeStartSheet))
        #expect(LiveClimbAnalyticsEvent.EntryPoint.homeStartSheet.rawValue == "home_start_sheet")
    }

    @Test
    func theLandmarkRowFallsBackToTheListWithoutAPickAndSeeAllAlwaysOpensIt() {
        #expect(
            HomeStartDestination(action: .browseClimbs, seeAll: false, landmark: nil, routine: nil)
                == .landmarkList
        )
        #expect(
            HomeStartDestination(action: .browseClimbs, seeAll: true, landmark: .preview, routine: nil)
                == .landmarkList
        )
    }

    @Test
    func theRoutineRowOpensTodaysPickAndSeeAllOpensTheRoutinesTab() {
        #expect(
            HomeStartDestination(action: .routines, seeAll: false, landmark: nil, routine: routinePick)
                == .routine(templateId: "builtin-pyramid")
        )
        #expect(
            HomeStartDestination(action: .routines, seeAll: true, landmark: nil, routine: routinePick)
                == .routinesTab
        )
        #expect(
            HomeStartDestination(action: .routines, seeAll: false, landmark: nil, routine: nil)
                == .routinesTab
        )
    }

    @Test
    func justClimbOpensItsSetup() {
        #expect(
            HomeStartDestination(action: .justClimb, seeAll: false, landmark: .preview, routine: routinePick)
                == .justClimbSetup
        )
    }
}
