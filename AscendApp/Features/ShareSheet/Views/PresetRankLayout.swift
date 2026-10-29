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
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            PresetBesideOrBelow(gap: 12, floor: 0.5, alignment: .bottom) {
                // The `#` and the number are one line of text in two sizes, so they scale together
                // and share a baseline. A line box of 0.82em, as the design sets it, so the number
                // sits on the hairline row. Tracking does not scale with the text, so a long number,
                // which is scaled the most, gets a looser fit than the design's -0.06em or its
                // digits would overlap.
                Text("\(model.font.run("#", size: 52, weight: 900, color: Color(share: palette.accentText)))\(model.font.run(rank.positionText, size: 104, weight: 900, trackingEm: rank.positionText.count <= 4 ? -0.06 : -0.02, color: Color(share: palette.foreground)))")
                    .presetOneLine()
                    .frame(height: 104 * 0.82)
                Text("of \(rank.fieldText)")
                    .presetText(model.font, size: 20, weight: 800, color: Color(share: palette.foreground))
                    .presetOneLine(floor: PresetFitGeometry.labelFloor)
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
        PresetStatRow(model: model, columns: [
            PresetStatColumn(id: "percentile", value: rank.leadsWithPercent ? "TOP \(rank.topPercent)%" : "BEAT \(rank.beatPercent)%", label: "PERCENTILE"),
            PresetStatColumn(id: "steps", value: model.subject.stepsText, label: "STEPS"),
            PresetStatColumn(id: "time", value: model.subject.durationText, label: "TIME")
        ])
    }
}
