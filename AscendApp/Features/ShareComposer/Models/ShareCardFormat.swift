import CoreGraphics
import Foundation

/// The declarative share-card format: one `Codable` tree describing a card, its
/// elements, their arrangement, and the intent expressed per element.
///
/// One format, one interpreter (`ShareCardRenderer`). A sticker on the canvas and
/// a full recap template are the same tree at different sizes, so a per-element
/// setting can no longer be honoured by one renderer and silently dropped by
/// another — there is only one renderer to honour it.
///
/// **Forward compatibility.** The format is shaped so it could later be delivered
/// remotely without a rewrite (see `ShareCardTemplateStore`), which means old
/// binaries must survive newer payloads:
/// - every template declares `minRendererVersion`; the store drops what it is too
///   old to draw before anything is rendered,
/// - an unknown element type decodes to `.unsupported` and renders nothing,
/// - an unknown stat reference decodes to `nil` and its element disappears,
///   exactly as an unresolvable stat already does.
///
/// The schema is deliberately **closed**: a fixed set of element types chosen by a
/// Swift `switch`. There is no expression language and no escape hatch that takes
/// a script — that line is what keeps remote delivery inside App Review 2.5.2.

// MARK: - Document

/// A decoded template payload. `formatVersion` versions the payload shape; the
/// filename carries it too (`share-card-templates-v1.json`) so a v2 schema can
/// ship alongside v1 rather than breaking clients that ask for v1.
struct ShareCardDocument: Codable, Equatable, Sendable {
    var formatVersion: Int
    var templates: [ShareCardTemplate]

    init(formatVersion: Int, templates: [ShareCardTemplate]) {
        self.formatVersion = formatVersion
        self.templates = templates
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, templates }

    /// Templates are decoded one at a time and a template that fails is dropped.
    ///
    /// The element-level guarantees — an unknown element draws nothing, an
    /// unresolvable stat drops its element — are worth nothing if one malformed
    /// template throws the array away with the five valid ones and empties the
    /// picker. The document degrades the way an element does.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)

        var list = try container.nestedUnkeyedContainer(forKey: .templates)
        var decoded: [ShareCardTemplate] = []
        decoded.reserveCapacity(list.count ?? 0)
        while !list.isAtEnd {
            // Decoded through a never-throwing wrapper: a container's index does
            // not advance past an element whose decode threw, so catching here
            // rather than inside would loop forever on the first bad template.
            if let template = try list.decode(DecodedTemplate.self).template {
                decoded.append(template)
            }
        }
        templates = decoded
    }
}

/// One array element of `ShareCardDocument.templates`, nil when it did not decode.
private struct DecodedTemplate: Decodable {
    let template: ShareCardTemplate?

    init(from decoder: any Decoder) throws {
        template = try? ShareCardTemplate(from: decoder)
    }
}

/// Data a template needs before it is worth offering. A template that asks for a
/// climb is hidden when there is no climb, rather than rendering a card with
/// holes in it.
enum ShareCardRequirement: String, Codable, Sendable {
    case climb
    /// A resolved leaderboard standing. A card built around the percentile is
    /// hollow without one, so it is not offered rather than drawn empty.
    case standing
}

