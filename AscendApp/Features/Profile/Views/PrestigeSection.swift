import SwiftUI

/// Merged competitive-prestige shelf: First Ascents held, then the leaderboard ladder -
/// CHAMPION, the exact podium placements, and the remaining bands - shown as a horizontal row
/// of earned badges rather than a stack of cards. When nothing is earned yet, the section
/// becomes an activation moment anchored to climb-drop notifications.
struct PrestigeSection: View {
    let held: [ProfileFirstAscentSummary]
    let open: [ProfileFirstAscentSummary]
    let achievements: ProfileAchievementLadder
    let mode: ProfileViewMode

    @State private var notificationState: ClimbDropNotificationState

    init(
        held: [ProfileFirstAscentSummary],
        open: [ProfileFirstAscentSummary],
        achievements: ProfileAchievementLadder,
        mode: ProfileViewMode,
        notificationState: ClimbDropNotificationState = .shared
    ) {
        self.held = held
        self.open = open
        self.achievements = achievements
        self.mode = mode
        _notificationState = State(initialValue: notificationState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeaderView(title: "Achievements")

            if tokens.isEmpty {
                activationContent
            } else {
                ProfilePrestigeBadgeShelf(
                    tokens: tokens,
                    imageSize: 54,
                    history: achievements.records
                )
            }
        }
        .task {
            guard mode == .own else { return }
            await notificationState.refreshIfNeeded()
        }
    }

    private var tokens: [ProfilePrestigeToken] {
        var result: [ProfilePrestigeToken] = []

        if !held.isEmpty {
            result.append(
                ProfilePrestigeToken(
                    id: "first-ascents",
                    asset: "FirstAscentBadgeDetailed",
                    tint: ProfileVisualStyle.gold,
                    count: held.count,
                    label: held.count == 1 ? "First Ascent" : "First Ascents",
                    historyFilter: nil
                )
            )
        }

        result.append(contentsOf: ProfilePrestigeToken.leaderboardTokens(for: achievements))

        return result
    }

    @ViewBuilder
    private var activationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // Free-standing, like the shelf badge it stands in for: the art is a cut-out,
                // so a circular clip would slice the flag off.
                Image("FirstAscentBadgeDetailed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .opacity(0.92)
                    .accessibilityHidden(true)

                Text(activationCopy)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode == .own, notificationState.shouldPromptForEnablement {
                Button("Turn on notifications") {
                    handleNotificationsTap()
                }
                .buttonStyle(ProfileActionButtonStyle())
                .disabled(notificationState.isUpdating)
                .opacity(notificationState.isUpdating ? 0.72 : 1)
            }
        }
    }

    private var activationCopy: String {
        if open.isEmpty {
            return "No badges yet. Top a leaderboard or claim a First Ascent and your case starts filling."
        }

        guard mode == .own, notificationState.shouldPromptForEnablement else {
            return "\(open.count) First Ascents still open. Be first up when the next climb drops."
        }

        return "\(open.count) First Ascents still open. Turn on notifications and be first up when the next climb drops."
    }

    private func handleNotificationsTap() {
        Task {
            await notificationState.enable()
        }
    }
}
