import SwiftUI

/// A board nobody has entered yet. The three pedestals stand open with the champion's
/// crown already on the centre one, so the empty state is the prize rather than a
/// notice that there is nothing here.
struct LeaderboardEmptyBoardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let period: LeaderboardPeriod
    let metric: LeaderboardMetric

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                // States which window is empty before it commands. "No entries yet" on a
                // month that reset hours ago reads as lost data; "August is empty" reads
                // as a fresh board.
                Text("\(period.windowSubject) is empty.")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.center)

                Text("Take the first spot.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(primaryTextColor.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            LeaderboardPodiumView(entries: [], metric: metric)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
}