struct ShareCardTemplate: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// User-facing name in the picker.
    var title: String
    /// Lowest renderer version that can draw this template. Clients below it skip
    /// the template instead of drawing it wrong.
    var minRendererVersion: Int
    var requires: [ShareCardRequirement]
    /// Card-level backdrop drawn beneath `root`.
    var background: ShareCardFill?
    /// The fixed bottom wordmark tint. Its placement is owned by the template
    /// wrapper so card content cannot move or omit the brand lockup.
    var wordmarkTint: ShareCardTint
    var root: ShareCardNode

    private enum CodingKeys: String, CodingKey {
        case id, title, minRendererVersion, requires, background, wordmarkTint, root
    }

    init(
        id: String,
        title: String,
        minRendererVersion: Int = ShareCardFormat.rendererVersion,
        requires: [ShareCardRequirement] = [],
        background: ShareCardFill? = nil,
        wordmarkTint: ShareCardTint = ShareCardTint(.value),
        root: ShareCardNode
    ) {
        self.id = id
        self.title = title
        self.minRendererVersion = minRendererVersion
        self.requires = requires
        self.background = background
        self.wordmarkTint = wordmarkTint
        self.root = root
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            minRendererVersion: try container.value(.minRendererVersion, default: 1),
            requires: try container.value(.requires, default: []),
            background: try container.decodeIfPresent(ShareCardFill.self, forKey: .background),
            wordmarkTint: try container.value(.wordmarkTint, default: ShareCardTint(.value)),
            root: try container.decode(ShareCardNode.self, forKey: .root)
        )
    }
}

enum ShareCardFormat {
    /// Bumped whenever the renderer gains an element type or a knob that a
    /// template may depend on. Templates above this are skipped by this binary.
    static let rendererVersion = 2

    /// The card's design space. Every size in a template is in these units; the
    /// whole card is scaled once, never per element.
    static let designSize = CGSize(width: 390, height: 390 / (9.0 / 19.5))
    static let aspectRatio: CGFloat = 9.0 / 19.5
}

// MARK: - Node

/// One element plus the modifiers wrapped around it. Authored flat, so a node is
/// a single JSON object: `{"type": "stack", "axis": "vertical", "padding": 26}`.
struct ShareCardNode: Codable, Equatable, Sendable {
    var element: ShareCardElement
    var modifiers: ShareCardModifiers

    init(_ element: ShareCardElement, modifiers: ShareCardModifiers = ShareCardModifiers()) {
        self.element = element
        self.modifiers = modifiers
    }

    init(from decoder: any Decoder) throws {
        element = try ShareCardElement(from: decoder)
        modifiers = try ShareCardModifiers(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try element.encode(to: encoder)
        try modifiers.encode(to: encoder)
    }
}

/// Modifiers every element accepts, applied in one place by the interpreter so
/// they behave identically whatever the element is.
struct ShareCardModifiers: Codable, Equatable, Sendable {
    var padding: ShareCardEdgeInsets?
    var frame: ShareCardFrame?
    var background: ShareCardFill?
    /// Shape the background fill and border are drawn in. Defaults to a rectangle.
    var backgroundShape: ShareCardShapeKind?
    var border: ShareCardStroke?
    var rotationDegrees: Double?
    var opacity: Double?
    var shadow: ShareCardShadow?

    init(
        padding: ShareCardEdgeInsets? = nil,
        frame: ShareCardFrame? = nil,
        background: ShareCardFill? = nil,
        backgroundShape: ShareCardShapeKind? = nil,
        border: ShareCardStroke? = nil,
        rotationDegrees: Double? = nil,
        opacity: Double? = nil,
        shadow: ShareCardShadow? = nil
    ) {
        self.padding = padding
        self.frame = frame
        self.background = background
        self.backgroundShape = backgroundShape
        self.border = border
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
        self.shadow = shadow
    }

    private enum CodingKeys: String, CodingKey {
        case padding, frame, background, backgroundShape, border, rotationDegrees, opacity, shadow
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            padding: try container.decodeIfPresent(ShareCardEdgeInsets.self, forKey: .padding),
            frame: try container.decodeIfPresent(ShareCardFrame.self, forKey: .frame),
            background: try container.decodeIfPresent(ShareCardFill.self, forKey: .background),
            backgroundShape: try container.decodeIfPresent(ShareCardShapeKind.self, forKey: .backgroundShape),
            border: try container.decodeIfPresent(ShareCardStroke.self, forKey: .border),
            rotationDegrees: try container.decodeIfPresent(Double.self, forKey: .rotationDegrees),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity),
            shadow: try container.decodeIfPresent(ShareCardShadow.self, forKey: .shadow)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(padding, forKey: .padding)
        try container.encodeIfPresent(frame, forKey: .frame)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encodeIfPresent(backgroundShape, forKey: .backgroundShape)
        try container.encodeIfPresent(border, forKey: .border)
        try container.encodeIfPresent(rotationDegrees, forKey: .rotationDegrees)
        try container.encodeIfPresent(opacity, forKey: .opacity)
        try container.encodeIfPresent(shadow, forKey: .shadow)
    }
}

