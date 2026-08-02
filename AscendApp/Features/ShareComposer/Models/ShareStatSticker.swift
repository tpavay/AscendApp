import CoreGraphics
import Foundation

/// A stat that can be dropped onto the share canvas as a draggable sticker.
///
/// Per the `ascend-share-composer` skill: stat stickers are typed,
/// parameterized values — NOT per-stat bespoke layouts. Adding a new stat is
/// data (a new case + how to read it from the workout/climb), never a new code
/// path. How it is drawn is decided separately, by the card format.
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
    // Structured timeline
    case splits
    // Climb-specific
    case climbName
    case climbRank       // "#1 rank"
    case climbRankWithTotal // "#1 / 2,460 rank"
    // Derived achievement (resolved from the Best Effort cache, not the workout)
    case bestEffort
    // Aggregate (resolved from this-week totals across workouts, not one workout)
    case totals

    var id: String { rawValue }

    /// Climb-only stickers are hidden from the catalog when the workout isn't a
    /// Live Climb completion.
    var isClimbOnly: Bool {
        switch self {
        case .climbName, .climbRank, .climbRankWithTotal:
            return true
        default:
            return false
        }
    }

    /// Structured stickers render their own multi-row content instead of the
    /// normal single-stat/composite text styles.
    var isStructured: Bool {
        switch self {
        case .splits:
            return true
        default:
            return false
        }
    }

    /// Only simple scalar stats can be combined in the structure sheet.
    var supportsComposite: Bool {
        !isStructured
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
struct RGBAColor: Hashable, Codable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    static let lime = RGBAColor(r: 0.706, g: 0.8, b: 0, a: 1)
}

/// Arrangement for a multi-metric (composite) stat sticker. Single-metric
/// stickers ignore this. `grid` is the 2×2 "cube" (top-left, top-right,
/// bottom-left, bottom-right).
enum ShareStatLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case row      // metrics side by side
    case grid     // 2×2 cube
    case column   // stacked vertically

    var id: String { rawValue }
}

/// A reference to one resolvable stat: its kind plus, for injected stats
/// (`.bestEffort` / `.totals`), the key identifying which value. Composite
/// stickers hold several of these. The value itself is always resolved live
/// from canonical data — only the reference is stored.
///
/// Decodes from a bare kind string (`"steps"`) or the full object, so a card
/// template names most stats in one word.
struct ShareStatRef: Hashable, Codable, Sendable {
    var kind: ShareStatStickerKind
    var injectedStatKey: String?

    init(kind: ShareStatStickerKind, injectedStatKey: String? = nil) {
        self.kind = kind
        self.injectedStatKey = injectedStatKey
    }

    private enum CodingKeys: String, CodingKey { case kind, injectedStatKey }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let kind = try? single.decode(ShareStatStickerKind.self) {
            self.init(kind: kind)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(ShareStatStickerKind.self, forKey: .kind),
            injectedStatKey: try container.decodeIfPresent(String.self, forKey: .injectedStatKey)
        )
    }
}

/// One placed sticker on the canvas. Position is normalized (0...1) relative to
/// the canvas so it survives different export sizes; scale and rotation are the
/// user's gesture transforms.
struct ShareStickerInstance: Identifiable, Equatable {
    let id: UUID
    var kind: ShareStatStickerKind
    /// Where every label on this sticker sits relative to its value.
    ///
    /// The user's choice, and it belongs to the sticker rather than to whichever
    /// renderer runs — adding a second metric or switching arrangement can no
    /// longer discard it. Whether a given metric shows a label at all is a
    /// separate question, answered per stat by `ShareCardLabelPolicy`.
    var labelPlacement: ShareCardLabelPlacement
    /// Center point of the sticker, normalized to the canvas (0...1, 0...1).
    var position: CGPoint
    var scale: CGFloat
    /// Rotation in radians. Stored as a plain `Double` (not SwiftUI `Angle`) so
    /// the model and view models stay SwiftUI-free and Codable-friendly.
    var rotationRadians: Double
    var font: ShareStickerFont
    var color: RGBAColor
    var textBackground: ShareTextBackground
    /// When set, this sticker renders the climb's artwork (an image overlay)
    /// instead of a stat; `kind` is unused in that case.
    var climbImageVariant: ClimbImageVariant?
    /// Selector for injected stats whose value isn't resolvable from the workout
    /// alone (`.bestEffort`, `.totals`). Identifies *which* injected stat this
    /// sticker shows; the value is still read live from the view model's
    /// injected lists at render time (never stored on the model).
    var injectedStatKey: String?
    /// Extra metrics beyond the primary (`kind` + `injectedStatKey`), making this
    /// a composite sticker. Empty = single-metric sticker (the common case).
    var extraStats: [ShareStatRef]
    /// Arrangement used when the sticker shows more than one metric.
    var layout: ShareStatLayout

