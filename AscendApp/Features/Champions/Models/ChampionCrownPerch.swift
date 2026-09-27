import CoreGraphics

/// Where a champion's crown sits on a picture of a given size.
///
/// The crown is perched at the top right and tilted. Pictures 56pt and larger wear the
/// full perch; smaller pictures, which sit in rows, wear a compact perch at half the
/// picture's width that stays inside a row's padding. Coordinates are in the picture's
/// own space, origin at its top-left corner, so the crown may extend past its bounds.
struct ChampionCrownPerch: Equatable, Sendable {
    /// The picture size from which the full perch is used.
    static let fullPerchMinimumSize: CGFloat = 56

    /// The shipped crown art's aspect ratio (512 x 341).
    static let crownAspectRatio: CGFloat = 341 / 512

    let avatarSize: CGFloat

    var isFull: Bool {
        avatarSize >= Self.fullPerchMinimumSize
    }

    var crownWidth: CGFloat {
        avatarSize * (isFull ? 0.58 : 0.5)
    }

    var crownHeight: CGFloat {
        crownWidth * Self.crownAspectRatio
    }

    /// How far the crown's right edge reaches past the picture's right edge.
    private var rightOverhang: CGFloat {
        avatarSize * (isFull ? 0.17 : 0.12)
    }

    /// How far the crown's top edge rises above the picture's top edge.
    private var topRise: CGFloat {
        avatarSize * (isFull ? 0.31 : 0.2)
    }

    var rotationDegrees: Double {
        isFull ? 22 : 20
    }

    var crownCenter: CGPoint {
        CGPoint(
            x: avatarSize + rightOverhang - crownWidth / 2,
            y: -topRise + crownHeight / 2
        )
    }

    /// Dots for the other titles a climber holds, stacked under the crown on large
    /// pictures only - at row size they would be specks.
    var showsTitleDots: Bool {
        isFull
    }

    static let titleDotDiameter: CGFloat = 8
    static let titleDotSpacing: CGFloat = 3

    /// The centre of the first title dot; further dots stack below it.
    var firstTitleDotCenter: CGPoint {
        CGPoint(x: avatarSize * 0.95, y: avatarSize * 0.2 + Self.titleDotDiameter / 2)
    }
}
