import Foundation

/// Styling primitives for the declarative share-card format.
///
/// Deliberately SwiftUI-free: these are the values a template author writes in
/// JSON. `ShareCardStyleResolvers` turns them into `Font`/`Color`/`Shape` at
/// render time, so the format stays testable without a view tree.
///
/// Every type here decodes leniently — an omitted key takes its default and an
/// unknown string decodes to a documented fallback rather than throwing. A
/// template must never be able to fail a user's share.

// MARK: - Decoding helper

extension KeyedDecodingContainer {
    /// Decodes `key` when present, otherwise returns `fallback`. Keeps authored
    /// JSON terse: only the values that differ from the default appear.
    func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

// MARK: - Geometry

enum ShareCardAxis: String, Codable, Sendable {
    case horizontal
    case vertical
    /// Layered (`ZStack`).
    case depth
}

enum ShareCardAlignment: String, Codable, Sendable {
    case leading
    case center
    case trailing
    case top
    case bottom
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    /// Only meaningful as a horizontal stack's cross-axis alignment.
    case firstTextBaseline
}

enum ShareCardUnitPoint: String, Codable, Sendable {
    case top
    case bottom
    case leading
    case trailing
    case center
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// A frame dimension. `infinity` is the JSON spelling of `.infinity`.
enum ShareCardDimension: Codable, Equatable, Sendable {
    case points(Double)
    case infinity

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .points(number)
            return
        }
        let text = try container.decode(String.self)
        self = text == "infinity" ? .infinity : .points(Double(text) ?? 0)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .points(let value): try container.encode(value)
        case .infinity: try container.encode("infinity")
        }
    }
}

struct ShareCardFrame: Codable, Equatable, Sendable {
    var width: Double?
    var height: Double?
    var maxWidth: ShareCardDimension?
    var maxHeight: ShareCardDimension?
    var alignment: ShareCardAlignment?
}

/// Padding. Authored as a number (all edges), or an object that may use the
/// `all` / `horizontal` / `vertical` shorthands alongside single edges.
struct ShareCardEdgeInsets: Codable, Equatable, Sendable {
    var top: Double
    var leading: Double
    var bottom: Double
    var trailing: Double

    init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    private enum CodingKeys: String, CodingKey {
        case all, horizontal, vertical, top, leading, bottom, trailing
    }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let all = try? single.decode(Double.self) {
            self.init(top: all, leading: all, bottom: all, trailing: all)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let all = try container.decodeIfPresent(Double.self, forKey: .all) ?? 0
        let horizontal = try container.decodeIfPresent(Double.self, forKey: .horizontal) ?? all
        let vertical = try container.decodeIfPresent(Double.self, forKey: .vertical) ?? all
        self.init(
            top: try container.decodeIfPresent(Double.self, forKey: .top) ?? vertical,
            leading: try container.decodeIfPresent(Double.self, forKey: .leading) ?? horizontal,
            bottom: try container.decodeIfPresent(Double.self, forKey: .bottom) ?? vertical,
            trailing: try container.decodeIfPresent(Double.self, forKey: .trailing) ?? horizontal
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(top, forKey: .top)
        try container.encode(leading, forKey: .leading)
        try container.encode(bottom, forKey: .bottom)
        try container.encode(trailing, forKey: .trailing)
    }
}

// MARK: - Color

/// A color slot. `value` and `label` resolve against the render context, so one
/// template renders correctly whether the context is a card (white on lime) or a
/// sticker the user has recolored.
enum ShareCardColor: Codable, Equatable, Sendable {
    /// The context's value color — white on a template, the user's pick on a sticker.
    case value
    /// The context's label color — the lime accent, or the user's pick when custom.
    case label
    /// A literal `RRGGBB` hex, for template-specific palettes (bib cream, medal gold).
    case hex(String)

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        switch text {
        case "value": self = .value
        case "label": self = .label
        default: self = .hex(text.hasPrefix("#") ? String(text.dropFirst()) : text)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value: try container.encode("value")
        case .label: try container.encode("label")
        case .hex(let hex): try container.encode("#\(hex)")
        }
    }
}

/// A color plus opacity. Authored either as a bare color string (`"value"`) or
/// as `{"color": "value", "opacity": 0.13}`.
struct ShareCardTint: Codable, Equatable, Sendable {
    var color: ShareCardColor
    var opacity: Double

    init(_ color: ShareCardColor, opacity: Double = 1) {
        self.color = color
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey { case color, opacity }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let color = try? single.decode(ShareCardColor.self) {
            self.init(color)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(ShareCardColor.self, forKey: .color),
            opacity: try container.value(.opacity, default: 1)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(opacity, forKey: .opacity)
    }
}

// MARK: - Fill / stroke / shape

enum ShareCardMaterial: String, Codable, Sendable {
    case ultraThin
    case thin
    case regular
}

enum ShareCardFill: Codable, Equatable, Sendable {
    case color(ShareCardTint)
    case linearGradient(stops: [ShareCardTint], start: ShareCardUnitPoint, end: ShareCardUnitPoint)
    case radialGradient(stops: [ShareCardTint], center: ShareCardUnitPoint, startRadius: Double, endRadius: Double)
    case material(ShareCardMaterial, opacity: Double)

