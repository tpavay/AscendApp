import CryptoKit
import Foundation

enum PublicClimberIdentity {
    static let policyVersion = 1

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

    /// Account-authored identity is safe to publish only while the moderation
    /// boundary remains mandatory on every cross-user rendering surface.
    static let mode: Mode = .accountAuthored

    static let anonymousDisplayName = "Anonymous Climber"
    static let genericAvatarSystemName = "person.fill"

    /// Every letter here is absent from every screened term, so no six-character
    /// token can spell one. The generator also never repeats a character back to
    /// back, so the repeated-character check can never fire either. Together that
    /// guarantees `DisplayNamePolicy` and `isAllowedDisplayName` accept every
    /// handle this can produce - otherwise a uid whose hash landed on a rejected
    /// token could never publish a profile or a leaderboard row.
    static let tokenAlphabet = Array("2346789AEFJMNQRT")

    static func systemHandle(for userId: String?) -> String {
        guard let userId = normalizedUserId(userId) else {
            return anonymousDisplayName
        }

        let digest = SHA256.hash(data: Data(userId.utf8))
        let prefix = digest.prefix(4).reduce(UInt32.zero) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        let token = stride(from: 20, through: 0, by: -4).reduce(
            into: [Character]()
        ) { token, shift in
            let character = tokenAlphabet[Int((prefix >> UInt32(shift)) & 0x0F)]
            token.append(
                token.last == character ? nextTokenCharacter(after: character) : character
            )
        }

        return "Climber \(String(token))"
    }

    private static func nextTokenCharacter(after character: Character) -> Character {
        guard let index = tokenAlphabet.firstIndex(of: character) else {
            return character
        }
        return tokenAlphabet[(index + 1) % tokenAlphabet.count]
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
            let name = nonEmpty(storedDisplayName) ?? systemHandle(for: userId)
            return Presentation(
                displayName: name,
                photoURL: currentUserPhotoURL ?? storedPhotoURL,
                avatarToken: avatarToken(for: name),
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

    /// Mirrors `isValidPublicPhotoURL` in `firestore.rules` and `validPhotoURL`
    /// in `functions/src/publicIdentity.ts`. A URL outside Firebase Storage is
    /// dropped rather than published, so the server never has to reject the
    /// whole profile write over a photo the client could have discarded.
    ///
    /// `StorageReference.downloadURL()` builds its URL from `URLComponents`
    /// with `port` set to `Storage.port`, which defaults to 443, and Foundation
    /// keeps that default port in the string - so the shape the SDK actually
    /// emits carries an explicit `:443`.
    static func publishablePhotoURL(_ photoURL: URL?) -> URL? {
        guard let photoURL else {
            return nil
        }

        let value = photoURL.absoluteString
        guard value.count <= 2048,
              value.range(
                of: #"^https://firebasestorage\.googleapis\.com(:443)?/v0/b/[a-zA-Z0-9][a-zA-Z0-9._-]*/o/[^/]+$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }

        return photoURL
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
