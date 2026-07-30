import Foundation

struct ResolvedUserIdentity: Equatable, Sendable {
    let userId: String?
    let displayName: String
    let photoURL: URL?
    let avatarToken: String
    let isHidden: Bool
    let unmoderatedDisplayName: String
    let unmoderatedPhotoURL: URL?

    private init(
        userId: String?,
        displayName: String,
        photoURL: URL?,
        avatarToken: String,
        isHidden: Bool,
        unmoderatedDisplayName: String,
        unmoderatedPhotoURL: URL?
    ) {
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.avatarToken = avatarToken
        self.isHidden = isHidden
        self.unmoderatedDisplayName = unmoderatedDisplayName
        self.unmoderatedPhotoURL = unmoderatedPhotoURL
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
                let unmoderatedDisplayName = normalizedName(
                    displayName,
                    fallback: "You"
                )
                let unmoderatedAvatarToken = normalizedName(
                    avatarToken,
                    fallback: "YOU"
                )
                return ResolvedUserIdentity(
                    userId: userId,
                    displayName: unmoderatedDisplayName,
                    photoURL: photoURL,
                    avatarToken: unmoderatedAvatarToken,
                    isHidden: false,
                    unmoderatedDisplayName: unmoderatedDisplayName,
                    unmoderatedPhotoURL: photoURL
                )
            }

            let unmoderatedDisplayName = normalizedName(
                displayName,
                fallback: "Climber"
            )
            let unmoderatedAvatarToken = normalizedName(
                avatarToken,
                fallback: "CL"
            )
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
                    isHidden: true,
                    unmoderatedDisplayName: unmoderatedDisplayName,
                    unmoderatedPhotoURL: photoURL
                )
            }

            return ResolvedUserIdentity(
                userId: userId,
                displayName: unmoderatedDisplayName,
                photoURL: photoURL,
                avatarToken: unmoderatedAvatarToken,
                isHidden: false,
                unmoderatedDisplayName: unmoderatedDisplayName,
                unmoderatedPhotoURL: photoURL
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
