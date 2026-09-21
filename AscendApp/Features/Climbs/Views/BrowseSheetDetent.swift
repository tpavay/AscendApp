import SwiftUI

/// The three resting heights of the sheet over the globe.
///
/// `compact` is one line and a grabber, `medium` a reading height, `expanded` the whole
/// screen. Heights are functions of the container, so the same enum serves the Browse
/// sheet and Home's sheet.
enum BrowseSheetDetent: Int, CaseIterable, Comparable {
    case compact
    case medium
    case expanded

    func height(
        containerHeight: CGFloat,
        topCoverageInset: CGFloat = 0,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let expandedHeight = max(320, containerHeight + topCoverageInset)

        switch self {
        case .compact:
            return min(expandedHeight, 86 + bottomInset)
        case .medium:
            return min(expandedHeight, max(286 + bottomInset, containerHeight * 0.36))
        case .expanded:
            return expandedHeight
        }
    }

    func offset(
        containerHeight: CGFloat,
        topCoverageInset: CGFloat = 0,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        BrowseSheetDetent.expanded.height(
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset
        ) - height(
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func clampedOffset(
        _ offset: CGFloat,
        containerHeight: CGFloat,
        topCoverageInset: CGFloat = 0,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        min(
            max(
                offset,
                BrowseSheetDetent.expanded.offset(
                    containerHeight: containerHeight,
                    topCoverageInset: topCoverageInset,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            ),
            BrowseSheetDetent.compact.offset(
                containerHeight: containerHeight,
                topCoverageInset: topCoverageInset,
                topInset: topInset,
                bottomInset: bottomInset
            )
        )
    }

    static func nearest(
        to offset: CGFloat,
        among detents: [BrowseSheetDetent] = [.medium, .expanded],
        containerHeight: CGFloat,
        topCoverageInset: CGFloat = 0,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> BrowseSheetDetent {
        detents.min { lhs, rhs in
            abs(
                lhs.offset(
                    containerHeight: containerHeight,
                    topCoverageInset: topCoverageInset,
                    topInset: topInset,
                    bottomInset: bottomInset
                ) - offset
            )
            < abs(
                rhs.offset(
                    containerHeight: containerHeight,
                    topCoverageInset: topCoverageInset,
                    topInset: topInset,
                    bottomInset: bottomInset
                ) - offset
            )
        } ?? .medium
    }

    /// The next resting height up from this one among `detents`, or the highest.
    func nextUp(in detents: [BrowseSheetDetent]) -> BrowseSheetDetent {
        detents.filter { $0 > self }.min() ?? detents.max() ?? .expanded
    }

    /// The next resting height down from this one among `detents`, or the lowest.
    func nextDown(in detents: [BrowseSheetDetent]) -> BrowseSheetDetent {
        detents.filter { $0 < self }.max() ?? detents.min() ?? .medium
    }

    static func < (lhs: BrowseSheetDetent, rhs: BrowseSheetDetent) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