// MARK: - Elements

enum ShareCardElement: Codable, Equatable, Sendable {
    case stack(ShareCardStack)
    case text(ShareCardText)
    case metric(ShareCardMetric)
    case artwork(ShareCardArtwork)
    case splits(ShareCardSplitsTableSpec)
    case rankTab(ShareCardRankTabSpec)
    case standing(ShareCardStandingSpec)
    case progress(ShareCardProgress)
    case shape(ShareCardShapeElement)
    case rule(ShareCardRule)
    case wordmark(ShareCardWordmark)
    case spacer(minLength: Double?)
    /// An element type this binary does not know. Renders nothing. Combined with
    /// `minRendererVersion` filtering this should be unreachable — which is
    /// exactly why it exists.
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey { case type, minLength }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.value(.type, default: "unsupported")
        switch type {
        case "stack": self = .stack(try ShareCardStack(from: decoder))
        case "text": self = .text(try ShareCardText(from: decoder))
        case "metric": self = .metric(try ShareCardMetric(from: decoder))
        case "artwork": self = .artwork(try ShareCardArtwork(from: decoder))
        case "splits": self = .splits(try ShareCardSplitsTableSpec(from: decoder))
        case "rankTab": self = .rankTab(try ShareCardRankTabSpec(from: decoder))
        case "standing": self = .standing(try ShareCardStandingSpec(from: decoder))
        case "progress": self = .progress(try ShareCardProgress(from: decoder))
        case "shape": self = .shape(try ShareCardShapeElement(from: decoder))
        case "rule": self = .rule(try ShareCardRule(from: decoder))
        case "wordmark": self = .wordmark(try ShareCardWordmark(from: decoder))
        case "spacer": self = .spacer(minLength: try container.decodeIfPresent(Double.self, forKey: .minLength))
        default: self = .unsupported(type: type)
        }
    }

    func encode(to encoder: any Encoder) throws {
        // The type tag and the payload share one JSON object, so each write takes
        // its own short-lived container rather than holding one across a nested
        // `encode(to:)`.
        func writeType(_ type: String) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }

        switch self {
        case .stack(let stack):
            try writeType("stack")
            try stack.encode(to: encoder)
        case .text(let text):
            try writeType("text")
            try text.encode(to: encoder)
        case .metric(let metric):
            try writeType("metric")
            try metric.encode(to: encoder)
        case .artwork(let artwork):
            try writeType("artwork")
            try artwork.encode(to: encoder)
        case .splits(let splits):
            try writeType("splits")
            try splits.encode(to: encoder)
        case .rankTab(let rankTab):
            try writeType("rankTab")
            try rankTab.encode(to: encoder)
        case .standing(let standing):
            try writeType("standing")
            try standing.encode(to: encoder)
        case .progress(let progress):
            try writeType("progress")
            try progress.encode(to: encoder)
        case .shape(let shape):
            try writeType("shape")
            try shape.encode(to: encoder)
        case .rule(let rule):
            try writeType("rule")
            try rule.encode(to: encoder)
        case .wordmark(let wordmark):
            try writeType("wordmark")
            try wordmark.encode(to: encoder)
        case .spacer(let minLength):
            try writeType("spacer")
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(minLength, forKey: .minLength)
        case .unsupported(let type):
            try writeType(type)
        }
    }
}

