import Foundation
import Observation

/// The signed-in climber's athlete, for every surface that shows or edits it: the Mountain,
/// onboarding, Profile and climb setup.
///
/// The saved look is kept on the device too, for the signed-in account only, so a climb that
/// starts offline still wears it. A climber who never saved one - everyone who finished onboarding
/// before the athlete step existed - climbs as the athlete their gender answer starts them with,
/// and nothing is published for them until they save.
@MainActor
@Observable
final class AthleteLookStore {
    static let shared = AthleteLookStore()

    /// The look the climber saved, or nil when they have not.
    private(set) var saved: AthleteLook?
    /// The athlete they start with until they save one.
    private(set) var starting = AthleteLook.starting(for: nil)
    private(set) var userId: String?

    @ObservationIgnored private let repository: AthleteLookRepository
    @ObservationIgnored private let genderSource: @Sendable (String) async -> ProfileGender?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loading: Task<Void, Never>?

    static let cacheKey = "athleteLook.signedIn"

    private struct Cached: Codable {
        let userId: String
        let look: AthleteLook
    }

    init(
        repository: AthleteLookRepository = FirestoreAthleteLookRepository.shared,
        genderSource: @escaping @Sendable (String) async -> ProfileGender? = { userId in
            (try? await UserDataRepository.shared.getUserFromFirestore(userId: userId))?.gender.flatMap(ProfileGender.init(rawValue:))
        },
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.genderSource = genderSource
        self.defaults = defaults
    }

    /// What the climber looks like now: their saved look, else the one they start with.
    var current: AthleteLook {
        saved ?? starting
    }

    /// Reads the climber's look, from this device at once and then from their account. Safe to
    /// call from every surface that shows it: once a read has answered, later calls for the same
    /// climber return at once; a read that failed is tried again by the next call.
    func load(userId: String) async {
        if self.userId != userId {
            loading?.cancel()
            loading = nil
            hasAnswered = false
            if self.userId != nil {
                starting = .starting(for: nil)
            }
            self.userId = userId
            saved = cachedLook(for: userId)
        }
        guard !hasAnswered else { return }
        if let loading {
            await loading.value
            return
        }
        let task = Task { [repository, genderSource] in
            async let stored = Self.read(userId, from: repository)
            async let gender = genderSource(userId)
            let (look, answer) = await (stored, gender)
            guard !Task.isCancelled, self.userId == userId else { return }
            self.loading = nil
            if let answer {
                self.starting = .starting(for: answer)
            }
            guard case .success(let found) = look else { return }
            self.hasAnswered = true
            if let found {
                self.saved = found
                self.cache(found, for: userId)
            }
        }
        loading = task
        await task.value
    }

    @ObservationIgnored private var hasAnswered = false

    private nonisolated static func read(_ userId: String, from repository: AthleteLookRepository) async -> Result<AthleteLook?, any Error> {
        do {
            return .success(try await repository.fetchLook(userId: userId))
        } catch {
            return .failure(error)
        }
    }

    /// The athlete onboarding starts a new climber with, from the gender answer they just gave.
    func start(with gender: ProfileGender?) {
        starting = .starting(for: gender)
    }

    /// Saves the climber's look to their account; others see it on their stairs from their next
    /// read. Throws when it could not be saved, and keeps nothing it could not save.
    func save(_ look: AthleteLook, userId: String) async throws {
        try await repository.saveLook(look, userId: userId)
        guard self.userId == userId || self.userId == nil else { return }
        self.userId = userId
        saved = look
        cache(look, for: userId)
    }

    /// Forgets the account's look on this device, on sign-out and account deletion.
    func clearAccountScopedState() {
        loading?.cancel()
        loading = nil
        hasAnswered = false
        userId = nil
        saved = nil
        starting = .starting(for: nil)
        defaults.removeObject(forKey: Self.cacheKey)
    }

    private func cachedLook(for userId: String) -> AthleteLook? {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              cached.userId == userId else { return nil }
        return cached.look
    }

    private func cache(_ look: AthleteLook, for userId: String) {
        guard let data = try? JSONEncoder().encode(Cached(userId: userId, look: look)) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }
}
