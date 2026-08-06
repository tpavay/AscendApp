import Foundation

struct PostAuthNameInput: Equatable, Sendable {
    var firstName = ""
    var lastName = ""

    /// The same gate Edit Profile saves behind. Requiring both halves is only
    /// part of it: a composed name that the policy would reject must keep
    /// CONTINUE disabled rather than fail after the tap.
    var canContinue: Bool {
        validationError == nil
    }

    /// Onboarding shows first and last name fields, so it cannot borrow the
    /// policy's own copy: that names a single display name field the climber
    /// is never shown here.
    var validationMessage: String? {
        switch validationError {
        case .none:
            return nil
        case .incompleteName:
            return DisplayNamePolicyError.incompleteName.errorDescription
        case .invalidLength:
            return "That name is too long"
        case .objectionable:
            return "That name cannot be used"
        }
    }

    private var validationError: DisplayNamePolicyError? {
        do {
            _ = try DisplayNamePolicy.composedBoardName(
                firstName: firstName,
                lastName: lastName
            )
            return nil
        } catch let error as DisplayNamePolicyError {
            return error
        } catch {
            return .objectionable
        }
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
