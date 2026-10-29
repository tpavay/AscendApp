import SwiftUI

/// The best-effort laurel: with the real count inside when several were earned, or beside a
/// two-line record when one is shown.
struct PresetBestEffortBadge: View {
    let display: ShareBestEffortDisplay
    let palette: PresetCardPalette

    var body: some View {
        switch display {
        case .none:
            EmptyView()
        case .count(let count):
            ZStack {
                Image("BestEffortLaurel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 27)
                Text("\(count)")
                    .presetText(.bold, size: 11, weight: 900, color: Color(share: palette.wordmarkLetters))
                    .padding(.top, 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) best efforts")
        case .line(let effort):
            HStack(spacing: 4) {
                Image("BestEffortLaurel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 19)
                VStack(alignment: .leading, spacing: 0) {
                    Text(effort.detailText)
                        .presetText(.bold, size: 7, weight: 800, trackingEm: 0.14, color: Color(share: palette.topSecondary))
                    Text(effort.title)
                        .presetText(.bold, size: 8, weight: 800, trackingEm: 0.05, color: Color(share: palette.wordmarkLetters))
                }
                .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Best effort: \(effort.detailText) \(effort.title)")
        }
    }
}
