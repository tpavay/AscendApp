import Foundation

/// The backgrounds that need no photograph: flat colour or a pattern built from the accent.
enum PresetFlatBackground: String, CaseIterable, Codable, Identifiable, Sendable {
    case black
    case white
    case accent
    case glow
    case fade
    case aurora
    case grain
    case hex
    case stairs
    case grid
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .white: return "White"
        case .accent: return "Accent"
        case .glow: return "Glow"
        case .fade: return "Fade"
        case .aurora: return "Aurora"
        case .grain: return "Grain"
        case .hex: return "Hex"
        case .stairs: return "Stairs"
        case .grid: return "Grid"
        case .dots: return "Dots"
        }
    }

    /// Text on this background is dark (the card is light, or the accent fills it).
    var isLight: Bool {
        self == .white || self == .accent
    }

    /// The top row sits on bright accent, so it switches to dark text.
    var topRowIsDark: Bool {
        self == .fade
    }
}
