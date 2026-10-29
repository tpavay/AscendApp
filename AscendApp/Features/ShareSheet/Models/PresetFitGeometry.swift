import CoreGraphics

/// How a Presets card's numbers share a line, decided from measured widths alone.
///
/// A card is drawn at one fixed type size and exported as an image, so nothing on it may wrap or
/// end in an ellipsis however long a climb or a field gets: 24:00:00, thousands of floors, a
/// seven digit pool. These rules say what gives way, and in what order: the gaps close first, then
/// labels shrink or truncate, and only then do the numbers themselves scale down together.
enum PresetFitGeometry {
    /// The least space left between two stat columns before anything else gives way.
    static let minimumGap: CGFloat = 8
    /// The smallest a stat value, or a hero number, may scale to before it would be cut off.
    static let valueFloor: CGFloat = 0.3
    /// The smallest a label or caption may scale to before it truncates.
    static let labelFloor: CGFloat = 0.6

    struct Columns: Equatable {
        var widths: [CGFloat]
        var gap: CGFloat
    }

    /// Widths for a row of stat columns, each a value over a label.
    ///
    /// While everything fits, a column is as wide as its wider part and the gap is the design's.
    /// When it does not, the gap closes toward `minimumGap`; then the labels give up width, down to
    /// `labelFloor` of their size but never below their value; and only if that is still too wide
    /// does the whole row scale, every column by the same factor so none is the odd one out.
    static func columns(values: [CGFloat], labels: [CGFloat], available: CGFloat, gap: CGFloat) -> Columns {
        precondition(values.count == labels.count, "every stat has one value and one label")
        guard !values.isEmpty else { return Columns(widths: [], gap: gap) }
        let gaps = CGFloat(values.count - 1)
        let ideals = zip(values, labels).map { max($0, $1) }
        let idealSum = ideals.reduce(0, +)
        if idealSum + gap * gaps <= available {
            return Columns(widths: ideals, gap: gap)
        }
        let room = max(available - minimumGap * gaps, 0)
        if idealSum <= room {
            let left = gaps > 0 ? (available - idealSum) / gaps : 0
            return Columns(widths: ideals, gap: min(max(left, minimumGap), gap))
        }
        let smallest = zip(values, labels).map { max($0, $1 * labelFloor) }
        let smallestSum = smallest.reduce(0, +)
        if smallestSum <= room {
            let wants = zip(ideals, smallest).map { $0 - $1 }
            let wanted = wants.reduce(0, +)
            let share = wanted > 0 ? min(1, (room - smallestSum) / wanted) : 0
            return Columns(widths: zip(smallest, wants).map { $0 + $1 * share }, gap: minimumGap)
        }
        let factor = smallestSum > 0 ? room / smallestSum : 0
        return Columns(widths: smallest.map { $0 * factor }, gap: minimumGap)
    }

    enum Placement: Equatable {
        /// The two sit on one line, the first given at most `primaryWidth`.
        case beside(primaryWidth: CGFloat)
        /// The second drops to its own line under the first.
        case below
    }

    /// A big number with its caption: beside it while the number can stay at or above `floor` of
    /// its size, under it once it could not. The number scales before the caption moves, because a
    /// card should keep its design when a number is merely a digit longer.
    static func placement(
        primary: CGFloat,
        secondary: CGFloat,
        available: CGFloat,
        gap: CGFloat,
        floor: CGFloat
    ) -> Placement {
        let room = available - gap - secondary
        if primary <= room { return .beside(primaryWidth: primary) }
        if room >= primary * floor { return .beside(primaryWidth: room) }
        return .below
    }
}
