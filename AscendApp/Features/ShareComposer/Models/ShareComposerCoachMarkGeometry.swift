import CoreGraphics

enum ShareComposerCoachMarkGeometry {
    /// The stats sheet can scroll far beyond its detent. Spotlight the visible lower section
    /// where the tappable groups and stats live, never the off-screen content bounds.
    static func statsSpotlightRect(for contentRect: CGRect, in containerSize: CGSize) -> CGRect? {
        let container = CGRect(origin: .zero, size: containerSize)
        let visible = contentRect.intersection(container)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }

        let horizontalInset: CGFloat = min(8, visible.width / 4)
        let height = min(150, visible.height)
        var spotlight = CGRect(
            x: visible.minX + horizontalInset,
            y: visible.maxY - height,
            width: visible.width - horizontalInset * 2,
            height: height
        )
        let ringExpansionAndHalfStroke: CGFloat = 5
        spotlight.origin.y = min(
            spotlight.origin.y,
            container.maxY - ringExpansionAndHalfStroke - spotlight.height
        )
        spotlight.origin.y = max(
            container.minY + ringExpansionAndHalfStroke,
            spotlight.origin.y
        )
        return spotlight
    }
}
