import Foundation

enum TelemetryDestination: Sendable, Hashable {
    case analytics
    case crashlytics

    var displayName: String {
        switch self {
        case .analytics:
            "Analytics"
        case .crashlytics:
            "Crashlytics"
        }
    }
}
