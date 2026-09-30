import SwiftUI

/// Which of the Mountain's two pages is showing: the world, or the leaderboard one swipe over.
struct AscendMountainPageDots: View {
    let isOnLeaderboard: Bool

    var body: some View {
        HStack(spacing: 7) {
            dot(isCurrent: !isOnLeaderboard)
            dot(isCurrent: isOnLeaderboard)
        }
        .animation(.easeInOut(duration: 0.2), value: isOnLeaderboard)
        .accessibilityHidden(true)
    }

    private func dot(isCurrent: Bool) -> some View {
        Circle()
            .fill(.white.opacity(isCurrent ? 1 : 0.35))
            .frame(width: 6, height: 6)
    }
}
