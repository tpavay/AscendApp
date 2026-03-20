import Foundation

enum BuiltInRoutineBrowseSection: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted:
            return "GETTING STARTED"
        }
    }
}