/// A row, column, layered group, or wrapped grid of children.
struct ShareCardStack: Codable, Equatable, Sendable {
    var axis: ShareCardAxis
    var spacing: Double
    var alignment: ShareCardAlignment
    /// On a vertical stack, wraps children into rows of this many — the 2×2 cube.
    var gridColumns: Int?
    /// Render at most this many children that actually produced content. Lets a
    /// template list metrics in priority order and take the first few that resolve
    /// for this workout, instead of hardcoding a selection in Swift.
    var maxVisibleChildren: Int?
    /// Spacing between wrapped grid rows. Falls back to `spacing`.
    var rowSpacing: Double?
    var children: [ShareCardNode]

    init(
        axis: ShareCardAxis,
        spacing: Double = 0,
        alignment: ShareCardAlignment = .center,
        gridColumns: Int? = nil,
        maxVisibleChildren: Int? = nil,
        rowSpacing: Double? = nil,
        children: [ShareCardNode]
    ) {
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.gridColumns = gridColumns
        self.maxVisibleChildren = maxVisibleChildren
        self.rowSpacing = rowSpacing
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case axis, spacing, alignment, gridColumns, maxVisibleChildren, rowSpacing, children
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            axis: try container.value(.axis, default: .vertical),
            spacing: try container.value(.spacing, default: 0),
            alignment: try container.value(.alignment, default: .center),
            gridColumns: try container.decodeIfPresent(Int.self, forKey: .gridColumns),
            maxVisibleChildren: try container.decodeIfPresent(Int.self, forKey: .maxVisibleChildren),
            rowSpacing: try container.decodeIfPresent(Double.self, forKey: .rowSpacing),
            children: try container.value(.children, default: [])
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(axis, forKey: .axis)
        try container.encode(spacing, forKey: .spacing)
        try container.encode(alignment, forKey: .alignment)
        try container.encodeIfPresent(gridColumns, forKey: .gridColumns)
        try container.encodeIfPresent(maxVisibleChildren, forKey: .maxVisibleChildren)
        try container.encodeIfPresent(rowSpacing, forKey: .rowSpacing)
        try container.encode(children, forKey: .children)
    }
}

/// One run of text, assembled from literal and stat-backed segments.
struct ShareCardText: Codable, Equatable, Sendable {
    var segments: [ShareCardTextSegment]
    /// Used when `segments` cannot be resolved. Nil means the element disappears.
    var fallback: [ShareCardTextSegment]?
    var style: ShareCardTextStyle
    var transform: ShareCardTextTransform

    init(
        segments: [ShareCardTextSegment],
        fallback: [ShareCardTextSegment]? = nil,
        style: ShareCardTextStyle,
        transform: ShareCardTextTransform = .none
    ) {
        self.segments = segments
        self.fallback = fallback
        self.style = style
        self.transform = transform
    }

    private enum CodingKeys: String, CodingKey { case segments, fallback, style, transform }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            segments: try container.value(.segments, default: []),
            fallback: try container.decodeIfPresent([ShareCardTextSegment].self, forKey: .fallback),
            style: try container.decode(ShareCardTextStyle.self, forKey: .style),
            transform: try container.value(.transform, default: .none)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(fallback, forKey: .fallback)
        try container.encode(style, forKey: .style)
        try container.encode(transform, forKey: .transform)
    }
}

/// Which facet of a resolved stat a segment reads.
enum ShareCardStatFacet: String, Codable, Sendable {
    /// The formatted value: `2,096`, `22:10`, `#60`.
    case value
    /// The short uppercase label: `STEPS`, `AVG BPM`.
    case label
    /// A secondary facet the stat carries: the splits subtitle, a rank's field size.
    case detail
}

/// A piece of a text run. A bare JSON string is a literal, so most copy stays
/// readable: `"segments": ["Finished ", {"stat": "climbRankWithTotal"}]`.
struct ShareCardTextSegment: Codable, Equatable, Sendable {
    var literal: String?
    /// Nil when the template names a stat this binary does not know — the segment
    /// then behaves exactly like an unresolvable stat.
    var stat: ShareStatRef?
    var facet: ShareCardStatFacet
    /// Substituted when the stat does not resolve. Nil makes the whole run
    /// unresolvable, which is what triggers `fallback`.
    var placeholder: String?

