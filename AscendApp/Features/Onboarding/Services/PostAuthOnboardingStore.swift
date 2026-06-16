import Foundation

struct PostAuthOnboardingStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func snapshot(for userId: String) -> PostAuthOnboardingSnapshot {
        let key = storageKey(for: userId)

        guard let data = userDefaults.data(forKey: key) else {
            return PostAuthOnboardingSnapshot()
        }

        do {
            return try JSONDecoder().decode(PostAuthOnboardingSnapshot.self, from: data)
        } catch {
            if let legacySnapshot = legacySnapshot(from: data) {
                save(legacySnapshot, for: userId)
                return legacySnapshot
            }

            userDefaults.removeObject(forKey: key)
            return PostAuthOnboardingSnapshot()
        }
    }

    func save(_ snapshot: PostAuthOnboardingSnapshot, for userId: String) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: storageKey(for: userId))
        } catch {
            assertionFailure("Failed to persist post-auth onboarding snapshot: \(error)")
        }
    }

    func reset(for userId: String) {
        userDefaults.removeObject(forKey: storageKey(for: userId))
    }

    func markComplete(for userId: String) {
        let now = Date()
        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .first,
            completedStages: Set(PostAuthOnboardingStage.allCases),
            isComplete: true,
            startedAt: self.snapshot(for: userId).startedAt,
            completedAt: now
        )
        save(snapshot, for: userId)
        #if DEBUG
        endDebugReplay(for: userId)
        #endif
    }

    #if DEBUG
    func beginDebugReplay(for userId: String) {
        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .first,
            completedStages: [],
            isComplete: false,
            startedAt: Date(),
            completedAt: nil
        )

        save(snapshot, for: userId)
        userDefaults.set(true, forKey: debugReplayStorageKey(for: userId))
    }

    func endDebugReplay(for userId: String) {
        userDefaults.removeObject(forKey: debugReplayStorageKey(for: userId))
    }

    func isDebugReplayActive(for userId: String) -> Bool {
        userDefaults.bool(forKey: debugReplayStorageKey(for: userId))
    }
    #endif

    private func storageKey(for userId: String) -> String {
        "postAuthOnboarding.v1.\(userId)"
    }

    #if DEBUG
    private func debugReplayStorageKey(for userId: String) -> String {
        "postAuthOnboarding.debugReplay.v1.\(userId)"
    }
    #endif

    private func legacySnapshot(from data: Data) -> PostAuthOnboardingSnapshot? {
        guard let legacy = try? JSONDecoder().decode(LegacyPostAuthOnboardingSnapshot.self, from: data) else {
            return nil
        }

        let hasCompletedDisplayName = legacy.completedStages.contains(PostAuthOnboardingStage.displayName.rawValue)
        return PostAuthOnboardingSnapshot(
            currentStage: .first,
            completedStages: hasCompletedDisplayName ? [.displayName] : [],
            isComplete: false,
            startedAt: legacy.startedAt,
            completedAt: nil
        )
    }
}

struct OnboardingFirstClimbHandoffStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func stage(climbId: String, for userId: String) {
        userDefaults.set(climbId, forKey: storageKey(for: userId))
    }

    func consume(for userId: String) -> String? {
        let key = storageKey(for: userId)
        guard let climbId = userDefaults.string(forKey: key),
              !climbId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        userDefaults.removeObject(forKey: key)
        return climbId
    }

    private func storageKey(for userId: String) -> String {
        "postAuthOnboarding.firstClimbHandoff.v1.\(userId)"
    }
}

private struct LegacyPostAuthOnboardingSnapshot: Decodable {
    var currentStage: String
    var completedStages: Set<String>
    var isComplete: Bool
    var startedAt: Date
    var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case currentStage
        case completedStages
        case isComplete
        case startedAt
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentStage = try container.decodeIfPresent(String.self, forKey: .currentStage) ?? ""
        completedStages = try container.decodeIfPresent(Set<String>.self, forKey: .completedStages) ?? []
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
