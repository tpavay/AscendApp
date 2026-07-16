import Foundation

enum BuiltInRoutineBrowseSection: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted

    var id: String { rawValue }

    static func remoteValue(_ rawValue: String) -> BuiltInRoutineBrowseSection? {
        switch rawValue {
        case "gettingStarted", "getting_started":
            return .gettingStarted
        default:
            return BuiltInRoutineBrowseSection(rawValue: rawValue)
        }
    }

    var title: String {
        switch self {
        case .gettingStarted:
            return "GETTING STARTED"
        }
    }
}
