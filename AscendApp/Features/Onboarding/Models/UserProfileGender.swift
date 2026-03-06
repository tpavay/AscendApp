import Foundation

enum UserProfileGender: String, Codable, CaseIterable, Identifiable {
    case female
    case male
    case other
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female:
            return "Female"
        case .male:
            return "Male"
        case .other:
            return "Other"
        case .preferNotToSay:
            return "Prefer not to say"
        }
    }
}

extension UserProfileGender {
    var shareTemplateGender: Gender? {
        switch self {
        case .female:
            return .female
        case .male:
            return .male
        case .other, .preferNotToSay:
            return nil
        }
    }
}
