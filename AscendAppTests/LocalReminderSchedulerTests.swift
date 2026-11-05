import Foundation
import Testing
import UserNotifications
@testable import AscendApp

@MainActor
private final class RecordingReminderCenter: LocalReminderCenter {
    var status: UNAuthorizationStatus = .authorized
    private(set) var added: [LocalReminderRequest] = []
    private(set) var removed: [[String]] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func add(_ request: LocalReminderRequest) async throws { added.append(request) }
    func removePending(identifiers: [String]) { removed.append(identifiers) }
}

/// What the scheduler may and may not schedule: nothing when the switch is off, the climber's
/// answer is off or iOS refuses, and no trial reminder without a started trial.
@MainActor
struct LocalReminderSchedulerTests {
    private let calendar = WeekConfiguration.calendar(timeZone: TimeZone(identifier: "UTC")!)
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))! }

    private func scheduler(
        center: RecordingReminderCenter,
        preference: Bool = true,
        off: [RemoteFeatureFlag] = []
    ) -> LocalReminderScheduler {
        var values: [String: Bool] = [:]
        for flag in off { values[flag.key] = false }
        return LocalReminderScheduler(
            center: center,
            featureFlags: RemoteFeatureFlagStore(snapshot: .resolving(remoteValues: values)),
            isPreferenceEnabled: { preference }
        )
    }

    @Test
    func aTargetSchedulesThisWeekAndNext() async {
        let center = RecordingReminderCenter()
        await scheduler(center: center).reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)

        #expect(Set(center.added.map(\.identifier)) == Set(LocalReminderPlan.weeklyTargetIdentifiers))
    }

    @Test
    func everyReconcileClearsWhatItOwnsFirst() async {
        let center = RecordingReminderCenter()
        await scheduler(center: center).reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)

        #expect(center.removed.first == LocalReminderPlan.weeklyTargetIdentifiers)
    }

    @Test
    func clearingTheTargetClearsThePendingNudgeAndSchedulesNone() async {
        let center = RecordingReminderCenter()
        await scheduler(center: center).reconcileWeeklyTarget(targetDays: nil, climbDates: [], now: monday, calendar: calendar)

        #expect(center.added.isEmpty)
        #expect(center.removed == [LocalReminderPlan.weeklyTargetIdentifiers])
    }

    @Test
    func nothingIsScheduledWhenTheClimbersAnswerIsOff() async {
        let center = RecordingReminderCenter()
        await scheduler(center: center, preference: false)
            .reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)
        await scheduler(center: center, preference: false)
            .reconcileTrialEnding(trialStartedAt: monday, now: monday, calendar: calendar)

        #expect(center.added.isEmpty)
    }

    @Test
    func nothingIsScheduledWhenIOSRefuses() async {
        let center = RecordingReminderCenter()
        center.status = .denied
        await scheduler(center: center)
            .reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)

        #expect(center.added.isEmpty)
    }

    @Test
    func eachReminderHasItsOwnSwitch() async {
        let center = RecordingReminderCenter()
        let weeklyOff = scheduler(center: center, off: [.weeklyTargetReminder])
        await weeklyOff.reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)
        #expect(center.added.isEmpty)

        await weeklyOff.reconcileTrialEnding(trialStartedAt: monday, now: monday, calendar: calendar)
        #expect(center.added.map(\.identifier) == [LocalReminderPlan.trialEndingIdentifier])

        let trialCenter = RecordingReminderCenter()
        let trialOff = scheduler(center: trialCenter, off: [.trialEndingReminder])
        await trialOff.reconcileTrialEnding(trialStartedAt: monday, now: monday, calendar: calendar)
        #expect(trialCenter.added.isEmpty)
        await trialOff.reconcileWeeklyTarget(targetDays: 3, climbDates: [], now: monday, calendar: calendar)
        #expect(!trialCenter.added.isEmpty)
    }

    @Test
    func noTrialReminderWithoutAStartedTrial() async {
        let center = RecordingReminderCenter()
        await scheduler(center: center).reconcileTrialEnding(trialStartedAt: nil, now: monday, calendar: calendar)

        #expect(center.added.isEmpty)
        #expect(center.removed == [[LocalReminderPlan.trialEndingIdentifier]])
    }

    @Test
    func aStartedTrialSchedulesTheDayFiveReminder() async throws {
        let center = RecordingReminderCenter()
        await scheduler(center: center).reconcileTrialEnding(trialStartedAt: monday, now: monday, calendar: calendar)

        let request = try #require(center.added.first)
        #expect(request.identifier == LocalReminderPlan.trialEndingIdentifier)
        #expect(request.fireDate == calendar.date(byAdding: .day, value: 5, to: monday))
    }

    @Test
    func cancelAllClearsBothReminders() {
        let center = RecordingReminderCenter()
        scheduler(center: center).cancelAll()

        #expect(center.removed == [LocalReminderPlan.weeklyTargetIdentifiers + [LocalReminderPlan.trialEndingIdentifier]])
    }

    @Test
    func accountDeletionsLocalSweepClearsBothReminders() throws {
        let center = RecordingReminderCenter()
        let suite = "local-reminder-deletion-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let cleanup = AppAccountDeletionLocalCleanup(
            userDefaults: defaults,
            persistentDomainName: suite,
            settingsManager: SettingsManager(userDefaults: defaults),
            localReminderScheduler: scheduler(center: center),
            bootstrapCoordinator: AuthenticatedBootstrapCoordinator()
        )

        cleanup.clearUserDefaults()

        #expect(center.removed == [LocalReminderPlan.weeklyTargetIdentifiers + [LocalReminderPlan.trialEndingIdentifier]])
    }
}