    private enum CodingKeys: String, CodingKey {
        case kind, tint, stops, start, end, center, startRadius, endRadius, material, opacity
    }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let tint = try? single.decode(ShareCardTint.self) {
            self = .color(tint)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.value(.kind, default: "color") {
        case "linearGradient":
            self = .linearGradient(
                stops: try container.value(.stops, default: []),
                start: try container.value(.start, default: .top),
                end: try container.value(.end, default: .bottom)
            )
        case "radialGradient":
            self = .radialGradient(
                stops: try container.value(.stops, default: []),
                center: try container.value(.center, default: .center),
                startRadius: try container.value(.startRadius, default: 0),
                endRadius: try container.value(.endRadius, default: 0)
            )
        case "material":
            self = .material(
                try container.value(.material, default: .ultraThin),
                opacity: try container.value(.opacity, default: 1)
            )
        default:
            self = .color(try container.value(.tint, default: ShareCardTint(.value)))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let tint):
            try container.encode("color", forKey: .kind)
            try container.encode(tint, forKey: .tint)
        case .linearGradient(let stops, let start, let end):
            try container.encode("linearGradient", forKey: .kind)
            try container.encode(stops, forKey: .stops)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .radialGradient(let stops, let center, let startRadius, let endRadius):
            try container.encode("radialGradient", forKey: .kind)
            try container.encode(stops, forKey: .stops)
            try container.encode(center, forKey: .center)
            try container.encode(startRadius, forKey: .startRadius)
            try container.encode(endRadius, forKey: .endRadius)
        case .material(let material, let opacity):
            try container.encode("material", forKey: .kind)
            try container.encode(material, forKey: .material)
            try container.encode(opacity, forKey: .opacity)
        }
    }
}

struct ShareCardStroke: Codable, Equatable, Sendable {
    var tint: ShareCardTint
    var width: Double
    /// Dash pattern in design units. Nil draws a solid line.
    var dash: [Double]?

    init(tint: ShareCardTint, width: Double = 1, dash: [Double]? = nil) {
        self.tint = tint
        self.width = width
        self.dash = dash
    }

    private enum CodingKeys: String, CodingKey { case tint, width, dash }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tint: try container.value(.tint, default: ShareCardTint(.value)),
            width: try container.value(.width, default: 1),
            dash: try container.decodeIfPresent([Double].self, forKey: .dash)
        )
    }
}

enum ShareCardShapeKind: Codable, Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case capsule
    case circle

    private enum CodingKeys: String, CodingKey { case kind, cornerRadius }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            switch text {
            case "capsule": self = .capsule
            case "circle": self = .circle
            default: self = .rectangle
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.value(.kind, default: "rectangle") {
        case "roundedRectangle":
            self = .roundedRectangle(cornerRadius: try container.value(.cornerRadius, default: 0))
        case "capsule": self = .capsule
        case "circle": self = .circle
        default: self = .rectangle
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .roundedRectangle(let radius):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("roundedRectangle", forKey: .kind)
            try container.encode(radius, forKey: .cornerRadius)
        case .rectangle, .capsule, .circle:
            var container = encoder.singleValueContainer()
            try container.encode(self == .capsule ? "capsule" : (self == .circle ? "circle" : "rectangle"))
        }
    }
}

struct ShareCardShadow: Codable, Equatable, Sendable {
    var tint: ShareCardTint
    var radius: Double
    var x: Double
    var y: Double

    init(tint: ShareCardTint, radius: Double, x: Double = 0, y: Double = 0) {
        self.tint = tint
        self.radius = radius
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey { case tint, radius, x, y }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tint: try container.value(.tint, default: ShareCardTint(.hex("000000"), opacity: 0.45)),
            radius: try container.value(.radius, default: 0),
            x: try container.value(.x, default: 0),
            y: try container.value(.y, default: 0)
        )
    }
}

// MARK: - Typography

/// Weight slot within the context's typeface. Faces that ship a single weight
/// (Anton, Playfair, Space Mono) render every role from that one file.
enum ShareCardFontRole: String, Codable, Sendable {
    case heavy
    case medium
    case regular
}

enum ShareCardTextTransform: String, Codable, Sendable {
    case none
    case uppercase
}

enum ShareCardTextAlignment: String, Codable, Sendable {
    case leading
    case center
    case trailing
}

/// How one run of text is drawn. Sizes are design units on the 390pt-wide card;
/// the whole card is scaled once at render time, never per element.
struct ShareCardTextStyle: Codable, Equatable, Sendable {
    var role: ShareCardFontRole
    var size: Double
    var tracking: Double
    var tint: ShareCardTint
    var lineLimit: Int?
    var minimumScaleFactor: Double?
    var alignment: ShareCardTextAlignment?
    var monospacedDigit: Bool

    init(
        role: ShareCardFontRole = .heavy,
        size: Double,
        tracking: Double = 0,
        tint: ShareCardTint = ShareCardTint(.value),
        lineLimit: Int? = nil,
        minimumScaleFactor: Double? = nil,
        alignment: ShareCardTextAlignment? = nil,
        monospacedDigit: Bool = false
    ) {
        self.role = role
        self.size = size
        self.tracking = tracking
        self.tint = tint
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
        self.alignment = alignment
        self.monospacedDigit = monospacedDigit
    }

    private enum CodingKeys: String, CodingKey {
        case role, size, tracking, tint, lineLimit, minimumScaleFactor, alignment, monospacedDigit
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            role: try container.value(.role, default: .heavy),
            size: try container.value(.size, default: 16),
            tracking: try container.value(.tracking, default: 0),
            tint: try container.value(.tint, default: ShareCardTint(.value)),
            lineLimit: try container.decodeIfPresent(Int.self, forKey: .lineLimit),
            minimumScaleFactor: try container.decodeIfPresent(Double.self, forKey: .minimumScaleFactor),
            alignment: try container.decodeIfPresent(ShareCardTextAlignment.self, forKey: .alignment),
            monospacedDigit: try container.value(.monospacedDigit, default: false)
        )
    }
}
