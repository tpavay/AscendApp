import CoreGraphics
import Foundation

/// A stat that can be dropped onto the share canvas as a draggable sticker.
///
/// Per CLAUDE.md's Share Composer Architecture: stat stickers are typed,
/// parameterized values — NOT per-stat bespoke layouts. Adding a new stat is
/// data (a new case + how to read it from the workout/climb), never a new code
/// path. The visual treatment is decided separately by `ShareStickerStyle`.
enum ShareStatStickerKind: String, CaseIterable, Identifiable, Codable, Sendable {
    // Universal
    case workoutName
    case date
    case duration
    case steps
    case calories
    case pace            // steps per minute
    case avgHeartRate
    case maxHeartRate
    case verticalClimb
    case addedWeight
    // Climb-specific
    case climbName
    case climbRank       // "Nth finisher"
    // Derived achievement (resolved from the Best Effort cache, not the workout)
    case bestEffort

    var id: String { rawValue }

    /// Climb-only stickers are hidden from the catalog when the workout isn't a
    /// Live Climb completion.
    var isClimbOnly: Bool {
        switch self {
        case .climbName, .climbRank:
            return true
        default:
            return false
        }
    }
}

/// Visual treatment for a stat sticker. Any stat can be rendered in any style —
/// the style is a reusable styled view, not a per-stat layout.
enum ShareStickerStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Big value with a small uppercase unit/label beneath it.
    case display
    /// Small uppercase label stacked above the value.
    case stacked
    /// Single-line "label · value" chip on a translucent pill.
    case chip

    var id: String { rawValue }

    /// Cycle order for tap-to-change.
    func next() -> ShareStickerStyle {
        let all = ShareStickerStyle.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

/// Typeface options offered in the font picker. Custom faces resolve to bundled
/// fonts; the rest use system font designs (no bundled files needed).
enum ShareStickerFont: String, CaseIterable, Identifiable, Codable, Sendable {
    case montserrat   // brand default
    case anton        // heavy condensed (bundled)
    case playfair     // elegant serif italic (bundled)
    case spaceMono    // typewriter / receipt (bundled)
    case rounded      // SF Pro rounded (system)
    case thin         // SF Pro ultralight (system)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .montserrat: return "Ascend"
        case .anton: return "Bold"
        case .playfair: return "Elegant"
        case .spaceMono: return "Mono"
        case .rounded: return "Round"
        case .thin: return "Thin"
        }
    }
}

/// Optional backing plate behind a sticker's text for legibility. Cycled by
/// tapping the background chip control.
enum ShareTextBackground: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case dark
    case grey

    var id: String { rawValue }

    func next() -> ShareTextBackground {
        let all = ShareTextBackground.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

/// SwiftUI-free RGBA color (0...1) stored on the model so the view model and
/// persistence stay free of SwiftUI's `Color`.
struct RGBAColor: Equatable, Codable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    static let lime = RGBAColor(r: 0.706, g: 0.8, b: 0, a: 1)
}

/// One placed sticker on the canvas. Position is normalized (0...1) relative to
/// the canvas so it survives different export sizes; scale and rotation are the
/// user's gesture transforms.
struct ShareStickerInstance: Identifiable, Equatable {
    let id: UUID
    var kind: ShareStatStickerKind
    var style: ShareStickerStyle
    /// Center point of the sticker, normalized to the canvas (0...1, 0...1).
    var position: CGPoint
    var scale: CGFloat
    /// Rotation in radians. Stored as a plain `Double` (not SwiftUI `Angle`) so
    /// the model and view models stay SwiftUI-free and Codable-friendly.
    var rotationRadians: Double
    var font: ShareStickerFont
    var color: RGBAColor
    var textBackground: ShareTextBackground

    init(
        id: UUID = UUID(),
        kind: ShareStatStickerKind,
        style: ShareStickerStyle = .display,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationRadians: Double = 0,
        font: ShareStickerFont = .montserrat,
        color: RGBAColor = .white,
        textBackground: ShareTextBackground = .none
    ) {
        self.id = id
        self.kind = kind
        self.style = style
        self.position = position
        self.scale = scale
        self.rotationRadians = rotationRadians
        self.font = font
        self.color = color
        self.textBackground = textBackground
    }
}

/// A resolved, display-ready stat value (label + value) read from canonical data.
struct ResolvedShareStat: Equatable {
    let kind: ShareStatStickerKind
    /// Short uppercase label, e.g. "STEPS", "DURATION", "FINISHER".
    let label: String
    /// Formatted value, e.g. "2,096", "22:10", "#60".
    let value: String
}
