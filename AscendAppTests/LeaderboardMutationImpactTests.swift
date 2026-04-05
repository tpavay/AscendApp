import Foundation
import Testing
@testable import AscendApp

struct LeaderboardMutationImpactTests {
    @Test
    func nonLeaderboardEditsDoNotTriggerAggregationWork() {
        let before = snapshot(id: UUID(), day: 5, hour: 7, duration: 1_800, steps: 1_200, floors: 75)
        let after = snapshot(id: before.id, day: 5, hour: 7, duration: 1_800, steps: 1_200, floors: 75)

        let impact = LeaderboardMutationImpact.classify(.updated(before: before, after: after))
        #expect(impact == .none)
    }

    @Test
    func relevantWorkoutFieldChangesProduceIncrementalChanges() {
        let before = snapshot(id: UUID(), day: 5, hour: 7, duration: 1_800, steps: 1_200, floors: 75)
        let after = snapshot(id: before.id, day: 6, hour: 7, duration: 2_100, steps: 1_500, floors: 94)

        let impact = LeaderboardMutationImpact.classify(.updated(before: before, after: after))
        guard case .incremental(let changes) = impact else {
            Issue.record("Expected incremental impact for leaderboard-relevant update.")
            return
        }

        #expect(changes.count == 1)
        #expect(changes.first?.before == before)
        #expect(changes.first?.after == after)
    }

    @Test
    func createAndDeleteMutationsAreTrackedIncrementally() {
        let created = snapshot(id: UUID(), day: 5, hour: 7, duration: 1_500, steps: 900, floors: 56)
        let deleted = snapshot(id: UUID(), day: 7, hour: 9, duration: 1_200, steps: 700, floors: 44)

        let impact = LeaderboardMutationImpact.classify(
            WorkoutMutation(created: [created], deleted: [deleted])
        )

        guard case .incremental(let changes) = impact else {
            Issue.record("Expected incremental impact for create/delete mutation.")
            return
        }

        #expect(changes.count == 2)
        #expect(changes.contains { $0.before == nil && $0.after == created })
        #expect(changes.contains { $0.before == deleted && $0.after == nil })
    }

    @Test
    func explicitFullRebuildWinsOverIncrementalPaths() {
        let impact = LeaderboardMutationImpact.classify(.rebuildAll)
        #expect(impact == .rebuildAll)
    }

    private func snapshot(
        id: UUID,
        day: Int,
        hour: Int,
        duration: TimeInterval,
        steps: Int,
        floors: Int
    ) -> LeaderboardWorkoutSnapshot {
        LeaderboardWorkoutSnapshot(
            id: id,
            date: utcDate(year: 2026, month: 4, day: day, hour: hour),
            duration: duration,
            steps: steps,
            floors: floors
        )
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
