import Foundation

/// What is behind a Presets card right now.
enum PresetCardBackground: Equatable, Sendable {
    case flat(PresetFlatBackground)
    /// The landmark's own hero artwork; offered on landmark climbs only.
    case tower
    /// A photograph the climber chose. Never persisted.
    case photo
    case seasonal(SeasonalBackground)

    /// A photograph or artwork sits behind the text, so it gets the bottom scrim.
    var isImage: Bool {
        switch self {
        case .tower, .photo: return true
        case .flat, .seasonal: return false
        }
    }

    var title: String {
        switch self {
        case .flat(let flat): return flat.title
        case .tower: return "Tower"
        case .photo: return "Photo"
        case .seasonal(let seasonal): return seasonal.title
        }
    }
}
