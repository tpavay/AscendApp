import Foundation
import Testing
@testable import AscendApp

/// What a today row says and where it leads, for every session kind the server sends.
@MainActor
struct HomeTodayActivityRowPresentationTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test
    func aLiveClimbNamesTheLandmarkAndOpensClimbDetail() {
        let presentation = HomeTodayActivityRowPresentation(
            row: moderated(kind: .liveClimb, climbId: "eiffel-tower", steps: 1_665, duration: 768, publishedAt: now.addingTimeInterval(-120)),
            climbName: "Eiffel Tower",
            routineTemplateName: nil,
            now: now
        )

        #expect(presentation.title == "Eiffel Tower")
        #expect(presentation.detail == "12:48 · 1,665 steps · 2 min ago")
        #expect(presentation.destination == .climbDetail(climbId: "eiffel-tower"))
        #expect(presentation.isTappable)
    }

    @Test
    func aJustClimbStatesItsGoalAndReopensTheSameOne() {
        let duration = HomeTodayActivityRowPresentation(
            row: moderated(kind: .justClimb, steps: 2_140, duration: 1_736, goalKind: .duration, goalValue: 30, publishedAt: now.addingTimeInterval(-9 * 60)),
            climbName: nil,
            routineTemplateName: nil,
            now: now
        )
        #expect(duration.title == "Just Climb")
        #expect(duration.detail == "28:56 of 30 min · 2,140 steps · 9 min ago")
        #expect(reopenedGoal(duration)?.kind == .duration)
        #expect(reopenedGoal(duration)?.durationMinutes == 30)

        let steps = HomeTodayActivityRowPresentation(
            row: moderated(kind: .justClimb, steps: 1_310, duration: 700, goalKind: .steps, goalValue: 1_500, publishedAt: now.addingTimeInterval(-3_600)),
            climbName: nil,
            routineTemplateName: nil,
            now: now
        )
        #expect(steps.detail == "1,310 of 1,500 steps · 11:40 · 1 h ago")

        let open = HomeTodayActivityRowPresentation(
            row: moderated(kind: .justClimb, steps: 900, duration: 600, goalKind: .open, publishedAt: now.addingTimeInterval(-30)),
            climbName: nil,
            routineTemplateName: nil,
            now: now
        )
        #expect(open.detail == "10:00 · 900 steps · just now")
        #expect(reopenedGoal(open)?.kind == .open)
        #expect(open.isTappable)
    }

    @Test
    func aCatalogRoutineOpensInTrainingAndAPersonalRoutineOpensNothing() {
        let template = HomeTodayActivityRowPresentation(
            row: moderated(kind: .routineTemplate, routineTemplateId: "pyramid_climb", steps: 1_310, duration: 1_200, publishedAt: now.addingTimeInterval(-2 * 86_400)),
            climbName: nil,
            routineTemplateName: "Pyramid Climb",
            now: now
        )
        #expect(template.title == "Pyramid Climb")
        #expect(template.detail == "20:00 · 1,310 steps · 2 d ago")
        #expect(template.destination == .routineTemplate(templateId: "pyramid_climb"))

        let personal = HomeTodayActivityRowPresentation(
            row: moderated(kind: .routine, steps: 800, duration: 600, publishedAt: now),
            climbName: nil,
            routineTemplateName: nil,
            now: now
        )
        #expect(personal.title == "Routine")
        #expect(personal.destination == .none)
        #expect(!personal.isTappable)
    }

    @Test
    func anUnknownLandmarkStillReadsAsALiveClimbButOpensNothing() {
        let presentation = HomeTodayActivityRowPresentation(
            row: moderated(kind: .liveClimb, climbId: "retired-climb", steps: 100, duration: 60, publishedAt: now),
            climbName: nil,
            routineTemplateName: nil,
            now: now
        )
        #expect(presentation.title == "Live Climb")
        // The catalog cannot name it, so there is no Climb Detail to open: no chevron,
        // no enabled row that silently does nothing.
        #expect(presentation.destination == .none)
        #expect(!presentation.isTappable)
    }

    // MARK: - Fixtures

    /// The goal a Just Climb row re-opens. `JustClimbGoal` carries a fresh id, so the
    /// destination is read by case rather than compared whole.
    private func reopenedGoal(_ presentation: HomeTodayActivityRowPresentation) -> JustClimbGoal? {
        if case .justClimb(let goal) = presentation.destination {
            return goal
        }
        return nil
    }

    private func moderated(
        kind: HomeTodayActivityKind,
        climbId: String? = nil,
        routineTemplateId: String? = nil,
        steps: Int,
        duration: TimeInterval,
        goalKind: HomeTodayJustClimbGoalKind? = nil,
        goalValue: Int? = nil,
        publishedAt: Date
    ) -> ModeratedHomeTodayActivityRow {
        let row = HomeTodayActivityRow(
            workoutId: "w",
            userId: "user-a",
            kind: kind,
            climbId: climbId,
            routineTemplateId: routineTemplateId,
            steps: steps,
            durationSeconds: duration,
            completedAt: publishedAt,
            publishedAt: publishedAt,
            justClimbGoalKind: goalKind,
            justClimbGoalValue: goalValue,
            displayName: "Ada",
            photoURL: nil,
            avatarToken: "AE7",
            isSynthetic: false
        )
        return CrossUserIdentityAdapter.homeTodayRow(row, blockedUserIds: [], isBlockListHydrated: true)
    }
}
