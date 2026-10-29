import SwiftUI

/// A row of stats, each a value over a label, that never lets a value wrap. The children come in
/// pairs, a value then its label. `PresetFitGeometry.columns` decides the widths from what each
/// part measures; every part is expected to carry `presetOneLine`, so a part given less than its
/// full width scales or truncates itself rather than breaking onto a second line.
struct PresetStatColumns: Layout {
    var gap: CGFloat = 22
    /// Whether the row, and each value and label inside its column, is centred rather than leading.
    var centered = false

    private struct Measured {
        var columns: PresetFitGeometry.Columns
        var valueHeights: [CGFloat]
        var labelHeights: [CGFloat]
        var used: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(proposal: proposal, subviews: subviews)
        let height = zip(measured.valueHeights, measured.labelHeights).map { $0 + $1 }.max() ?? 0
        return CGSize(width: proposal.width ?? measured.used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var x = centered ? bounds.minX + (bounds.width - measured.used) / 2 : bounds.minX
        for column in measured.columns.widths.indices {
            let width = measured.columns.widths[column]
            let proposal = ProposedViewSize(width: width, height: nil)
            let value = subviews[column * 2]
            let label = subviews[column * 2 + 1]
            for (subview, y) in [(value, bounds.minY), (label, bounds.minY + measured.valueHeights[column])] {
                let size = subview.sizeThatFits(proposal)
                let inset = centered ? (width - size.width) / 2 : 0
                subview.place(at: CGPoint(x: x + inset, y: y), anchor: .topLeading, proposal: proposal)
            }
            x += width + measured.columns.gap
        }
    }

    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> Measured {
        let count = subviews.count / 2
        let values = (0..<count).map { subviews[$0 * 2].sizeThatFits(.unspecified).width }
        let labels = (0..<count).map { subviews[$0 * 2 + 1].sizeThatFits(.unspecified).width }
        let natural = values.indices.map { max(values[$0], labels[$0]) }.reduce(0, +) + gap * CGFloat(max(count - 1, 0))
        let columns = PresetFitGeometry.columns(
            values: values,
            labels: labels,
            available: proposal.width ?? natural,
            gap: gap
        )
        let widths = columns.widths
        return Measured(
            columns: columns,
            valueHeights: (0..<count).map {
                subviews[$0 * 2].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height
            },
            labelHeights: (0..<count).map {
                subviews[$0 * 2 + 1].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height
            },
            used: widths.reduce(0, +) + columns.gap * CGFloat(max(count - 1, 0))
        )
    }
}
