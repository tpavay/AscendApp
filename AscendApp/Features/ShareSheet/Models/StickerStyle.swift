import Foundation

/// The one Font, Color and Shadow setting every sticker shares, remembered across sessions.
struct StickerStyle: Codable, Equatable, Sendable {
    enum Font: String, CaseIterable, Codable, Identifiable, Sendable {
        case bold, condensed, mono, serif
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bold: return "Bold"
            case .condensed: return "Condensed"
            case .mono: return "Mono"
            case .serif: return "Serif"
            }
        }

        var presetFont: PresetFont {
            switch self {
            case .bold: return .bold
            case .condensed: return .condensed
            case .mono: return .mono
            case .serif: return .serif
            }
        }
    }

    enum Color: String, CaseIterable, Codable, Identifiable, Sendable {
        case white, lime, black, coral, sky
        var id: String { rawValue }

        var title: String {
            switch self {
            case .white: return "White"
            case .lime: return "Lime"
            case .black: return "Black"
            case .coral: return "Coral"
            case .sky: return "Sky"
            }
        }

        var hex: UInt32 {
            switch self {
            case .white: return 0xFFFFFF
            case .lime: return 0x86D30A
            case .black: return 0x0B0B0B
            case .coral: return 0xFB7185
            case .sky: return 0x7DD3FC
            }
        }

        /// The wordmark's A: lime on white and black stickers, white on the rest.
        var wordmarkMarkHex: UInt32 {
            switch self {
            case .white, .black: return 0x86D30A
            case .lime, .coral, .sky: return 0xFFFFFF
            }
        }
    }

    enum Shadow: String, CaseIterable, Codable, Identifiable, Sendable {
        case none, soft, hard, outline
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .soft: return "Soft"
            case .hard: return "Hard"
            case .outline: return "Outline"
            }
        }
    }

    var font: Font = .bold
    var color: Color = .white
    var shadow: Shadow = .soft

    static let defaults = StickerStyle()

    init(font: Font = .bold, color: Color = .white, shadow: Shadow = .soft) {
        self.font = font
        self.color = color
        self.shadow = shadow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        font = (try? container.decode(Font.self, forKey: .font)) ?? .bold
        color = (try? container.decode(Color.self, forKey: .color)) ?? .white
        shadow = (try? container.decode(Shadow.self, forKey: .shadow)) ?? .soft
    }

    private enum CodingKeys: String, CodingKey {
        case font, color, shadow
    }
}
