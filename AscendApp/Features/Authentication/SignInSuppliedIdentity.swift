import AuthenticationServices
import Foundation

/// The name and email a sign-in provider handed back, whichever provider it was.
///
/// Sign in with Apple and Google both supply a name, and asking a climber to
/// retype either one is the Guideline 4 refusal that rejected 1.0. So there is no
/// per-provider branch here: both arrive as this value and one rule decides what
/// happens next.
///
/// The two providers differ only in how long the offer stands.
/// `ASAuthorizationAppleIDCredential.fullName` and `.email` are populated on the
/// FIRST authorization for an Apple ID and app pair, never again, and there is no
/// API to ask Apple a second time - so an Apple capture is persisted
/// (`SignInIdentityStore`) the instant it arrives. Google hands Firebase a
/// display name on every sign-in, so its copy is simply read back off the
/// account and nothing needs storing.
struct SignInSuppliedIdentity: Codable, Equatable, Sendable {
    /// The provider's stable per-app user identifier. For Apple it is also the
    /// `uid` Firebase records for the `apple.com` provider, which is how a stored
    /// capture is matched back to the account it belongs to on a later launch.
    let providerUserID: String
    let firstName: String?
    let lastName: String?
    /// May be a `@privaterelay.appleid.com` address when the climber chose Hide
    /// My Email. That is a real, deliverable address and is treated as one.
    let email: String?
    let capturedAt: Date

    init(
        providerUserID: String,
        firstName: String?,
        lastName: String?,
        email: String?,
        capturedAt: Date = .now
    ) {
        self.providerUserID = providerUserID
        self.firstName = Self.normalizedNamePart(firstName)
        self.lastName = Self.normalizedNamePart(lastName)
        self.email = Self.normalizedEmail(email)
        self.capturedAt = capturedAt
    }

    init(credential: ASAuthorizationAppleIDCredential, capturedAt: Date = .now) {
        self.init(
            providerUserID: credential.user,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName,
            email: credential.email,
            capturedAt: capturedAt
        )
    }

    /// The form Google - and Firebase generally - supplies a name in: one string.
    ///
    /// The first whitespace-separated word is the given name and the remainder is
    /// the family name, so a multi-word family name survives intact. A one-word
    /// name yields half an identity, which the adoption rule treats exactly like
    /// half a name from Apple: not publishable, so the placeholder is written
    /// instead. Ascend never asks for the missing half - there is no screen left
    /// to ask on.
    init(
        providerUserID: String,
        fullName: String?,
        email: String?,
        capturedAt: Date = .now
    ) {
        let parts = (fullName ?? "")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        self.init(
            providerUserID: providerUserID,
            firstName: parts.first,
            lastName: parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil,
            email: email,
            capturedAt: capturedAt
        )
    }

    /// False when the provider returned nothing usable - a returning Apple
    /// authorization, or a climber who declined to share anything. Nothing is
    /// worth storing then.
    var carriesSomething: Bool {
        firstName != nil || lastName != nil || email != nil
    }

    /// The two halves Ascend's board name needs, present and composing a name the
    /// display-name policy accepts. `nil` when the provider supplied only one
    /// half, none at all, or something the policy refuses to publish.
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
    /// returns nil - which is every Apple authorization after the first - can
    /// never erase what the first one gave.
    func mergingRetainedValues(from previous: SignInSuppliedIdentity?) -> SignInSuppliedIdentity {
        guard let previous, previous.providerUserID == providerUserID else { return self }

        return SignInSuppliedIdentity(
            providerUserID: providerUserID,
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

/// The name a profile carries when no source supplied one.
///
/// Deliberately an instruction rather than a plausible name. A climber who never
/// typed one opens their profile, reads "CHANGE ME", and knows exactly what to
/// do - which a generated handle like `Climber 2A4F` does not tell them. It is
/// also never a wall: it is written without asking, and nothing about reaching
/// the app is conditional on replacing it. Settings -> Edit Profile -> First
/// name changes it, three taps from the Profile tab.
///
/// Both halves are stored, because Ascend's board name is composed from a first
/// and a last name and a profile carrying only one of them is not editable
/// without re-deriving the other.
enum SignInNamePlaceholder {
    static let firstName = "CHANGE"
    static let lastName = "ME"

    /// What the leaderboards render. Screened by `DisplayNamePolicy` here, by
    /// `isAllowedDisplayName` in `firestore.rules`, and by the Cloud Functions
    /// projection - all three accept it, which is what makes it writable at all.
    static var boardName: String {
        "\(firstName) \(lastName)"
    }
}

/// What the stored profile document says about the climber's name at the moment
/// a provider-supplied identity is being considered.
enum StoredProfileName: Equatable, Sendable {
    /// The profile could not be read - offline, or a failed request. Nothing is
    /// safe to conclude from it.
    case unreadable
    case absent
    case present
}

/// Decides what to do with a name a provider supplied.
///
/// One rule for every provider, and it always terminates in a name: the profile
/// Ascend already holds, else whatever this sign-in supplied, else
/// `SignInNamePlaceholder`. Apple and Google both hand back a name, so a
/// per-provider branch would only be two things to drift apart.
///
/// Nothing here asks the climber anything. The name step was removed from
/// onboarding with this rule, because a rule that always produces a name leaves
/// the question with nothing to ask.
///
/// Pure, so every branch is decided once and tested once rather than being
/// re-derived inside an auth callback nobody can run in a test.
enum SuppliedNameAdoption {
    enum Decision: Equatable {
        /// Resolution step 2. The provider gave a usable name and the account has
        /// none, so it is written without ever being put to the climber.
        case write(firstName: String, lastName: String)
        /// Resolution step 1. The account already carries a name, so it wins over
        /// everything below it: the provider's copy has done its job, or was
        /// never needed, and is dropped.
        case discard
        /// The profile could not be read, so writing over it would be a guess.
        /// Any capture stays put and the next sign-in tries again.
        case retryLater
        /// Resolution step 3. Nothing supplied a name Ascend can publish - no
        /// capture at all, or less than a full name - so the profile gets
        /// `SignInNamePlaceholder`.
        ///
        /// This is terminal on purpose. There is no name step left to fall back
        /// on, and there must not be: a screen that asks for what Authentication
        /// Services already supplies is the Guideline 4 rejection, and a screen
        /// the climber cannot pass is the same rejection with extra steps.
        case writePlaceholder
    }

    static func decide(
        supplied: SignInSuppliedIdentity?,
        storedName: StoredProfileName
    ) -> Decision {
        switch storedName {
        case .present:
            return .discard
        case .unreadable:
            return .retryLater
        case .absent:
            guard let adoptable = supplied?.adoptableName else { return .writePlaceholder }
            return .write(firstName: adoptable.firstName, lastName: adoptable.lastName)
        }
    }
}
