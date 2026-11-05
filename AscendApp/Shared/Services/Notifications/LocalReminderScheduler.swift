import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the scheduler needs, so the rules can be tested without
/// asking iOS for anything.
@MainActor
protocol LocalReminderCenter: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: LocalReminderRequest) async throws
    func removePending(identifiers: [String])
}

@MainActor
final class LiveLocalReminderCenter: LocalReminderCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func add(_ request: LocalReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: request.fireDate
        )
        components.calendar = Calendar.current
        components.timeZone = Calendar.current.timeZone

        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        )
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Carries out ``LocalReminderPlan``: the weekly-target nudge and the trial-ending reminder.
///
/// Three things must all hold before anything is scheduled, and each is read fresh on every call
/// rather than remembered, because each can change behind the app's back:
/// - the reminder's own Remote Config switch is on;
/// - the climber still wants Ascend's notifications (the same stored answer the primer's TURN ON
///   and Settings write, which a denial never rewrites);
/// - iOS will deliver them.
///
/// Every call first clears what it owns, so turning notifications off, clearing a target or losing
/// the trial leaves nothing pending. Only identifiers this type owns are ever removed.
@MainActor
final class LocalReminderScheduler {
    static let shared = LocalReminderScheduler()

    private let center: any LocalReminderCenter
    private let featureFlags: RemoteFeatureFlagStore
    private let isPreferenceEnabled: @MainActor () -> Bool

    init(
        center: any LocalReminderCenter = LiveLocalReminderCenter(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        isPreferenceEnabled: @escaping @MainActor () -> Bool = { ClimbDropNotificationPreferenceStore.isEnabled }
    ) {
        self.center = center
        self.featureFlags = featureFlags
        self.isPreferenceEnabled = isPreferenceEnabled
    }

    /// Replaces the weekly-target reminders to match the climber's target and this week's climbs.
    /// Call it whenever either can have changed: a target set or cleared, a climb saved or
    /// removed, and a launch or foreground, which is also what rolls a finished week over.
    func reconcileWeeklyTarget(
        targetDays: Int?,
        climbDates: [Date],
        usualClimbMinutes: Int? = nil,
        now: Date = .now,
        calendar: Calendar = WeekConfiguration.calendar()
    ) async {
        center.removePending(identifiers: LocalReminderPlan.weeklyTargetIdentifiers)

        guard await canSchedule(.weeklyTargetReminder, path: "LocalReminderScheduler.reconcileWeeklyTarget") else {
            return
        }

        let requests = LocalReminderPlan.weeklyTarget(
            targetDays: targetDays,
            climbDates: climbDates,
            usualClimbMinutes: usualClimbMinutes,
            now: now,
            calendar: calendar
        )
        await add(requests)
    }

    /// Schedules the reminder for the day 5 of a started trial, replacing any earlier one. A nil
    /// start means no trial began and clears the reminder: nothing is ever scheduled for a trial
    /// that did not start.
    func reconcileTrialEnding(
        trialStartedAt: Date?,
        now: Date = .now,
        calendar: Calendar = WeekConfiguration.calendar()
    ) async {
        center.removePending(identifiers: [LocalReminderPlan.trialEndingIdentifier])

        guard trialStartedAt != nil,
              await canSchedule(.trialEndingReminder, path: "LocalReminderScheduler.reconcileTrialEnding"),
              let request = LocalReminderPlan.trialEnding(trialStartedAt: trialStartedAt, now: now, calendar: calendar) else {
            return
        }
        await add([request])
    }

    /// Clears every reminder this type owns, for sign-out and account deletion.
    func cancelAll() {
        center.removePending(
            identifiers: LocalReminderPlan.weeklyTargetIdentifiers + [LocalReminderPlan.trialEndingIdentifier]
        )
    }

    private func canSchedule(_ flag: RemoteFeatureFlag, path: String) async -> Bool {
        guard RemoteFeatureGate.allows(flag, path: path, store: featureFlags),
              isPreferenceEnabled() else {
            return false
        }
        return await center.authorizationStatus().allowsRemoteUserVisibleNotifications
    }

    private func add(_ requests: [LocalReminderRequest]) async {
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                AppDiagnosticsRecorder.shared.record(
                    "local_reminder_schedule_failed",
                    level: .warning,
                    details: ["identifier": request.identifier, "error": String(describing: type(of: error))]
                )
            }
        }
    }
}
