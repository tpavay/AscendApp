import Foundation

enum ModerationReportReason: String, CaseIterable, Identifiable, Sendable {
    case harassment
    case hateSpeech = "hate_speech"
    case inappropriateName = "inappropriate_name"
    case inappropriatePhoto = "inappropriate_photo"
    case impersonation
    case spam
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment:
            "Harassment or bullying"
        case .hateSpeech:
            "Hate speech"
        case .inappropriateName:
            "Inappropriate name"
        case .inappropriatePhoto:
            "Inappropriate photo"
        case .impersonation:
            "Impersonation"
        case .spam:
            "Spam"
        case .other:
            "Something else"
        }
    }
}
