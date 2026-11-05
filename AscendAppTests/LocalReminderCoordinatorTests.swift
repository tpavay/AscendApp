import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import AscendApp

@MainActor
private final class CoordinatorRecordingCenter: LocalReminderCenter {
    private(set) var added: [LocalReminderRequest] = []

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func add(_ request: LocalReminderRequest) async throws { added.append(request) }
    func removePending(identifiers: [String]) {}
}

/// The weekly nudge follows the week the climber is actually having: this week's climbs, read from
/// the store, change what it says and when it fires.
@MainActor
struct LocalReminderCoordinatorTests {
    private let calendar = WeekConfiguration.calendar()

    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func climb(on day: Int, in modelContext: ModelContext) {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 9))!
        modelContext.insert(Workout(date: date, duration: 1_200, steps: 1_000, floors: 63, source: .headphoneMotion))
    }

    private func coordinator(center: CoordinatorRecordingCenter, target: Int?, now: Date) -> LocalReminderCoordinator {
        LocalReminderCoordinator(
            scheduler: LocalReminderScheduler(
                center: center,
                featureFlags: RemoteFeatureFlagStore(snapshot: .shippedDefaults),
                isPreferenceEnabled: { true }
            ),
            target: { (target, 20) },
            now: { now }
        )
    }

    @Test
    func onlyThisWeeksClimbsAreRead() throws {
        let modelContext = try context()
        climb(on: 1, in: modelContext) // Sunday: last week
        climb(on: 3, in: modelContext)
        climb(on: 9, in: modelContext) // next Monday
        try modelContext.save()

        let dates = LocalReminderCoordinator.climbDates(
            inWeekOf: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!,
            calendar: calendar,
            modelContext: modelContext
        )

        #expect(dates.count == 1)
    }

    /// The failure the primer alone could not avoid: a target of 3 and three climbs by Wednesday
    /// must not leave Friday's "your week is still open" pending.
    @Test
    func aClimberWhoMetTheirTargetIsNoLongerToldTheyAreBehind() async throws {
        let modelContext = try context()
        for day in [2, 3, 4] { climb(on: day, in: modelContext) }
        try modelContext.save()

        let center = CoordinatorRecordingCenter()
        let reminders = coordinator(
            center: center,
            target: 3,
            now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 8))!
        )
        reminders.configure(modelContext: modelContext)
        await reminders.reconcile()

        #expect(!center.added.contains { $0.identifier == LocalReminderPlan.thisWeekIdentifier })
        #expect(center.added.contains { $0.identifier == LocalReminderPlan.nextWeekIdentifier })
    }

    @Test
    func aClimbThisWeekChangesTheNudgesWordsToTheirOwnCount() async throws {
        let modelContext = try context()
        climb(on: 2, in: modelContext)
        climb(on: 3, in: modelContext)
        try modelContext.save()

        let center = CoordinatorRecordingCenter()
        let reminders = coordinator(
            center: center,
            target: 3,
            now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 8))!
        )
        reminders.configure(modelContext: modelContext)
        await reminders.reconcile()

        let thisWeek = try #require(center.added.first { $0.identifier == LocalReminderPlan.thisWeekIdentifier })
        #expect(thisWeek.title == "One climb from your target")
        #expect(thisWeek.body == "2 of 3 days done this week. 20 minutes gets it done.")
    }

    @Test
    func noTargetSchedulesNothingWhateverWasClimbed() async throws {
        let modelContext = try context()
        climb(on: 2, in: modelContext)
        try modelContext.save()

        let center = CoordinatorRecordingCenter()
        let reminders = coordinator(center: center, target: nil, now: monday)
        reminders.configure(modelContext: modelContext)
        await reminders.reconcile()

        #expect(center.added.isEmpty)
    }
}
