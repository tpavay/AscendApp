import Foundation
import UserNotifications

@MainActor
final class TodayClimbNotificationScheduler {
    static let shared = TodayClimbNotificationScheduler()

    private let notificationCenter: UNUserNotificationCenter
    private let scheduledDaysCount = 14
    private let identifierPrefix = "today-climb-drop-"

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func scheduleIfAuthorized(
        availableClimbs: [Climb],
        completedClimbIds: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard TodayClimbNotificationPreferenceStore.isEnabled else {
            await cancelPendingTodayClimbNotifications()
            return
        }

        guard !availableClimbs.isEmpty else {
            await cancelPendingTodayClimbNotifications()
            return
        }

        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus.allowsTodayClimbNotifications else {
            await cancelPendingTodayClimbNotifications()
            return
        }

        await scheduleUpcomingTodayClimbNotifications(
            availableClimbs: availableClimbs,
            completedClimbIds: completedClimbIds,
            now: now,
            calendar: calendar
        )
    }

    private func scheduleUpcomingTodayClimbNotifications(
        availableClimbs: [Climb],
        completedClimbIds: Set<String>,
        now: Date,
        calendar: Calendar
    ) async {
        await cancelPendingTodayClimbNotifications()

        for dayOffset in 0..<scheduledDaysCount {
            guard let fireDate = DailyClimbRecommendationPolicy.rolloverDate(
                offsetByDays: dayOffset,
                after: now,
                calendar: calendar
            ) else {
                continue
            }

            let recommendationDate = fireDate.addingTimeInterval(1)
            guard let climb = DailyClimbRecommendationPolicy.recommendation(
                from: availableClimbs,
                completedClimbIds: completedClimbIds,
                on: recommendationDate,
                calendar: calendar
            ) else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "Today's climb: \(climb.name)"
            content.body = "Climb \(climb.referenceStepCount.formatted()) steps and put a result on the board."
            content.sound = .default
            content.userInfo = [
                "kind": "today_climb_drop",
                "climbId": climb.id
            ]

            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.second = 0

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(DailyClimbRecommendationPolicy.dayKey(for: recommendationDate, calendar: calendar))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                TelemetryManager.shared.recordError(
                    error,
                    context: .network,
                    code: "today_climb_notification_schedule_failed",
                    additionalInfo: ["climbId": climb.id]
                )
            }
        }
    }

    func cancelPendingTodayClimbNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }

        guard !identifiers.isEmpty else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private extension UNAuthorizationStatus {
    var allowsTodayClimbNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