    init(literal: String) {
        self.literal = literal
        self.stat = nil
        self.facet = .value
        self.placeholder = nil
    }

    init(stat: ShareStatRef?, facet: ShareCardStatFacet = .value, placeholder: String? = nil) {
        self.literal = nil
        self.stat = stat
        self.facet = facet
        self.placeholder = placeholder
    }

    private enum CodingKeys: String, CodingKey { case literal, stat, facet, placeholder }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self.init(literal: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let literal = try container.decodeIfPresent(String.self, forKey: .literal) {
            self.init(literal: literal)
            return
        }
        self.init(
            stat: try? container.decode(ShareStatRef.self, forKey: .stat),
            facet: try container.value(.facet, default: .value),
            placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder)
        )
    }

    func encode(to encoder: any Encoder) throws {
        if let literal {
            var container = encoder.singleValueContainer()
            try container.encode(literal)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stat, forKey: .stat)
        try container.encode(facet, forKey: .facet)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
    }
}

/// One stat drawn as a value with an optional label — the element that carries
/// the per-stat presentation intent this format exists to preserve.
struct ShareCardMetric: Codable, Equatable, Sendable {
    /// Nil when the template names a stat this binary does not know; the element
    /// then disappears, the same as a stat this workout has no value for.
    var stat: ShareStatRef?
    var labelPlacement: ShareCardLabelPlacement
    var labelPolicy: ShareCardLabelPolicy
    /// Template-supplied label copy, replacing the stat's own (`AVG BPM` → `AVG HR`).
    var labelOverride: String?
    var value: ShareCardTextStyle
    var label: ShareCardTextStyle
    var spacing: Double
    var alignment: ShareCardAlignment

    init(
        stat: ShareStatRef?,
        labelPlacement: ShareCardLabelPlacement = .below,
        labelPolicy: ShareCardLabelPolicy = .automatic,
        labelOverride: String? = nil,
        value: ShareCardTextStyle,
        label: ShareCardTextStyle,
        spacing: Double = 2,
        alignment: ShareCardAlignment = .center
    ) {
        self.stat = stat
        self.labelPlacement = labelPlacement
        self.labelPolicy = labelPolicy
        self.labelOverride = labelOverride
        self.value = value
        self.label = label
        self.spacing = spacing
        self.alignment = alignment
    }

    private enum CodingKeys: String, CodingKey {
        case stat, labelPlacement, labelPolicy, labelOverride, value, label, spacing, alignment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(ShareCardTextStyle.self, forKey: .value)
        self.init(
            stat: try? container.decode(ShareStatRef.self, forKey: .stat),
            labelPlacement: try container.value(.labelPlacement, default: .below),
            labelPolicy: try container.value(.labelPolicy, default: .automatic),
            labelOverride: try container.decodeIfPresent(String.self, forKey: .labelOverride),
            value: value,
            label: try container.value(.label, default: Self.defaultLabelStyle(for: value)),
            spacing: try container.value(.spacing, default: 2),
            alignment: try container.value(.alignment, default: .center)
        )
    }

    /// The category-standard supporting label: a third the value's size, tracked
    /// out, in the accent. Authoring only names a label style when it differs.
    static func defaultLabelStyle(for value: ShareCardTextStyle) -> ShareCardTextStyle {
        ShareCardTextStyle(
            role: value.role,
            size: value.size * 0.3,
            tracking: 2,
            tint: ShareCardTint(.label)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stat, forKey: .stat)
        try container.encode(labelPlacement, forKey: .labelPlacement)
        try container.encode(labelPolicy, forKey: .labelPolicy)
        try container.encodeIfPresent(labelOverride, forKey: .labelOverride)
        try container.encode(value, forKey: .value)
        try container.encode(label, forKey: .label)
        try container.encode(spacing, forKey: .spacing)
        try container.encode(alignment, forKey: .alignment)
    }
}

