import Foundation

enum AppUpdatePresentation: String, Equatable, Identifiable, Sendable {
    case required
    case recommended

    var id: Self { self }

    var title: String {
        switch self {
        case .required:
            "Update Required"
        case .recommended:
            "Update Ascend"
        }
    }

    var message: String {
        switch self {
        case .required:
            "Update Ascend to keep climbing. This version is no longer supported."
        case .recommended:
            "A newer version is ready. Update now, or keep climbing and do it later."
        }
    }

    var allowsInteractiveDismissal: Bool { self == .recommended }

    var showsLaterAction: Bool { self == .recommended }
}
