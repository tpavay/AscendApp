import Foundation
import Observation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Whether the signed-in climber wants a push when they take a crown.
///
/// The answer belongs to the account, not the phone: it is read from the server's
/// `communication_preferences/current.pushChampionCrownEnabled` - the same field the champion
/// push reads - so another climber signing in here, or this climber on a new phone, sees
/// their own answer. On unless they turn it off: the alert is about their own win, so it is
/// opt-out, and an absent preference means on, exactly as the server treats it.
@MainActor
@Observable
final class ChampionPushPreference {
    private(set) var isEnabled = true
    private(set) var isSaving = false
    /// Set when a change could not be saved; the switch has already gone back to what the
    /// server holds.
    private(set) var saveErrorMessage: String?

    @ObservationIgnored private let loadStored: @Sendable () async throws -> Bool?
    @ObservationIgnored private let saveStored: @Sendable (Bool) async throws -> Void

    init(
        load: @escaping @Sendable () async throws -> Bool? = { try await ChampionPushPreference.loadFromServer() },
        save: @escaping @Sendable (Bool) async throws -> Void = { isEnabled in
            try await PushNotificationService.shared.setChampionPushEnabled(isEnabled)
        }
    ) {
        loadStored = load
        saveStored = save
    }

    /// Reads the account's answer. An unreadable preference keeps showing on, the server's
    /// own default, rather than guessing from another account.
    func load() async {
        guard let stored = try? await loadStored() else { return }
        isEnabled = stored
    }

    func setEnabled(_ newValue: Bool) async {
        guard newValue != isEnabled, !isSaving else { return }
        let previous = isEnabled
        isEnabled = newValue
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            try await saveStored(newValue)
        } catch {
            isEnabled = previous
            saveErrorMessage = "Couldn't save. Check your connection and try again."
        }
    }

    nonisolated static func loadFromServer() async throws -> Bool? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("communication_preferences")
            .document("current")
            .getDocument()
        return snapshot.data()?["pushChampionCrownEnabled"] as? Bool ?? true
    }
}
