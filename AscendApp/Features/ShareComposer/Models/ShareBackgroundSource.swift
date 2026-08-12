import SwiftUI
import UIKit

/// What fills the share canvas. Backgrounds are decoupled from stats — a
/// background is just a backing layer, never bundled with baked-in stats.
enum ShareBackgroundSource: Identifiable {
    /// A still image chosen from the user's Camera Roll.
    case photo(UIImage)
    /// A generated 9:19.5 recap card. Unlike arbitrary photos, this must not be
    /// aspect-fill cropped when it is used as the canvas background.
    case recap(UIImage)
    /// A looping video chosen from the user's Camera Roll. (Export support is a
    /// fast-follow; editing/preview works in V1.)
    case video(URL)
    /// A bundled / known preset background.
    case preset(ShareComposerPreset)

    var id: String {
        switch self {
        case .photo:
            return "photo"
        case .recap:
            return "recap"
        case .video(let url):
            return "video-\(url.absoluteString)"
        case .preset(let preset):
            return "preset-\(preset.id)"
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

/// A preset background. For a climb, the climb's own artwork (hero / card /
/// thumbnail) is offered as a background — backgrounds the user can drop stat
/// stickers on top of.
enum ShareComposerPreset: Identifiable, Equatable {
    case climbImage(Climb, ClimbImageVariant)

    var id: String {
        switch self {
        case .climbImage(let climb, let variant):
            return "climb-\(climb.id)-\(variant.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .climbImage(_, let variant):
            switch variant {
            case .hero: return "Hero"
            case .card: return "Card"
            case .thumb: return "Thumbnail"
            }
        }
    }
}
