import Foundation

enum PushNotificationDestination: Equatable, Sendable {
    case climbDetail(climbId: String)
    /// A "Climb imported" notification: open that imported climb's quick edit sheet.
    case importedClimbQuickEdit(workoutID: UUID)
}

extension Notification.Name {
    static let pushNotificationDestinationDidChange = Notification.Name("pushNotificationDestinationDidChange")
}
