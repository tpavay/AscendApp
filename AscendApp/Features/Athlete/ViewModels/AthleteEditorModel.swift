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
    /// Whether the climber's account has answered with their saved look, or with none.
    enum SavedLookRead: Equatable {
        case reading, read, failed
    }

    /// Saving is only safe once this is `.read`: before then the editor holds this device's copy
    /// or the default athlete, and saving it would replace the look the climber saved.
    private(set) var savedLookRead: SavedLookRead = .reading
    /// The look the editor last took from the store; the climber has edits when the draft
    /// differs from it.
    private var adoptedLook: AthleteLook

    init(look: AthleteLook) {
        draft = look
        adoptedLook = look
    }

    var hasEdits: Bool {
        draft != adoptedLook
    }

    var canSave: Bool {
        !isSaving && savedLookRead == .read
    }

    /// Reads the climber's saved look and dresses the editor in it. A read the account never
    /// answered leaves saving off until a retry succeeds.
    ///
    /// The editor cannot trust whoever opened it to have loaded the store first: the Just Climb
    /// chip opened it on an unread store after a relaunch, showed the default athlete, and a
    /// save there overwrote the look the climber had saved.
    func loadSavedLook(userId: String, from store: AthleteLookStore) async {
        savedLookRead = .reading
        guard await store.load(userId: userId) else {
            savedLookRead = .failed
            return
        }
        adopt(store.current)
        savedLookRead = .read
    }

    /// Takes a look the store learned about, unless the climber has already changed something,
    /// so a late answer never undoes a choice they tapped.
    func adopt(_ look: AthleteLook) {
        guard !hasEdits else { return }
        draft = look
        adoptedLook = look
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
        guard canSave else { return false }
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
