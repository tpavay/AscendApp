import SwiftUI

/// One stat as a card draws it: the figure over what it measures.
struct PresetStatColumn: Identifiable, Equatable {
    let id: String
    let value: String
    let label: String
}

/// A row of value-over-label stats, shared by the Classic, Rank and Centered cards. Every value
/// stays on one line however long it runs (`PresetStatColumns` gives the widths), so a time of
/// 100:00:00 or a rank of 806 of 1,234,567 shrinks a little instead of dropping a digit to a
/// second line.
struct PresetStatRow: View {
    let model: PresetCardModel
    var columns: [PresetStatColumn]? = nil
    var centered = false
    /// The hairline above the row and the space under it. The Centered card sets its own.
    var ruled = true
    var valueSize: CGFloat = 16
    var labelSize: CGFloat = 9

    var body: some View {
        let palette = model.palette
        let shown = columns ?? model.stats.map { PresetStatColumn(id: $0.id.rawValue, value: $0.value, label: $0.label) }
        PresetStatColumns(centered: centered) {
            ForEach(shown) { column in
                Text(column.value)
                    .presetText(model.font, size: valueSize, weight: 800, color: Color(share: palette.foreground))
                    .presetOneLine()
                Text(column.label)
                    .presetText(model.font, size: labelSize, weight: 700, trackingEm: 0.12, color: Color(share: palette.secondary))
                    // The label may scale as far as a value: the row has already decided how much
                    // each gets, and a label cut to an ellipsis would lose the pool it names.
                    .presetOneLine()
            }
        }
        .padding(.top, ruled ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .overlay(alignment: .top) {
            if ruled {
                Rectangle()
                    .fill(Color(share: palette.rule))
                    .frame(height: 1)
            }
        }
    }
}
