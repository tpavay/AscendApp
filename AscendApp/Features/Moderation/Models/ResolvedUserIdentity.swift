import Foundation

/// The only identity a view may render for another climber.
///
/// It deliberately carries nothing but the moderated values. Attaching the raw
/// account-authored name or photo alongside them would remove the
/// compiler-enforced boundary, because a surface could then read past the mask.
struct ResolvedUserIdentity: Equatable, Sendable {
    let userId: String?
    let displayName: String
    let photoURL: URL?
    let avatarToken: String
    let isHidden: Bool

    private init(
        userId: String?,
        displayName: String,
        photoURL: URL?,
        avatarToken: String,
        isHidden: Bool
    ) {
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.avatarToken = avatarToken
        self.isHidden = isHidden
    }

    enum Resolver {
        static let hiddenDisplayNamePrefix = "Blocked climber"
        static let hiddenAvatarToken = ""

        static func resolve(
            userId: String?,
            displayName: String,
            photoURL: URL?,
            avatarToken: String = "",
            isCurrentUser: Bool,
            blockedUserIds: Set<String>,
            isBlockListHydrated: Bool
        ) -> ResolvedUserIdentity {
            if isCurrentUser {
                return ResolvedUserIdentity(
                    userId: userId,
                    displayName: normalizedName(
                        displayName,
                        fallback: PublicClimberIdentity.systemHandle(for: userId)
                    ),
                    photoURL: photoURL,
                    avatarToken: normalizedName(
                        avatarToken,
                        fallback: PublicClimberIdentity.fallbackAvatarToken
                    ),
                    isHidden: false
                )
            }

            let isBlocked = userId.map { blockedUserIds.contains($0) } ?? false
            let mustHideIdentity = !isBlockListHydrated ||
                userId == nil ||
                isBlocked

            if mustHideIdentity {
                return ResolvedUserIdentity(
                    userId: userId,
                    displayName: hiddenDisplayName(for: userId),
                    photoURL: nil,
                    avatarToken: hiddenAvatarToken,
                    isHidden: true
                )
            }

            return ResolvedUserIdentity(
                userId: userId,
                displayName: normalizedName(displayName, fallback: "Climber"),
                photoURL: photoURL,
                avatarToken: normalizedName(avatarToken, fallback: "CL"),
                isHidden: false
            )
        }

        static func hiddenDisplayName(for userId: String?) -> String {
            guard let userId, !userId.isEmpty else {
                return hiddenDisplayNamePrefix
            }

            // Swift's Hasher is intentionally randomized between launches.
            // FNV-1a gives the same privacy-safe label on every device and session.
            let hash = userId.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
            return "\(hiddenDisplayNamePrefix) \(String(format: "%04llu", hash % 10_000))"
        }

        private static func normalizedName(
            _ value: String,
            fallback: String
        ) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
    }
}
