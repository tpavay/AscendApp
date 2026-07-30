import Foundation

@MainActor
protocol AuthenticatedPushNotificationManaging: AnyObject {
    func synchronizeAuthenticatedDeviceIfNeeded() async
    func unregisterCurrentDevice() async
}

extension PushNotificationService: AuthenticatedPushNotificationManaging {}
