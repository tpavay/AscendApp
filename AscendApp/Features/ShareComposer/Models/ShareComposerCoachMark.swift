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
        message(sourceOptions: .climb)
    }

    func message(sourceOptions: ShareComposerSourceOptions) -> String {
        switch self {
        case .sources:
            return sourceOptions.message
        case .stats:
            return "Tap any available session stat or a ready-made group to add it. Then move or resize the sticker, or drag it to the trash to delete it."
        case .editRail:
            return "Change the arrangement, alignment, font, and color. Add a panel when the picture is busy."
        case .filters:
            return "Filters change the whole picture. Drag and pinch your photo or a preset background. Recaps stay fixed."
        }
    }
}
