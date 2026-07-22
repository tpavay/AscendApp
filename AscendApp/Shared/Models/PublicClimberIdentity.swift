import CryptoKit
import Foundation

enum PublicClimberIdentity {
    enum Mode: Sendable {
        case systemGenerated
        case accountAuthored
    }

    struct Presentation: Equatable, Sendable {
        let displayName: String
        let photoURL: URL?
        let avatarToken: String
        let usesGenericAvatar: Bool
    }

    /// One reversible seam for a future moderated-public-profile launch.
    static let mode: Mode = .systemGenerated

    static let storedDisplayName = "Climber"
    static let storedPhotoURL = ""
    static let anonymousDisplayName = "Anonymous Climber"
    static let genericAvatarSystemName = "person.fill"

    private static let tokenAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func systemHandle(for userId: String?) -> String {
        guard let userId = normalizedUserId(userId) else {
            return anonymousDisplayName
        }

        let digest = SHA256.hash(data: Data(userId.utf8))
        let prefix = digest.prefix(4).reduce(UInt32.zero) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        let token = stride(from: 27, through: 2, by: -5).map { shift in
            tokenAlphabet[Int((prefix >> UInt32(shift)) & 0x1F)]
        }

        return "Climber \(String(token))"
    }

    static func resolve(
        userId: String?,
        storedDisplayName: String?,
        storedPhotoURL: URL?,
        storedAvatarToken: String? = nil,
        isSynthetic: Bool = false,
        isCurrentUser: Bool = false,
        currentUserPhotoURL: URL? = nil
    ) -> Presentation {
        if isCurrentUser {
            return Presentation(
                displayName: "You",
                photoURL: currentUserPhotoURL ?? storedPhotoURL,
                avatarToken: "YOU",
                usesGenericAvatar: currentUserPhotoURL == nil && storedPhotoURL == nil
            )
        }

        if storedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) == anonymousDisplayName {
            return Presentation(
                displayName: anonymousDisplayName,
                photoURL: nil,
                avatarToken: "",
                usesGenericAvatar: true
            )
        }

        if isSynthetic {
            let name = nonEmpty(storedDisplayName) ?? fallbackDisplayName(for: userId)
            return Presentation(
                displayName: name,
                photoURL: storedPhotoURL,
                avatarToken: nonEmpty(storedAvatarToken) ?? avatarToken(for: name),
                usesGenericAvatar: storedPhotoURL == nil && nonEmpty(storedAvatarToken) == nil
            )
        }

        switch mode {
        case .systemGenerated:
            return Presentation(
                displayName: systemHandle(for: userId),
                photoURL: nil,
                avatarToken: "",
                usesGenericAvatar: true
            )
        case .accountAuthored:
            let name = nonEmpty(storedDisplayName) ?? systemHandle(for: userId)
            return Presentation(
                displayName: name,
                photoURL: storedPhotoURL,
                avatarToken: avatarToken(for: name),
                usesGenericAvatar: storedPhotoURL == nil
            )
        }
    }

    private static func fallbackDisplayName(for userId: String?) -> String {
        normalizedUserId(userId) == nil ? anonymousDisplayName : systemHandle(for: userId)
    }

    private static func normalizedUserId(_ userId: String?) -> String? {
        guard let value = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.utf8.count <= 128,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func avatarToken(for displayName: String) -> String {
        let token = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        return String(token).uppercased()
    }
}