    /// Image stickers (climb artwork) don't take text styling.
    var isImage: Bool { climbImageVariant != nil }

    /// The primary metric as a reference.
    var primaryStatRef: ShareStatRef { ShareStatRef(kind: kind, injectedStatKey: injectedStatKey) }
    /// All metrics in display order (primary first, then extras).
    var statRefs: [ShareStatRef] { [primaryStatRef] + extraStats }
    /// True when the sticker renders more than one metric.
    var isComposite: Bool { !extraStats.isEmpty }
    /// True when this is a text sticker that includes the climb name (renameable).
    var containsClimbName: Bool { !isImage && statRefs.contains { $0.kind == .climbName } }
    /// True when this sticker uses a structured renderer, such as split rows.
    var isStructured: Bool { !isImage && kind.isStructured && extraStats.isEmpty }

    init(
        id: UUID = UUID(),
        kind: ShareStatStickerKind,
        labelPlacement: ShareCardLabelPlacement = .below,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationRadians: Double = 0,
        font: ShareStickerFont = .montserrat,
        color: RGBAColor = .white,
        textBackground: ShareTextBackground = .none,
        climbImageVariant: ClimbImageVariant? = nil,
        injectedStatKey: String? = nil,
        extraStats: [ShareStatRef] = [],
        layout: ShareStatLayout = .row
    ) {
        self.id = id
        self.kind = kind
        self.labelPlacement = labelPlacement
        self.position = position
        self.scale = scale
        self.rotationRadians = rotationRadians
        self.font = font
        self.color = color
        self.textBackground = textBackground
        self.climbImageVariant = climbImageVariant
        self.injectedStatKey = injectedStatKey
        self.extraStats = extraStats
        self.layout = layout
    }
}

/// A resolved, display-ready stat value (label + value) read from canonical data.
struct ResolvedShareStat: Equatable, Sendable {
    let kind: ShareStatStickerKind
    /// Short uppercase label, e.g. "STEPS", "DURATION", "RANK".
    let label: String
    /// Formatted value, e.g. "2,096", "22:10", "#60".
    let value: String
    /// A secondary facet of the same stat, when it has one: the splits subtitle,
    /// the field size behind a rank. Cards read it as `facet: "detail"`; nothing
    /// else about the stat changes.
    let detail: String?

    init(kind: ShareStatStickerKind, label: String, value: String, detail: String? = nil) {
        self.kind = kind
        self.label = label
        self.value = value
        self.detail = detail
    }

    /// The text for one facet, or nil when this stat does not carry it.
    func text(for facet: ShareCardStatFacet) -> String? {
        switch facet {
        case .value: return value
        case .label: return label.isEmpty ? nil : label
        case .detail: return detail
        }
    }
}

/// Display-ready split rows for a structured share sticker.
struct ResolvedShareSplits: Equatable {
    let label: String
    let value: String
    let subtitle: String
    let rows: [ResolvedShareSplitRow]
    let hasHeartRate: Bool
}

struct ResolvedShareSplitRow: Identifiable, Equatable {
    let index: Int
    let segmentText: String
    let rangeText: String
    let stepsText: String
    let spmText: String
    let heartRateText: String?
    /// 0...1 bar fill, already normalized for display.
    let progress: Double

    var id: Int { index }
}
