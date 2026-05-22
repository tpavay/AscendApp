import Foundation

enum ProfileGender: String, CaseIterable, Codable, Identifiable, Sendable {
    case woman
    case man
    case nonBinary = "non_binary"
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woman:
            "Woman"
        case .man:
            "Man"
        case .nonBinary:
            "Non-binary"
        case .preferNotToSay:
            "Prefer not to say"
        }
    }
}
