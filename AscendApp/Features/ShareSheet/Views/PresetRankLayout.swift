import SwiftUI

/// Rank: the finish position at 104 points with the field beside it, then a hairline and three
/// fixed columns. Without a rank it falls back to the Classic body rather than drawing nothing.
struct PresetRankLayout: View {
    let model: PresetCardModel

    var body: some View {
        if let rank = model.subject.rank {
            content(rank: rank)
        } else {
            PresetClassicLayout(model: model)
        }
    }

    private func content(rank: ShareSheetSubject.Rank) -> some View {
        let palette = model.palette
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(model.label)
                .presetText(model.font, size: 10, weight: 700, trackingEm: 0.2, color: Color(share: palette.secondary))
            HStack(alignment: .bottom, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("#")
                        .presetText(model.font, size: 52, weight: 900, color: Color(share: palette.accentText))
                    Text(rank.positionText)
                        .presetText(model.font, size: 104, weight: 900, trackingEm: -0.06, color: Color(share: palette.foreground))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                // Line box of 0.82em, as the design sets it, so the number sits on the hairline row.
                .frame(height: 104 * 0.82)
                .layoutPriority(1)
                Text("of \(rank.fieldText)")
                    .presetText(model.font, size: 20, weight: 800, color: Color(share: palette.foreground))
                    .lineLimit(1)
                    .frame(height: 20)
                    .padding(.bottom, 6)
            }
            .padding(.top, 4)
            statRow(rank: rank)
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func statRow(rank: ShareSheetSubject.Rank) -> some View {
        let palette = model.palette
        let columns: [(label: String, value: String)] = [
            ("PERCENTILE", "TOP \(rank.topPercent)%"),
            ("STEPS", model.subject.stepsText),
            ("TIME", model.subject.durationText)
        ]
        return HStack(alignment: .top, spacing: 22) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 0) {
                    Text(column.value)
                        .presetText(model.font, size: 16, weight: 800, color: Color(share: palette.foreground))
                    Text(column.label)
                        .presetText(model.font, size: 9, weight: 700, trackingEm: 0.12, color: Color(share: palette.secondary))
                }
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(share: palette.rule))
                .frame(height: 1)
        }
    }
}
