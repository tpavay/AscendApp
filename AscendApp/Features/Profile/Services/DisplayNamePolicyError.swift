import Foundation

enum DisplayNamePolicyError: LocalizedError {
    case invalidLength
    case incompleteName
    case objectionable

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            "Enter a display name from 1 to \(DisplayNamePolicy.maximumLength) characters."
        case .incompleteName:
            "Enter both a first and last name."
        case .objectionable:
            "Choose a different display name."
        }
    }
}