enum ShareCardContentMode: String, Codable, Sendable {
    case fill
    case fit
}

/// The climb's artwork, with an optional readability gradient laid over it.
///
/// The image always clips to the element's own bounds. A landscape hero reports
/// an overflowed width under `scaledToFill`, and letting that width reach the
/// layout once stretched every stat on the card off-frame — so the renderer lays
/// the image on a flexible base and overlays it rather than sizing to it.
struct ShareCardArtwork: Codable, Equatable, Sendable {
    var variant: ClimbImageVariant
    var contentMode: ShareCardContentMode
    /// Gradient laid over the image, top to bottom.
    var overlay: [ShareCardTint]
    var cornerRadius: Double?
    var border: ShareCardStroke?

    init(
        variant: ClimbImageVariant = .hero,
        contentMode: ShareCardContentMode = .fill,
        overlay: [ShareCardTint] = [],
        cornerRadius: Double? = nil,
        border: ShareCardStroke? = nil
    ) {
        self.variant = variant
        self.contentMode = contentMode
        self.overlay = overlay
        self.cornerRadius = cornerRadius
        self.border = border
    }

    private enum CodingKeys: String, CodingKey { case variant, contentMode, overlay, cornerRadius, border }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            variant: try container.value(.variant, default: .hero),
            contentMode: try container.value(.contentMode, default: .fill),
            overlay: try container.value(.overlay, default: []),
            cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius),
            border: try container.decodeIfPresent(ShareCardStroke.self, forKey: .border)
        )
    }
}

/// The split-timeline table. A typed component, not a free-form layout: its rows
/// come from recorded sensor data, so the format parameterises it rather than
/// describing every cell.
struct ShareCardSplitsTableSpec: Codable, Equatable, Sendable {
    var layout: ShareCardSplitsLayout
    /// Overall width in design units. Column widths are fractions of it.
    var width: Double
    /// Drives every font size in the table.
    var baseSize: Double
    var maxRows: Int?
    /// The table's own `SPLITS` heading, subtitle, and rule. A card that writes
    /// its own heading turns this off rather than drawing a second one.
    var showsTitle: Bool
    var showsHeader: Bool
    var textTint: ShareCardTint
    var fastTint: ShareCardTint
    var slowTint: ShareCardTint
    var trackTint: ShareCardTint

    init(
        layout: ShareCardSplitsLayout = .timeline,
        width: Double = 270,
        baseSize: Double = 26,
        maxRows: Int? = nil,
        showsTitle: Bool = true,
        showsHeader: Bool = true,
        textTint: ShareCardTint = ShareCardTint(.value),
        fastTint: ShareCardTint = ShareCardTint(.value),
        slowTint: ShareCardTint = ShareCardTint(.hex("A8A8A8")),
        trackTint: ShareCardTint = ShareCardTint(.hex("DEDEDE"))
    ) {
        self.layout = layout
        self.width = width
        self.baseSize = baseSize
        self.maxRows = maxRows
        self.showsTitle = showsTitle
        self.showsHeader = showsHeader
        self.textTint = textTint
        self.fastTint = fastTint
        self.slowTint = slowTint
        self.trackTint = trackTint
    }

    private enum CodingKeys: String, CodingKey {
        case layout, width, baseSize, maxRows, showsTitle, showsHeader, textTint, fastTint, slowTint, trackTint
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            layout: try container.value(.layout, default: .timeline),
            width: try container.value(.width, default: 270),
            baseSize: try container.value(.baseSize, default: 26),
            maxRows: try container.decodeIfPresent(Int.self, forKey: .maxRows),
            showsTitle: try container.value(.showsTitle, default: true),
            showsHeader: try container.value(.showsHeader, default: true),
            textTint: try container.value(.textTint, default: ShareCardTint(.value)),
            fastTint: try container.value(.fastTint, default: ShareCardTint(.value)),
            slowTint: try container.value(.slowTint, default: ShareCardTint(.hex("A8A8A8"))),
            trackTint: try container.value(.trackTint, default: ShareCardTint(.hex("DEDEDE")))
        )
    }
}

