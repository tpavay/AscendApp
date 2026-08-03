import Foundation

enum DisplayNamePolicyError: LocalizedError {
    case invalidLength
    case objectionable

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            "Enter a display name from 1 to \(DisplayNamePolicy.maximumLength) characters."
        case .objectionable:
            "Choose a different display name."
        }
    }
}
