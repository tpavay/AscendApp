import CoreGraphics

/// The numbers and rules behind the Presets card swipe, pure so a test can pin each one. The
/// captain's handoff (`SWIPE_SPEC.md`) is the source of every value here.
enum PresetPagerGeometry {
    /// Cards are `PresetCardView.designSize` (310) points square with a 16 point gap, so pages sit 326
    /// points apart; a test pins the sum, because a view's constants cannot be read from here.
    static let step: CGFloat = 326
    /// At the first or last card the card still follows the finger, at this share of the distance.
    static let edgeResistance: CGFloat = 0.45
    /// A release past this distance pages.
    static let distanceThreshold: CGFloat = 60
    /// A release faster than this, in points a second, pages.
    static let velocityThreshold: CGFloat = 350
    /// How far a card's contents slide against the card, per card of distance from the centre.
    static let parallax: CGFloat = 24
    static let neighbourScale: CGFloat = 0.10
    static let neighbourFade: CGFloat = 0.55
    /// Pill and dot widths for the active and inactive page marks.
    static let pillWidth: CGFloat = 18
    static let dotWidth: CGFloat = 6

    /// Where the row sits for a drag of `translation`: one for one, except pulling past an end,
    /// where it resists.
    static func trackedOffset(translation: CGFloat, index: Int, count: Int) -> CGFloat {
        let pullsPastStart = index == 0 && translation > 0
        let pullsPastEnd = index == count - 1 && translation < 0
        return pullsPastStart || pullsPastEnd ? translation * edgeResistance : translation
    }

    /// The page a release lands on. It never moves more than one card, and a drag one way with a
    /// flick the other is a hesitation, so it stays.
    static func destination(index: Int, count: Int, translation: CGFloat, velocity: CGFloat) -> Int {
        let forward = translation < -distanceThreshold || velocity < -velocityThreshold
        let backward = translation > distanceThreshold || velocity > velocityThreshold
        guard forward != backward else { return index }
        return min(max(index + (forward ? 1 : -1), 0), max(count - 1, 0))
    }

    /// How many cards a card is from the centre: 0 on it, 1 a page away, negative to its left.
    static func signedDistance(page: Int, index: Int, offset: CGFloat) -> CGFloat {
        CGFloat(page - index) + offset / step
    }

    /// Scale, opacity and shadow strength for a card `signedDistance` from the centre, so depth
    /// follows the finger instead of waiting for the release.
    static func depth(signedDistance: CGFloat) -> (scale: CGFloat, opacity: CGFloat, shadow: CGFloat) {
        let distance = min(1, abs(signedDistance))
        return (1 - neighbourScale * distance, 1 - neighbourFade * distance, 1 - distance)
    }

    /// The fractional page the row is showing: 2.5 is halfway from the third card to the fourth.
    static func position(index: Int, offset: CGFloat) -> CGFloat {
        CGFloat(index) - offset / step
    }

    /// A page mark's width: the pill at the centre, a dot one page away, blended between.
    static func markWidth(page: Int, position: CGFloat) -> CGFloat {
        let distance = min(1, abs(position - CGFloat(page)))
        return dotWidth + (pillWidth - dotWidth) * (1 - distance)
    }

    /// The page a caption belongs to while the row is at `position`.
    static func activePage(position: CGFloat, count: Int) -> Int {
        min(max(Int(position.rounded()), 0), max(count - 1, 0))
    }

    /// The pages worth drawing: the centre, its neighbours, and the pair beyond them, which sit
    /// off screen so a card is already in place when a page change slides it into view.
    static func window(index: Int, count: Int) -> ClosedRange<Int> {
        max(index - 2, 0)...min(index + 2, max(count - 1, 0))
    }
}
