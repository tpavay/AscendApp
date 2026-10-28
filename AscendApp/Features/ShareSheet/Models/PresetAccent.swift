import Foundation

/// The colour a preset's accents and patterns are built from.
enum PresetAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case lime
    case white
    case coral
    case sky
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime: return "Lime"
        case .white: return "White"
        case .coral: return "Coral"
        case .sky: return "Sky"
        case .orange: return "Orange"
        }
    }

    var hex: UInt32 {
        switch self {
        case .lime: return 0x86D30A
        case .white: return 0xFFFFFF
        case .coral: return 0xFB7185
        case .sky: return 0x7DD3FC
        case .orange: return 0xFDBA74
        }
    }

    /// The accent as text on a light background, where the bright value would wash out.
    var onLightHex: UInt32 {
        switch self {
        case .lime: return 0x4D7C0F
        case .white: return 0x0B0B0B
        case .coral: return 0xBE123C
        case .sky: return 0x0369A1
        case .orange: return 0xC2410C
        }
    }
}
