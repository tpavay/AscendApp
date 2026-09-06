import Foundation

/// Opaque account-authored identity carried by service models.
///
/// Raw names and photo URLs are private so non-rendering layers can transport
/// them to the one resolver without exposing an unmoderated member API.
struct UnresolvedUserIdentity:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    private let displayName: String
    private let photoURL: URL?
    private let avatarToken: String
    private let isSynthetic: Bool

    init(
        displayName: String,
        photoURL: URL?,
        avatarToken: String = "",
        isSynthetic: Bool = false
    ) {
        self.displayName = displayName
        self.photoURL = photoURL
        self.avatarToken = avatarToken
        self.isSynthetic = isSynthetic
    }

    fileprivate func publicPresentation(
        userId: String?,
        isCurrentUser: Bool,
        currentUserPhotoURL: URL? = nil
    ) -> PublicClimberIdentity.Presentation {
        PublicClimberIdentity.resolve(
            userId: userId,
            storedDisplayName: displayName,
            storedPhotoURL: isCurrentUser ? nil : photoURL,
            storedAvatarToken: avatarToken,
            isSynthetic: isSynthetic,
            isCurrentUser: isCurrentUser,
            currentUserPhotoURL: currentUserPhotoURL ??
                (isCurrentUser ? photoURL : nil)
        )
    }

    func applyingFallback(
        displayName fallbackDisplayName: String,
        photoURL fallbackPhotoURL: URL?
    ) -> UnresolvedUserIdentity {
        let trimmedName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return UnresolvedUserIdentity(
            displayName: trimmedName.isEmpty ? fallbackDisplayName : displayName,
            photoURL: photoURL ?? fallbackPhotoURL,
            avatarToken: avatarToken,
            isSynthetic: isSynthetic
        )
    }

    func applyingOverrides(
        displayName: String?,
        photoURL: URL?
    ) -> UnresolvedUserIdentity {
        UnresolvedUserIdentity(
            displayName: displayName ?? self.displayName,
            photoURL: photoURL ?? self.photoURL,
            avatarToken: avatarToken,
            isSynthetic: isSynthetic
        )
    }

    /// Unlike `applyingOverrides`, a nil photo here clears the photo: removing
    /// one is an edit the climber can make, so it must survive the round trip.
    func replacingPhotoURL(_ photoURL: URL?) -> UnresolvedUserIdentity {
        UnresolvedUserIdentity(
            displayName: displayName,
            photoURL: photoURL,
            avatarToken: avatarToken,
            isSynthetic: isSynthetic
        )
    }

    fileprivate func publicationFields() throws -> (
        displayName: String,
        photoURL: URL?
    ) {
        (
            try DisplayNamePolicy.validated(displayName),
            PublicClimberIdentity.publishablePhotoURL(photoURL)
        )
    }

    var description: String {
        "<redacted unresolved identity>"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["identity": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Renderer input for a global leaderboard entry.
///
/// The raw `LeaderboardEntry` cannot be passed to identity-rendering views.
/// It must first cross `CrossUserIdentityAdapter`, which is the sole place that
/// can construct this type.
struct ModeratedLeaderboardEntry: Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let identity: ResolvedUserIdentity
    let rank: Int
    let value: Double
    let formattedValue: String
    let isCurrentUser: Bool
    let isTied: Bool

    fileprivate init(source: LeaderboardEntry, identity: ResolvedUserIdentity) {
        id = source.id
        userId = source.userId
        self.identity = identity
        rank = source.rank
        value = source.value
        formattedValue = source.formattedValue
        isCurrentUser = source.isCurrentUser
        isTied = source.isTied
    }

    static func preview(
        userId: String,
        displayName: String,
        rank: Int,
        value: Double,
        formattedValue: String,
        isCurrentUser: Bool = false
    ) -> ModeratedLeaderboardEntry {
        CrossUserIdentityAdapter.leaderboardEntry(
            LeaderboardEntry(
                userId: userId,
                displayName: displayName,
                rank: rank,
                value: value,
                formattedValue: formattedValue,
                isCurrentUser: isCurrentUser
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
    }
}

/// Renderer input for every Live Replay and completion leaderboard row.
struct ModeratedReplayLeaderboardRow: Identifiable, Equatable, Sendable {
    let id: String
    let identity: ResolvedUserIdentity
    let rank: Int?
    let stepsAtBucket: Int
    let finalSteps: Int
    let deltaFromUser: Int
    let isCurrentUser: Bool
    /// The viewer's attempt in progress, as opposed to every completion of
    /// theirs the board already carries. Both are `isCurrentUser`.
    let isLiveAttempt: Bool
    /// Mirrors `LiveReplayLeaderboardRow.isViewerGhost` by construction rather
    /// than re-deriving it, so the rule for which rows carry no rank has one
    /// definition.
    let isViewerGhost: Bool
    let isPersonalBest: Bool
    let completionDurationSeconds: TimeInterval?
    let userId: String?
    let gender: String?
    let age: Int?
    let locationCity: String?
    let isTied: Bool

    fileprivate init(
        source: LiveReplayLeaderboardRow,
        identity: ResolvedUserIdentity
    ) {
        id = source.id
        self.identity = identity
        rank = source.rank
        stepsAtBucket = source.stepsAtBucket
        finalSteps = source.finalSteps
        deltaFromUser = source.deltaFromUser
        isCurrentUser = source.isCurrentUser
        isLiveAttempt = source.isLiveAttempt
        isViewerGhost = source.isViewerGhost
        isPersonalBest = source.isPersonalBest
        completionDurationSeconds = source.completionDurationSeconds
        userId = source.userId
        gender = source.gender
        age = source.age
        locationCity = source.locationCity
        isTied = source.isTied
    }

    var averageStepsPerMinute: Double? {
        guard let completionDurationSeconds,
              completionDurationSeconds > 0,
              finalSteps > 0 else {
            return nil
        }

        let value = Double(finalSteps) / (completionDurationSeconds / 60)
        return value.isFinite ? value : nil
    }

    var demographicSummaryText: String? {
        let parts = [
            genderAbbreviation,
            age.map(String.init),
            locationCity
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var genderAbbreviation: String? {
        switch gender?.lowercased() {
        case "man", "male", "m":
            return "M"
        case "woman", "female", "f":
            return "F"
        default:
            return nil
        }
    }
}

struct ModeratedReplayFirstAscent: Equatable, Sendable {
    let identity: ResolvedUserIdentity
    let completedAt: Date

    fileprivate init(
        source: LiveReplayFirstAscent,
        identity: ResolvedUserIdentity
    ) {
        self.identity = identity
        completedAt = source.completedAt
    }
}

enum CrossUserIdentityAdapter {
    static func leaderboardEntry(
        from stats: FirestoreLeaderboardStats,
        rank: Int,
        value: Double,
        formattedValue: String,
        isTied: Bool,
        currentUserId: String,
        currentUserPhotoURL: URL?
    ) -> LeaderboardEntry {
        let isCurrentUser = stats.userId == currentUserId
        let presentation = stats.unresolvedIdentity.publicPresentation(
            userId: stats.userId,
            isCurrentUser: isCurrentUser,
            currentUserPhotoURL: currentUserPhotoURL
        )
        return LeaderboardEntry(
            userId: stats.userId,
            unresolvedIdentity: UnresolvedUserIdentity(
                displayName: presentation.displayName,
                photoURL: presentation.photoURL,
                avatarToken: presentation.avatarToken
            ),
            rank: rank,
            value: value,
            formattedValue: formattedValue,
            isCurrentUser: isCurrentUser,
            isTied: isTied
        )
    }

    static func leaderboardEntry(
        _ entry: LeaderboardEntry,
        blockedUserIds: Set<String>,
        isBlockListHydrated: Bool
    ) -> ModeratedLeaderboardEntry {
        let publicIdentity = entry.unresolvedIdentity.publicPresentation(
            userId: entry.userId,
            isCurrentUser: entry.isCurrentUser
        )
        let identity = resolve(
            userId: entry.userId,
            publicIdentity: publicIdentity,
            isCurrentUser: entry.isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
        return ModeratedLeaderboardEntry(source: entry, identity: identity)
    }

    static func replayRow(
        _ row: LiveReplayLeaderboardRow,
        blockedUserIds: Set<String>,
        isBlockListHydrated: Bool
    ) -> ModeratedReplayLeaderboardRow {
        let publicIdentity = row.unresolvedIdentity.publicPresentation(
            userId: row.userId,
            isCurrentUser: row.isCurrentUser
        )
        let identity = resolve(
            userId: row.userId,
            publicIdentity: publicIdentity,
            isCurrentUser: row.isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
        return ModeratedReplayLeaderboardRow(source: row, identity: identity)
    }

    static func firstAscent(
        _ firstAscent: LiveReplayFirstAscent,
        currentUserId: String?,
        blockedUserIds: Set<String>,
        isBlockListHydrated: Bool
    ) -> ModeratedReplayFirstAscent {
        let isCurrentUser = firstAscent.userId == currentUserId
        let publicIdentity = firstAscent.unresolvedIdentity.publicPresentation(
            userId: firstAscent.userId,
            isCurrentUser: isCurrentUser
        )
        let identity = resolve(
            userId: firstAscent.userId,
            publicIdentity: publicIdentity,
            isCurrentUser: isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
        return ModeratedReplayFirstAscent(
            source: firstAscent,
            identity: identity
        )
    }

    static func profileIdentity(
        _ profileIdentity: ProfileUserIdentity,
        isCurrentUser: Bool,
        blockedUserIds: Set<String>,
        isBlockListHydrated: Bool
    ) -> ResolvedUserIdentity {
        let publicIdentity = profileIdentity.unresolvedIdentity.publicPresentation(
            userId: profileIdentity.userId,
            isCurrentUser: isCurrentUser,
            currentUserPhotoURL: nil
        )
        return resolve(
            userId: profileIdentity.userId,
            publicIdentity: publicIdentity,
            isCurrentUser: isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }

    private static func resolve(
        userId: String?,
        publicIdentity: PublicClimberIdentity.Presentation,
        isCurrentUser: Bool,
        blockedUserIds: Set<String>,
        isBlockListHydrated: Bool
    ) -> ResolvedUserIdentity {
        CrossUserIdentityResolver.resolve(
            userId: userId,
            displayName: publicIdentity.displayName,
            photoURL: publicIdentity.photoURL,
            avatarToken: publicIdentity.avatarToken,
            isCurrentUser: isCurrentUser,
            blockedUserIds: blockedUserIds,
            isBlockListHydrated: isBlockListHydrated
        )
    }
}

/// The screened, publish-safe identity fields for one profile.
///
/// Screening is the expensive part of publishing an identity, so callers
/// validate once and pass the result to every helper that needs it rather than
/// re-screening per payload and per version comparison.
struct PublicIdentityPublication: Sendable, Equatable {
    let displayName: String
    let photoURL: URL?
}

enum ProfileIdentityPersistenceAdapter {
    static func validatedFields(
        for identity: ProfileUserIdentity
    ) throws -> PublicIdentityPublication {
        let fields = try identity.unresolvedIdentity.publicationFields()
        return PublicIdentityPublication(
            displayName: fields.displayName,
            photoURL: fields.photoURL
        )
    }
}
