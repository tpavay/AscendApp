import Foundation

@MainActor
final class PushNotificationRouter {
    static let shared = PushNotificationRouter()

    private(set) var pendingDestination: PushNotificationDestination?

    private init() {}

    func route(_ destination: PushNotificationDestination) {
        pendingDestination = destination
        NotificationCenter.default.post(name: .pushNotificationDestinationDidChange, object: nil)
    }

    func route(from userInfo: [AnyHashable: Any]) {
        guard let destination = destination(from: userInfo) else { return }
        route(destination)
    }

    func consumePendingDestination() -> PushNotificationDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func destination(from userInfo: [AnyHashable: Any]) -> PushNotificationDestination? {
        let type = stringValue(for: "type", in: userInfo)
        let route = stringValue(for: "route", in: userInfo)

        guard type == "climb_drop" || route == "climb_detail" else {
            return nil
        }

        guard let climbId = stringValue(for: "climbId", in: userInfo), !climbId.isEmpty else {
            return nil
        }

        return .climbDetail(climbId: climbId)
    }

    private func stringValue(for key: String, in userInfo: [AnyHashable: Any]) -> String? {
        if let value = userInfo[key] as? String {
            return value
        }

        if let value = userInfo[AnyHashable(key)] as? String {
            return value
        }

        return nil
    }
}
