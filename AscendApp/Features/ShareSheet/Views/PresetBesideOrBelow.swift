import SwiftUI

/// A number and its caption: on one line when they fit, the caption under the number when they do
/// not. Two children, the number first. The number is expected to carry its own
/// `presetOneLine`, so it scales into whatever width it is given; the rules are in
/// `PresetFitGeometry.placement`.
struct PresetBesideOrBelow: Layout {
    var gap: CGFloat = 8
    /// The space between the two when the caption drops under the number.
    var stackedSpacing: CGFloat = 2
    /// How far the number may scale before the caption drops.
    var floor: CGFloat = 0.5
    /// What the two line up on when they share a line.
    var alignment: VerticalAlignment = .firstTextBaseline

    private struct Arrangement {
        var primary: CGRect
        var secondary: CGRect
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let found = arrangement(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + found.primary.minX, y: bounds.minY + found.primary.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(found.primary.size)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + found.secondary.minX, y: bounds.minY + found.secondary.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(found.secondary.size)
        )
    }

    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        guard subviews.count == 2 else { return Arrangement(primary: .zero, secondary: .zero, size: .zero) }
        let primaryIdeal = subviews[0].sizeThatFits(.unspecified)
        let secondaryIdeal = subviews[1].sizeThatFits(.unspecified)
        let available = proposal.width ?? (primaryIdeal.width + gap + secondaryIdeal.width)
        let placement = PresetFitGeometry.placement(
            primary: primaryIdeal.width,
            secondary: secondaryIdeal.width,
            available: available,
            gap: gap,
            floor: floor
        )
        switch placement {
        case .beside(let primaryWidth):
            let primaryProposal = ProposedViewSize(width: primaryWidth, height: nil)
            let primarySize = subviews[0].sizeThatFits(primaryProposal)
            let primaryLine = subviews[0].dimensions(in: primaryProposal)[alignment]
            let secondaryLine = subviews[1].dimensions(in: ProposedViewSize(secondaryIdeal))[alignment]
            let line = max(primaryLine, secondaryLine)
            let primaryY = line - primaryLine
            let secondaryY = line - secondaryLine
            let primaryFrame = CGRect(x: 0, y: primaryY, width: primarySize.width, height: primarySize.height)
            let secondaryFrame = CGRect(
                x: primarySize.width + gap,
                y: secondaryY,
                width: secondaryIdeal.width,
                height: secondaryIdeal.height
            )
            return Arrangement(
                primary: primaryFrame,
                secondary: secondaryFrame,
                size: CGSize(width: secondaryFrame.maxX, height: max(primaryFrame.maxY, secondaryFrame.maxY))
            )
        case .below:
            let width = max(available, 0)
            let primarySize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let secondarySize = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let primaryFrame = CGRect(origin: .zero, size: primarySize)
            let secondaryFrame = CGRect(
                x: 0,
                y: primarySize.height + stackedSpacing,
                width: secondarySize.width,
                height: secondarySize.height
            )
            return Arrangement(
                primary: primaryFrame,
                secondary: secondaryFrame,
                size: CGSize(width: max(primaryFrame.maxX, secondaryFrame.maxX), height: secondaryFrame.maxY)
            )
        }
    }
}
