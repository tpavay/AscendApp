import SwiftUI

/// What a climber's picture shows when there is no photo, or while it loads.
///
/// Most climbers have no photo, so this is the picture most people see. Each surface keeps
/// its own look; the palette colour comes from the climber's uid, so the same climber
/// wears the same colour on every launch and on every surface using that palette.
enum ClimberAvatarPlaceholder: Equatable {
    /// Initials on a filled circle. An empty token falls back to the generic glyph.
    case initials(String, fill: Color, foreground: Color, fontSize: CGFloat? = nil)
    /// An SF Symbol on a filled circle.
    case glyph(systemName: String, fill: Color, foreground: Color, glyphSize: CGFloat? = nil)
    /// The profile's own default: the lime person on a faint disc.
    case profileDefault

    /// Initials for a resolved identity, falling back to the generic glyph for a hidden or
    /// anonymous climber whose token is empty.
    static func initials(
        for identity: ResolvedUserIdentity,
        fill: Color,
        foreground: Color = .white,
        fontSize: CGFloat? = nil
    ) -> ClimberAvatarPlaceholder {
        .initials(identity.avatarToken, fill: fill, foreground: foreground, fontSize: fontSize)
    }
}

/// The palettes the boards draw initials on, picked by uid.
enum ClimberAvatarPalette {
    /// Climb Detail's ALL TIMES board, the finisher strip and routine completion boards.
    static let vivid: [Color] = [
        Color(red: 0.94, green: 0.33, blue: 0.43),
        Color(red: 0.21, green: 0.72, blue: 0.69),
        Color(red: 1.0, green: 0.57, blue: 0.08),
        Color(red: 0.40, green: 0.34, blue: 0.86)
    ]

    /// The live race board, which sits over the climb's photograph.
    static let earth: [Color] = [
        Color(hex: "8C5A36"),
        Color(hex: "C69475"),
        Color(hex: "6E4E33"),
        Color(hex: "A36A42")
    ]

    /// Keys on the climber, never on a row or an attempt, so one climber is one colour.
    static func color(in palette: [Color], for key: String) -> Color {
        palette[StableAvatarPalette.index(for: key, count: palette.count)]
    }
}
