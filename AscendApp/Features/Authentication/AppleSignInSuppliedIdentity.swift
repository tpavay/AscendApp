import AuthenticationServices
import Foundation

/// The name and email Apple hands back with a Sign in with Apple authorization.
///
/// `ASAuthorizationAppleIDCredential.fullName` and `.email` are populated only on
/// the FIRST authorization for an Apple ID and app pair. Every later sign-in
/// returns nil for both, and there is no API to ask Apple again. So whatever
/// arrives is captured the moment it arrives and persisted
/// (`AppleSignInIdentityStore`): dropping it means the climber has to type a name
/// Apple already gave, which is the Guideline 4 refusal this type exists to
/// prevent.
struct AppleSignInSuppliedIdentity: Codable, Equatable, Sendable {
    /// Apple's stable per-app user identifier. It is also the `uid` Firebase
    /// records for the `apple.com` provider, which is how a stored capture is
    /// matched back to the account it belongs to on a later launch.
    let appleUserID: String
    let firstName: String?
    let lastName: String?
    /// May be a `@privaterelay.appleid.com` address when the climber chose Hide
    /// My Email. That is a real, deliverable address and is treated as one.
    let email: String?
    let capturedAt: Date

    init(
        appleUserID: String,
        firstName: String?,
        lastName: String?,
        email: String?,
        capturedAt: Date = .now
    ) {
        self.appleUserID = appleUserID
        self.firstName = Self.normalizedNamePart(firstName)
        self.lastName = Self.normalizedNamePart(lastName)
        self.email = Self.normalizedEmail(email)
        self.capturedAt = capturedAt
    }

    init(credential: ASAuthorizationAppleIDCredential, capturedAt: Date = .now) {
        self.init(
            appleUserID: credential.user,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName,
            email: credential.email,
            capturedAt: capturedAt
        )
    }

    /// False when Apple returned nothing usable - a returning sign-in, or a
    /// climber who declined to share anything. Nothing is worth storing then.
    var carriesSomething: Bool {
        firstName != nil || lastName != nil || email != nil
    }

    /// The two halves Ascend's board name needs, present and composing a name the
    /// display-name policy accepts. `nil` when Apple supplied only one half, none
    /// at all, or something the policy refuses to publish.
    var adoptableName: (firstName: String, lastName: String)? {
        guard let firstName,
              let lastName,
              DisplayNamePolicy.composesAllowedBoardName(
                  firstName: firstName,
                  lastName: lastName
              ) else {
            return nil
        }
        return (firstName, lastName)
    }

    /// Keeps whichever copy actually carries more, so a later authorization that
    /// returns nil - which is every authorization after the first - can never
    /// erase what the first one gave.
    func mergingRetainedValues(from previous: AppleSignInSuppliedIdentity?) -> AppleSignInSuppliedIdentity {
        guard let previous, previous.appleUserID == appleUserID else { return self }

        return AppleSignInSuppliedIdentity(
            appleUserID: appleUserID,
            firstName: firstName ?? previous.firstName,
            lastName: lastName ?? previous.lastName,
            email: email ?? previous.email,
            capturedAt: capturedAt
        )
    }

    private static func normalizedNamePart(_ value: String?) -> String? {
        guard let value else { return nil }
        let singleLine = value
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(DisplayNamePolicy.maximumLength))
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// What the stored profile document says about the climber's name at the moment
/// an Apple capture is being considered.
enum StoredProfileName: Equatable, Sendable {
    /// The profile could not be read - offline, or a failed request. Nothing is
    /// safe to conclude from it.
    case unreadable
    case absent
    case present
}

/// Decides what to do with a captured Apple identity.
///
/// Pure, so every branch is decided once and tested once rather than being
/// re-derived inside an auth callback nobody can run in a test.
enum AppleSuppliedNameAdoption {
    enum Decision: Equatable {
        /// Apple gave a usable name and the account has none. Write it, and the
        /// name step never runs.
        case write(firstName: String, lastName: String)
        /// The account already carries a name. Apple's copy has done its job -
        /// or was never needed - and is dropped.
        case discard
        /// The profile could not be read, so overwriting it would be a guess.
        /// The capture stays put and the next sign-in tries again.
        case retryLater
        /// Nothing to write: no capture at all, or a climber who shared less
        /// than a full name. The name step runs, seeded with whatever Apple did
        /// give.
        case askTheClimber
    }

    static func decide(
        supplied: AppleSignInSuppliedIdentity?,
        storedName: StoredProfileName
    ) -> Decision {
        guard let supplied else { return .askTheClimber }

        switch storedName {
        case .present:
            return .discard
        case .unreadable:
            return .retryLater
        case .absent:
            guard let adoptable = supplied.adoptableName else { return .askTheClimber }
            return .write(firstName: adoptable.firstName, lastName: adoptable.lastName)
        }
    }
}
