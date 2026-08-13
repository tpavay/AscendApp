import Foundation

struct ShareComposerSourceOptions: Equatable {
    let hasPresets: Bool
    let hasRecaps: Bool

    static let climb = ShareComposerSourceOptions(hasPresets: true, hasRecaps: true)
    static let cameraRollOnly = ShareComposerSourceOptions(hasPresets: false, hasRecaps: false)

    var title: String {
        switch (hasPresets, hasRecaps) {
        case (true, true):
            return "Three ways to start."
        case (true, false), (false, true):
            return "Two ways to start."
        case (false, false):
            return "Start with Camera Roll."
        }
    }

    var message: String {
        var descriptions = ["Camera Roll is your own photos."]
        if hasPresets {
            descriptions.append("Presets are Ascend climb artwork.")
        }
        if hasRecaps {
            descriptions.append("Recaps are ready-made cards with the stats already laid out.")
        }
        return descriptions.joined(separator: " ")
    }
}

/// Which of the edit rail's controls the selected sticker actually shows, so the mark names only
/// what the climber can see. A curated cluster arrives already arranged and a structured sticker
/// owns its own rows, so neither offers arrangement or alignment.
struct ShareComposerEditRailOptions: Equatable {
    let offersArrangement: Bool
    let offersAlignment: Bool

    static let full = ShareComposerEditRailOptions(offersArrangement: true, offersAlignment: true)
    static let styleOnly = ShareComposerEditRailOptions(offersArrangement: false, offersAlignment: false)

    init(offersArrangement: Bool, offersAlignment: Bool) {
        self.offersArrangement = offersArrangement
        self.offersAlignment = offersAlignment
    }

    /// Nil when the sticker has no rail at all: climb artwork takes no text styling, so there is
    /// no control left for a mark to point at.
    init?(sticker: ShareStickerInstance) {
        guard !sticker.isImage else { return nil }
        self.init(
            offersArrangement: sticker.kind.supportsComposite && !sticker.isPreset,
            offersAlignment: !sticker.isStructured && !sticker.isPreset
        )
    }

    var message: String {
        var controls: [String] = []
        if offersArrangement { controls.append("arrangement") }
        if offersAlignment { controls.append("alignment") }
        controls.append("font")
        controls.append("color")
        return "Change the \(Self.sentenceList(controls)). Add a panel when the picture is busy."
    }

    private static func sentenceList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        guard items.count > 2 else { return "\(items[0]) and \(last)" }
        return items.dropLast().joined(separator: ", ") + ", and " + last
    }
}

enum ShareComposerCoachMark: Int, CaseIterable, Identifiable {
    case sources
    case stats
    case editRail
    case filters

    static let seenStorageKey = "shareComposerCoachMarksSeen"

    var id: Int { rawValue }

    var title: String {
        title(sourceOptions: .climb)
    }

    func title(sourceOptions: ShareComposerSourceOptions) -> String {
        switch self {
        case .sources:
            return sourceOptions.title
        case .stats:
            return "Your stats, ready to use."
        case .editRail:
            return "Style what you selected."
        case .filters:
            return "Set the mood."
        }
    }

    var message: String {
        message(sourceOptions: .climb, editRailOptions: .full)
    }

    func message(
        sourceOptions: ShareComposerSourceOptions,
        editRailOptions: ShareComposerEditRailOptions
    ) -> String {
        switch self {
        case .sources:
            return sourceOptions.message
        case .stats:
            return "Tap any available session stat or a ready-made group to add it. Then move or resize the sticker, or drag it to the trash to delete it."
        case .editRail:
            return editRailOptions.message
        case .filters:
            return "Filters change the whole picture. Drag and pinch your photo or a preset background. Recaps stay fixed."
        }
    }
}
