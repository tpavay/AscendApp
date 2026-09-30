import Foundation
import Observation

/// The athlete editor's state: the look being tried on, which piece of kit the colour row is
/// dressing, and the save.
@MainActor
@Observable
final class AthleteEditorModel {
    /// The piece of kit the one colour row dresses.
    enum Garment: String, CaseIterable, Identifiable {
        case tank, shorts, shoes

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    var draft: AthleteLook
    var garment: Garment = .tank
    private(set) var isSaving = false
    private(set) var saveFailed = false

    init(look: AthleteLook) {
        draft = look
    }

    /// Switching body keeps the rest of the look, and moves a hairstyle that was only the old
    /// body's first to the new body's.
    func choose(body: AthleteLook.Body) {
        draft = draft.switching(to: body)
    }

    /// The colour of the piece of kit the colour row is dressing.
    var kitColor: AthleteLook.KitColor {
        get {
            switch garment {
            case .tank: draft.top
            case .shorts: draft.bottom
            case .shoes: draft.shoes
            }
        }
        set {
            switch garment {
            case .tank: draft.top = newValue
            case .shorts: draft.bottom = newValue
            case .shoes: draft.shoes = newValue
            }
        }
    }

    /// Saves the look to the climber's account. Returns whether it saved; a failure stays on
    /// screen until the next try.
    func save(userId: String, to store: AthleteLookStore) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            try await store.save(draft, userId: userId)
            return true
        } catch {
            saveFailed = true
            TelemetryManager.shared.recordError(error, context: .firestore, code: "athlete_look_save_failed")
            return false
        }
    }
}
