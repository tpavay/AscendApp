import Foundation

/// A color grade applied to the share *background only* (never the stat
/// stickers). Each case maps to a combination of SwiftUI image adjustments in
/// `View.shareBackgroundFilter(_:)`. All cases are resolution-independent, so
/// the editing preview and the high-res export match exactly.
///
/// Geometric effects (zoom blur, motion blur, fisheye) are intentionally out of
/// scope here — they require Core Image / Metal and per-frame work for video.
enum ShareBackgroundFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    // Color grades (SwiftUI image adjustments — resolution-independent)
    case original
    case mono
    case noir
    case vivid
    case fade
    case warm
    case cool
    // Geometric grades (Core Image — applied to the source photo)
    case zoomBlur
    case motionBlur
    case fisheye

    var id: String { rawValue }

    /// Geometric filters are rendered through Core Image on the source photo,
    /// not via SwiftUI color modifiers.
    var isGeometric: Bool {
        switch self {
        case .zoomBlur, .motionBlur, .fisheye: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .vivid: return "Vivid"
        case .fade: return "Fade"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .zoomBlur: return "Zoom Blur"
        case .motionBlur: return "Motion Blur"
        case .fisheye: return "Fisheye"
        }
    }
}
