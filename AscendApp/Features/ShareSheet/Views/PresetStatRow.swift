import SwiftUI

/// A hairline above a row of value-over-label stats, shared by the Classic, Rank and Centered cards.
struct PresetStatRow: View {
    let model: PresetCardModel
    var items: [PresetCardStatItem]? = nil
    var centered = false

    var body: some View {
        let palette = model.palette
        let shown = items ?? model.stats
        HStack(alignment: .top, spacing: 22) {
            ForEach(shown) { item in
                VStack(alignment: centered ? .center : .leading, spacing: 0) {
                    Text(item.value)
                        .presetText(model.font, size: 16, weight: 800, color: Color(share: palette.foreground))
                    Text(item.label)
                        .presetText(model.font, size: 9, weight: 700, trackingEm: 0.12, color: Color(share: palette.secondary))
                }
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(share: palette.rule))
                .frame(height: 1)
        }
    }
}
