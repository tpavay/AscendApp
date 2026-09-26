import CoreGraphics

/// Where the `BEST` marker may draw inside a row that also carries content -
/// a rank, an avatar, a name, a step count.
///
/// The marker's position is the previous best's, so it lands wherever that best
/// had reached, and on an open Just Climb that is usually the middle of the
/// climber's own name. Production drew it there on 2026-09-26, the line and the
/// word straight through "Tyler Pava|y". The rule is that nothing of the marker
/// ever draws over content:
///
/// - the line passes *behind* each piece of content, with `clearance` held
///   around it, so it reads as one line interrupted by the name rather than a
///   stroke through it;
/// - the word is drawn only where its whole frame, held `labelClearance` from
///   every piece of content, stays inside the row. Anywhere else it is withheld,
///   which generalises the fade the captain chose for the trailing step count.
///
/// Pure geometry, so the rule is testable without a view tree.
struct LiveReplayPreviousBestMarkerLayout: Equatable {
    enum LabelPlacement {
        /// Centred on the line's height - the vertical word on the summit bar.
        case centered
        /// Along the top of the line, in a row's top margin.
        case top
    }

    /// The line's horizontal centre, at the previous best's position.
    let lineCenterX: CGFloat
    /// The line's visible spans, top to bottom, in the host's coordinate space.
    let lineSegments: [ClosedRange<CGFloat>]
    /// Where the word sits, whether or not it is shown.
    let labelFrame: CGRect
    let showsLabel: Bool

    static let clearance: CGFloat = 4
    /// Tighter than the line's, so the flag still fits above an avatar that
    /// fills most of the row's height.
    static let labelClearance: CGFloat = 2
    static let labelTopInset: CGFloat = 3
    /// Gap between the line and the word to its right.
    static let labelSpacing: CGFloat = 3
    /// A line piece shorter than this reads as a speck, not part of a line.
    static let minimumSegmentLength: CGFloat = 2

    init(
        size: CGSize,
        progress: Double,
        lineWidth: CGFloat,
        labelSize: CGSize,
        labelPlacement: LabelPlacement,
        obstacles: [CGRect] = [],
        trailingInset: CGFloat = 0
    ) {
        let width = max(size.width, 1)
        lineCenterX = max(width * min(max(progress, 0), 1), lineWidth / 2)
        let lineMinX = lineCenterX - lineWidth / 2
        let lineMaxX = lineCenterX + lineWidth / 2
        let content = obstacles.filter { !$0.isEmpty }

        lineSegments = Self.segments(
            of: 0...max(size.height, 0),
            removing: content
                .map { $0.insetBy(dx: -Self.clearance, dy: -Self.clearance) }
                .filter { $0.minX < lineMaxX && $0.maxX > lineMinX }
                .map { $0.minY...$0.maxY }
        )

        let labelFrame = CGRect(
            x: lineMaxX + Self.labelSpacing,
            y: labelPlacement == .top ? Self.labelTopInset : (size.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        self.labelFrame = labelFrame
        showsLabel = labelFrame.maxX <= width - trailingInset
            && !content.contains {
                $0.insetBy(dx: -Self.labelClearance, dy: -Self.labelClearance).intersects(labelFrame)
            }
    }

    /// `range` with every one of `holes` cut out of it.
    private static func segments(
        of range: ClosedRange<CGFloat>,
        removing holes: [ClosedRange<CGFloat>]
    ) -> [ClosedRange<CGFloat>] {
        var segments = [range]
        for hole in holes {
            segments = segments.flatMap { segment -> [ClosedRange<CGFloat>] in
                guard hole.upperBound > segment.lowerBound,
                      hole.lowerBound < segment.upperBound else {
                    return [segment]
                }

                var pieces: [ClosedRange<CGFloat>] = []
                if hole.lowerBound > segment.lowerBound {
                    pieces.append(segment.lowerBound...hole.lowerBound)
                }
                if hole.upperBound < segment.upperBound {
                    pieces.append(hole.upperBound...segment.upperBound)
                }
                return pieces
            }
        }

        return segments.filter { $0.upperBound - $0.lowerBound >= minimumSegmentLength }
    }
}
