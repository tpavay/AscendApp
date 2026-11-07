import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import AscendApp

@MainActor
private final class CoordinatorRecordingCenter: LocalReminderCenter {
    private(set) var added: [LocalReminderRequest] = []
    private(set) var pending: Set<String> = []

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }

    func add(_ request: LocalReminderRequest) async throws {
        added.append(request)
        pending.insert(request.identifier)
    }

    func removePending(identifiers: [String]) {
        pending.subtract(identifiers)
    }
}

@MainActor
private final class StoredAnswer {
    var isOn = true
}

/// What the account would answer, so a read after a write sees what the write carried.
@MainActor
private final class AccountTarget {
    var target: WeeklyTarget?
}

@MainActor
private final class ProfileReads {
    var count = 0
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

    private func answersStore(target: Int?) throws -> PreAuthOnboardingStore {
        let suite = "local-reminder-coordinator-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.update {
            $0.weeklyTargetDays = target
            $0.usualClimbMinutes = 20
        }
        return store
    }

    private func coordinator(
        center: CoordinatorRecordingCenter,
        target: Int?,
        now: Date,
        answer: StoredAnswer = StoredAnswer()
    ) throws -> LocalReminderCoordinator {
        try coordinator(center: center, store: answersStore(target: target), now: now, answer: answer)
    }

    private func coordinator(
        center: CoordinatorRecordingCenter,
        store: PreAuthOnboardingStore,
        now: Date,
        answer: StoredAnswer = StoredAnswer()
    ) -> LocalReminderCoordinator {
        LocalReminderCoordinator(
            scheduler: LocalReminderScheduler(
                center: center,
                featureFlags: RemoteFeatureFlagStore(snapshot: .shippedDefaults),
                isPreferenceEnabled: { answer.isOn }
            ),
            store: store,
            now: { now }
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
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
        let reminders = try coordinator(
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
        let reminders = try coordinator(
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
        let reminders = try coordinator(center: center, target: nil, now: monday)
        reminders.configure(modelContext: modelContext)
        await reminders.reconcile()

        #expect(center.added.isEmpty)
    }

    /// Settings' toggle and the primer's Not now write the answer and nothing else: the pending
    /// nudge has to go without waiting for the next foreground.
    @Test
    func turningTheAnswerOffClearsThePendingNudgeAtOnce() async throws {
        let center = CoordinatorRecordingCenter()
        let answer = StoredAnswer()
        let reminders = try coordinator(center: center, target: 3, now: monday, answer: answer)
        reminders.configure(modelContext: try context())
        await reminders.reconcile()
        #expect(center.pending == Set(LocalReminderPlan.weeklyTargetIdentifiers))

        answer.isOn = false
        NotificationCenter.default.post(name: .climbDropNotificationPreferenceDidChange, object: nil)

        await waitUntil { center.pending.isEmpty }
        #expect(center.pending.isEmpty)
    }

    /// The primer's TURN ON schedules nothing itself: writing the answer is what arms the nudge.
    @Test
    func turningTheAnswerOnArmsTheNudgeAtOnce() async throws {
        let center = CoordinatorRecordingCenter()
        let answer = StoredAnswer()
        answer.isOn = false
        let reminders = try coordinator(center: center, target: 3, now: monday, answer: answer)
        reminders.configure(modelContext: try context())
        await reminders.reconcile()
        #expect(center.pending.isEmpty)

        answer.isOn = true
        NotificationCenter.default.post(name: .climbDropNotificationPreferenceDidChange, object: nil)

        await waitUntil { !center.pending.isEmpty }
        #expect(center.pending == Set(LocalReminderPlan.weeklyTargetIdentifiers))
    }

    private func settings(telling reminders: LocalReminderCoordinator) throws -> WeeklyTargetService {
        let suite = "local-reminder-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let account = AccountTarget()
        return WeeklyTargetService(
            store: WeeklyTargetStore(userDefaults: defaults),
            isWriteEnabled: { true },
            readRemote: { _ in account.target },
            writeRemote: { _, target in account.target = target },
            onTargetChange: { _, target in reminders.weeklyTargetChanged(to: target) },
            queue: WeeklyTargetSyncQueue()
        )
    }

    /// The hand-off run on the real weekly-target service, as the foreground retry runs it.
    private func handOff(
        store: PreAuthOnboardingStore,
        service: WeeklyTargetService,
        profileReads: ProfileReads = ProfileReads()
    ) -> OnboardingV3SignInHandOff {
        OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { true },
                signInNameSettled: {},
                readProfile: { _ in
                    profileReads.count += 1
                    return nil
                },
                writeProfile: { _, _, _ in },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { _ in false },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { service.localTarget(for: $0)?.days },
                saveWeeklyTarget: { userId, days in await service.save(WeeklyTarget(days: days), for: userId) },
                reconcileWeeklyTarget: { await service.reconcile(for: $0) }
            ),
            store: store
        )
    }

    /// With the rollout off nothing has handed anything off, and the foreground retry used to treat
    /// this target as undelivered, delete it, and leave the next reconcile with no target.
    @Test
    func aTargetSetInSettingsSurvivesTheForegroundRetryAndKeepsTheNudge() async throws {
        #expect(!RemoteFeatureFlagStore(snapshot: .shippedDefaults).isEnabled(.onboardingV3))
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: nil)
        store.update { $0.usualClimbMinutes = nil }
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: try context())
        let service = try settings(telling: reminders)
        await service.save(WeeklyTarget(days: 4), for: "alice")

        let profileReads = ProfileReads()
        let outcome = await handOff(store: store, service: service, profileReads: profileReads)
            .retryPendingAnswers(userId: "alice", email: nil)
        await reminders.reconcile()

        #expect(outcome == .complete)
        #expect(profileReads.count == 0, "a foreground costs no read for a target nobody has to deliver")
        #expect(store.answers().weeklyTargetDays == 4)
        #expect(center.pending == Set(LocalReminderPlan.weeklyTargetIdentifiers))
    }

    @Test
    func aTargetChosenBeforeSignInReachesTheServiceAndKeepsTheNudge() async throws {
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: 4)
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: try context())
        let service = try settings(telling: reminders)

        let outcome = await handOff(store: store, service: service)
            .runAfterSignIn(userId: "alice", email: nil)
        await reminders.reconcile()

        #expect(outcome == .complete)
        #expect(service.localTarget(for: "alice")?.days == 4)
        #expect(store.answers().weeklyTargetDays == 4)
        #expect(center.pending == Set(LocalReminderPlan.weeklyTargetIdentifiers))
    }

    @Test
    func clearingTheTargetInSettingsStopsTheNudge() async throws {
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: 3)
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: try context())
        await reminders.reconcile()
        #expect(!center.pending.isEmpty)

        try await settings(telling: reminders).save(nil, for: "alice")

        await waitUntil { center.pending.isEmpty }
        #expect(center.pending.isEmpty)
        await reminders.reconcile()
        #expect(center.pending.isEmpty, "no later reconcile re-arms a nudge for a cleared target")
        #expect(store.answers().weeklyTargetDays == nil)
    }

    @Test
    func settingTheTargetInSettingsReachesTheNudge() async throws {
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: nil)
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: try context())
        await reminders.reconcile()
        #expect(center.pending.isEmpty)

        try await settings(telling: reminders).save(WeeklyTarget(days: 3), for: "alice")

        await waitUntil { !center.pending.isEmpty }
        #expect(center.pending == Set(LocalReminderPlan.weeklyTargetIdentifiers))
        #expect(store.answers().weeklyTargetDays == 3)
    }

    /// One climb already meets a target of one, so only the changed target can arm this week's nudge.
    @Test
    func changingTheTargetInSettingsReachesTheNudge() async throws {
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: 1)
        let modelContext = try context()
        climb(on: 2, in: modelContext)
        try modelContext.save()
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: modelContext)
        await reminders.reconcile()
        #expect(!center.pending.contains(LocalReminderPlan.thisWeekIdentifier))

        try await settings(telling: reminders).save(WeeklyTarget(days: 3), for: "alice")

        await waitUntil { center.pending.contains(LocalReminderPlan.thisWeekIdentifier) }
        #expect(center.pending.contains(LocalReminderPlan.thisWeekIdentifier))
        #expect(store.answers().weeklyTargetDays == 3)
    }

    @Test
    func aSignOutClearsTheNudgeAndNoLaterReconcileReArmsIt() async throws {
        let center = CoordinatorRecordingCenter()
        let store = try answersStore(target: 3)
        store.update { $0.completedAt = monday }
        let reminders = coordinator(center: center, store: store, now: monday)
        reminders.configure(modelContext: try context())
        await reminders.reconcile()
        #expect(!center.pending.isEmpty)

        reminders.sessionEnded()
        #expect(center.pending.isEmpty)

        await reminders.reconcile()
        #expect(center.pending.isEmpty, "the next foreground must not re-arm the nudge")
        #expect(store.answers().weeklyTargetDays == nil, "the next account must not inherit the target")
        #expect(store.answers().completedAt == monday, "signing out does not restart the onboarding flow")
    }
}