enum ShareCardSplitsLayout: String, Codable, Sendable {
    case timeline
    case stepQuintiles
}

/// The right-edge leaderboard tab. This is data-backed rather than authored as
/// text because a one-climber field must atomically become First Ascent.
struct ShareCardRankTabSpec: Codable, Equatable, Sendable {
    var width: Double
    var height: Double

    init(width: Double = 112, height: Double = 58) {
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.value(.width, default: 112),
            height: try container.value(.height, default: 58)
        )
    }
}

/// The percentile hero and distribution curve used only by Standing.
struct ShareCardStandingSpec: Codable, Equatable, Sendable {
    var width: Double
    /// Nil sizes the visualization to whatever it actually draws. A First Ascent
    /// has no field to plot, so the curve is dropped - and a reserved height
    /// would leave its slot behind as a black void under the hero.
    var height: Double?

    init(width: Double = 354, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.value(.width, default: 354),
            height: try container.decodeIfPresent(Double.self, forKey: .height)
        )
    }
}

/// A decorative fill bar. The fraction is authored, not derived — these bars are
/// a graphic device on the HUD card, never a claim about the data.
struct ShareCardProgress: Codable, Equatable, Sendable {
    var fraction: Double
    var track: ShareCardTint
    var fill: ShareCardTint
    var height: Double

    init(
        fraction: Double,
        track: ShareCardTint = ShareCardTint(.value, opacity: 0.12),
        fill: ShareCardTint = ShareCardTint(.label),
        height: Double = 10
    ) {
        self.fraction = fraction
        self.track = track
        self.fill = fill
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case fraction, track, fill, height }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fraction: try container.value(.fraction, default: 0),
            track: try container.value(.track, default: ShareCardTint(.value, opacity: 0.12)),
            fill: try container.value(.fill, default: ShareCardTint(.label)),
            height: try container.value(.height, default: 10)
        )
    }
}

struct ShareCardShapeElement: Codable, Equatable, Sendable {
    var shape: ShareCardShapeKind
    var fill: ShareCardFill?
    var stroke: ShareCardStroke?

    init(shape: ShareCardShapeKind, fill: ShareCardFill? = nil, stroke: ShareCardStroke? = nil) {
        self.shape = shape
        self.fill = fill
        self.stroke = stroke
    }

    private enum CodingKeys: String, CodingKey { case shape, fill, stroke }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shape: try container.value(.shape, default: .rectangle),
            fill: try container.decodeIfPresent(ShareCardFill.self, forKey: .fill),
            stroke: try container.decodeIfPresent(ShareCardStroke.self, forKey: .stroke)
        )
    }
}

/// A horizontal separator, solid or dashed.
struct ShareCardRule: Codable, Equatable, Sendable {
    var thickness: Double
    var tint: ShareCardTint
    var dash: [Double]?

    init(thickness: Double = 1, tint: ShareCardTint = ShareCardTint(.value, opacity: 0.55), dash: [Double]? = nil) {
        self.thickness = thickness
        self.tint = tint
        self.dash = dash
    }

    private enum CodingKeys: String, CodingKey { case thickness, tint, dash }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            thickness: try container.value(.thickness, default: 1),
            tint: try container.value(.tint, default: ShareCardTint(.value, opacity: 0.55)),
            dash: try container.decodeIfPresent([Double].self, forKey: .dash)
        )
    }
}

struct ShareCardWordmark: Codable, Equatable, Sendable {
    var size: Double
    var tint: ShareCardTint

    init(size: Double = 14, tint: ShareCardTint = ShareCardTint(.value)) {
        self.size = size
        self.tint = tint
    }

    private enum CodingKeys: String, CodingKey { case size, tint }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            size: try container.value(.size, default: 14),
            tint: try container.value(.tint, default: ShareCardTint(.value))
        )
    }
}
