import Foundation

enum ProfileNameField: String, Sendable {
    case firstName = "First name"
    case lastName = "Last name"

    var counterpart: ProfileNameField {
        switch self {
        case .firstName: .lastName
        case .lastName: .firstName
        }
    }
}
