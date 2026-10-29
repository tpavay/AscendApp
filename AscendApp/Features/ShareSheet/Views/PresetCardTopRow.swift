import SwiftUI

/// The card's top row: the real wordmark on the left, the best-effort badge in the centre, the date
/// on the right. The badge lives here so it never collides with a layout's content.
struct PresetCardTopRow: View {
    let model: PresetCardModel

    var body: some View {
        HStack(alignment: .center) {
            AscendWordmark(
                size: 9,
                letterColor: Color(share: model.palette.wordmarkLetters),
                markColor: Color(share: model.palette.wordmarkMark)
            )
            Spacer(minLength: 0)
            Text(model.subject.dateText)
                .presetText(.bold, size: 10, weight: 700, trackingEm: 0.1, color: Color(share: model.palette.topSecondary))
        }
        .overlay {
            PresetBestEffortBadge(display: model.bestEffort, palette: model.palette)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .frame(width: PresetCardView.designSize, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
