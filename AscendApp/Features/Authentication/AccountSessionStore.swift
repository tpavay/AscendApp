import Foundation

enum AuthProviderKind: String, Equatable, Sendable {
    case google
    case apple
    case internalQA = "internal_qa"
}

@MainActor
final class AccountSessionStore {
    static let shared = AccountSessionStore()

    private enum Keys {
        static let lastUsedProvider = "auth.lastUsedProvider"
        static let localDataOwnerUserId = "accountData.localOwnerUserId"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastUsedProvider: AuthProviderKind? {
        guard let rawValue = userDefaults.string(forKey: Keys.lastUsedProvider) else {
            return nil
        }
        return AuthProviderKind(rawValue: rawValue)
    }

    var localDataOwnerUserId: String? {
        normalizedUserId(userDefaults.string(forKey: Keys.localDataOwnerUserId))
    }

    func recordSuccessfulSignIn(provider: AuthProviderKind) {
        userDefaults.set(provider.rawValue, forKey: Keys.lastUsedProvider)
    }

    func recordLocalDataOwner(userId: String) {
        guard let normalized = normalizedUserId(userId) else { return }
        userDefaults.set(normalized, forKey: Keys.localDataOwnerUserId)
    }

    func clearLocalDataOwner() {
        userDefaults.removeObject(forKey: Keys.localDataOwnerUserId)
    }

    private func normalizedUserId(_ userId: String?) -> String? {
        guard let userId else { return nil }
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
