import SwiftUI

/// The glyph beside a Today's Climb stake line. A First Ascent case draws the app's
/// real First Ascent mark; the rest draw their SF Symbol in the accent.
struct TodayClimbStakeLineIcon: View {
    let stakeLine: TodayClimbStakeLine
    var size: CGFloat = 12

    var body: some View {
        if stakeLine.showsFirstAscentMark {
            FirstAscentInlineMark(size: size + 4)
        } else {
            Image(systemName: stakeLine.systemImageName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.accent)
        }
    }
}

/// The First Ascent badge at inline-text size, for a line that names the claim.
/// `ClimbFirstAscentMark` is the 34pt shelf size; this is the same art beside copy.
struct FirstAscentInlineMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image("FirstAscentBadgeDetailed")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
