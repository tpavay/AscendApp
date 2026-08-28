import Foundation

/// Who the RevenueCat customer is, in the terms the app already knows the climber by.
///
/// RevenueCat discovers none of this. Left alone it files every install as an anonymous
/// `$RCAnonymous...` customer, which is why a trial or a grant in the dashboard cannot be matched
/// to a person without cross-referencing Firestore by hand. Both fields here are things the app
/// already holds from the sign-in that just happened; nothing new is collected from the climber to
/// build one.
struct MonetizationCustomerIdentity: Equatable, Sendable {
    /// The app's own Firebase Auth uid - the same identifier every other provider is told. Using it
    /// is what makes one climber one customer across their devices instead of one customer per
    /// install, so it is never a scheme invented here.
    let userID: String

    /// The address the sign-in provider handed the app, or nil when it handed none.
    ///
    /// A `@privaterelay.appleid.com` address is a real, deliverable address and is treated as one.
    /// Trimmed but never case-folded: the captain reads this, and the address they recognise is the
    /// one the climber typed.
    let email: String?

    init(userID: String, email: String? = nil) {
        self.userID = userID
        self.email = Self.normalizedEmail(email)
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
