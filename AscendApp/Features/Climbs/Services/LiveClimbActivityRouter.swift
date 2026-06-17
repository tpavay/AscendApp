import Foundation

struct LiveClimbActivityRoute: Equatable, Sendable {
    let sessionID: String
    let climbID: String?
}

@MainActor
final class LiveClimbActivityRouter {
    static let shared = LiveClimbActivityRouter()

    private var pendingRoute: LiveClimbActivityRoute?

    private init() {}

    func route(from url: URL) -> Bool {
        guard url.scheme == "ascendapp",
              url.host == "live-climb",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sessionID = components.queryItems?.first(where: { $0.name == "sessionID" })?.value,
              sessionID.isEmpty == false else {
            return false
        }

        let climbID = components.queryItems?.first(where: { $0.name == "climbID" })?.value
        route(sessionID: sessionID, climbID: climbID)
        return true
    }

    func route(sessionID: String, climbID: String?) {
        pendingRoute = LiveClimbActivityRoute(sessionID: sessionID, climbID: climbID)
        NotificationCenter.default.post(name: .liveClimbActivityRouteDidChange, object: nil)
    }

    func consumePendingRoute() -> LiveClimbActivityRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

extension Notification.Name {
    static let liveClimbActivityRouteDidChange = Notification.Name("liveClimbActivityRouteDidChange")
}
