import Foundation

/// What a climber has chosen for their cards, remembered across sessions and applied to every
/// preset. A chosen photo and the landmark background are climb-specific and are never stored.
struct PresetPreferences: Codable, Equatable, Sendable {
    var layout: PresetLayout
    var background: PresetFlatBackground
    var font: PresetFont
    var accent: PresetAccent
    /// The seasonal background last chosen, if any. It is only used while its window is live; after
    /// that the card falls back to `background`.
    var seasonal: SeasonalBackground?
    /// A stat's presence means on; absence means off.
    var stats: Set<PresetStat>

    static let defaults = PresetPreferences(
        layout: .classic,
        background: .black,
        font: .bold,
        accent: .lime,
        seasonal: nil,
        stats: [.time, .stepsPerMinute, .rank, .bestEfforts]
    )

    func isOn(_ stat: PresetStat) -> Bool {
        stats.contains(stat)
    }

    mutating func toggle(_ stat: PresetStat) {
        if stats.contains(stat) {
            stats.remove(stat)
        } else {
            stats.insert(stat)
        }
    }

    /// Reads whatever a previous build wrote, falling back field by field so one unrecognised
    /// value never discards the rest of the climber's choices.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaults
        layout = (try? container.decode(PresetLayout.self, forKey: .layout)) ?? fallback.layout
        background = (try? container.decode(PresetFlatBackground.self, forKey: .background)) ?? fallback.background
        font = (try? container.decode(PresetFont.self, forKey: .font)) ?? fallback.font
        accent = (try? container.decode(PresetAccent.self, forKey: .accent)) ?? fallback.accent
        seasonal = try? container.decodeIfPresent(SeasonalBackground.self, forKey: .seasonal)
        if let raw = try? container.decode([String].self, forKey: .stats) {
            stats = Set(raw.compactMap(PresetStat.init(rawValue:)))
        } else {
            stats = fallback.stats
        }
    }

    init(layout: PresetLayout, background: PresetFlatBackground, font: PresetFont, accent: PresetAccent, seasonal: SeasonalBackground? = nil, stats: Set<PresetStat>) {
        self.layout = layout
        self.background = background
        self.font = font
        self.accent = accent
        self.seasonal = seasonal
        self.stats = stats
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(layout, forKey: .layout)
        try container.encode(background, forKey: .background)
        try container.encode(font, forKey: .font)
        try container.encode(accent, forKey: .accent)
        try container.encodeIfPresent(seasonal, forKey: .seasonal)
        try container.encode(stats.map(\.rawValue).sorted(), forKey: .stats)
    }

    private enum CodingKeys: String, CodingKey {
        case layout, background, font, accent, seasonal, stats
    }
}
