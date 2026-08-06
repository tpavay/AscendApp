import Foundation

struct PostAuthNameInput: Equatable, Sendable {
    var firstName = ""
    var lastName = ""

    var canContinue: Bool {
        normalizedFirstName.isEmpty == false && normalizedLastName.isEmpty == false
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
