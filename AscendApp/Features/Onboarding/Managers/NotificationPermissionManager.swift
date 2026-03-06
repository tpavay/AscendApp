import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationPermissionManager {
    static let shared = NotificationPermissionManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task {
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }
}
