import Foundation

enum PushNotificationDestination: Equatable, Sendable {
    case climbDetail(climbId: String)
}

extension Notification.Name {
    static let pushNotificationDestinationDidChange = Notification.Name("pushNotificationDestinationDidChange")
}
