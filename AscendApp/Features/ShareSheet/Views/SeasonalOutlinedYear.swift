import SwiftUI

/// The big gold outline year on the Year card.
struct SeasonalOutlinedYear: View {
    let year: Int

    var body: some View {
        SeasonalYearOutlineShape(text: String(year))
            .stroke(Color(shareHex: 0xFBBF24), lineWidth: 2)
            .opacity(0.9)
            .frame(width: PresetCardView.designSize, height: PresetCardView.designSize)
    }
}
