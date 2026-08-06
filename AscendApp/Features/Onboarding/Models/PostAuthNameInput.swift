import Foundation

struct PostAuthNameInput: Equatable, Sendable {
    var firstName = ""
    var lastName = ""

    /// The same gate Edit Profile saves behind. Requiring both halves is only
    /// part of it: a composed name that the policy would reject must keep
    /// CONTINUE disabled rather than fail after the tap.
    var canContinue: Bool {
        DisplayNamePolicy.composesAllowedBoardName(
            firstName: firstName,
            lastName: lastName
        )
    }

    var normalizedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func singleLinePart(_ value: String) -> String {
        let singleLine = value
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
        return String(singleLine.prefix(DisplayNamePolicy.maximumLength))
    }
}
