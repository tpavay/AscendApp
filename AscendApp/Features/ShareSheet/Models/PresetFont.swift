import Foundation

/// The card's typeface. Every one is bundled; Bold is the default.
enum PresetFont: String, CaseIterable, Codable, Identifiable, Sendable {
    case bold
    case condensed
    case mono
    case serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .condensed: return "Condensed"
        case .mono: return "Mono"
        case .serif: return "Serif"
        }
    }

    /// PostScript names of the bundled files, heaviest first. The serif has a single weight.
    var postScriptName: String {
        switch self {
        case .bold: return "Montserrat-Black"
        case .condensed: return "BarlowCondensed-ExtraBold"
        case .mono: return "JetBrainsMono-ExtraBold"
        case .serif: return "InstrumentSerif-Regular"
        }
    }

    /// The bundled face for a CSS-style weight (900, 800, 700, 600). Montserrat has a file per
    /// weight; the other three faces are a single weight, as in the approved design.
    func postScriptName(weight: Int) -> String {
        switch self {
        case .bold:
            if weight >= 900 { return "Montserrat-Black" }
            if weight >= 800 { return "Montserrat-ExtraBold" }
            if weight >= 700 { return "Montserrat-Bold" }
            return "Montserrat-SemiBold"
        case .condensed, .mono, .serif:
            return postScriptName
        }
    }

    /// The Mono face tightens its tracking so a number keeps the card's rhythm.
    var tracking: Double {
        self == .mono ? -0.02 : 0
    }
}
