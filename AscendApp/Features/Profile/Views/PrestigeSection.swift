import SwiftUI

/// Merged competitive-prestige shelf: First Ascents held + leaderboard achievement bands,
/// shown as a horizontal row of earned badges rather than a stack of cards. When nothing is
/// earned yet, the section becomes an activation moment anchored to climb-drop notifications.
struct PrestigeSection: View {
    let held: [ProfileFirstAscentSummary]
    let open: [ProfileFirstAscentSummary]
    let achievements: ProfileAchievementCounts
    let achievementRecords: [ProfileAchievementRecord]
    let mode: ProfileViewMode

    @State private var notificationState: ClimbDropNotificationState
    @State private var selectedAchievementBand: ProfileAchievementRankBand?

    init(
        held: [ProfileFirstAscentSummary],
        open: [ProfileFirstAscentSummary],
        achievements: ProfileAchievementCounts,
        achievementRecords: [ProfileAchievementRecord],
        mode: ProfileViewMode,
        notificationState: ClimbDropNotificationState = .shared
    ) {
        self.held = held
        self.open = open
        self.achievements = achievements
        self.achievementRecords = achievementRecords
        self.mode = mode
        _notificationState = State(initialValue: notificationState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeaderView(title: "Achievements")

            if tokens.isEmpty {
                activationContent
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(tokens) { token in
                            if let band = token.achievementBand {
                                Button {
                                    HapticsManager.shared.trigger(.lightImpact)
                                    selectedAchievementBand = band
                                } label: {
                                    badge(token)
                                }
                                .buttonStyle(.plain)
                            } else {
                                badge(token)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $selectedAchievementBand) { band in
            AchievementHistorySheet(
                band: band,
                records: achievementRecords.filter { $0.countsToward(band) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            guard mode == .own else { return }
            await notificationState.refreshIfNeeded()
        }
    }

    private var tokens: [PrestigeToken] {
        var result: [PrestigeToken] = []

        if !held.isEmpty {
            result.append(
                PrestigeToken(
                    id: "first-ascents",
                    asset: "FirstAscentBadgeDetailed",
                    tint: ProfileVisualStyle.gold,
                    count: held.count,
                    label: held.count == 1 ? "First Ascent" : "First Ascents",
                    achievementBand: nil
                )
            )
        }

        if achievements.top1 > 0 {
            result.append(
                PrestigeToken(
                    id: "top1",
                    asset: "LeaderboardCrown",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top1,
                    label: ProfileTerminology.topOneAchievementLabel,
                    achievementBand: .top1
                )
            )
        }
        if achievements.top3 > 0 {
            result.append(
                PrestigeToken(
                    id: "top3",
                    asset: "LeaderboardTop3",
                    tint: ProfileVisualStyle.silver,
                    count: achievements.top3,
                    label: ProfileTerminology.topThreeAchievementLabel,
                    achievementBand: .top3
                )
            )
        }
        if achievements.top10 > 0 {
            result.append(
                PrestigeToken(
                    id: "top10",
                    asset: "LeaderboardTop10",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top10,
                    label: ProfileTerminology.topTenAchievementLabel,
                    achievementBand: .top10
                )
            )
        }
        if achievements.top100 > 0 {
            result.append(
                PrestigeToken(
                    id: "top100",
                    asset: "LeaderboardTop100",
                    tint: ProfileVisualStyle.secondaryText,
                    count: achievements.top100,
                    label: ProfileTerminology.topHundredAchievementLabel,
                    achievementBand: .top100
                )
            )
        }

        return result
    }

    private func badge(_ token: PrestigeToken) -> some View {
        VStack(spacing: 8) {
            Image(token.asset)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(token.tint.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: token.tint.opacity(0.26), radius: 6, y: 2)

            Text(token.count.formatted(.number.grouping(.automatic)))
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            Text(token.label.uppercased())
                .font(.montserratSemiBold(size: 9))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 88)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.label), \(token.count)")
    }

    @ViewBuilder
    private var activationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image("FirstAscentBadgeDetailed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
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

private struct PrestigeToken: Identifiable {
    let id: String
    let asset: String
    let tint: Color
    let count: Int
    let label: String
    let achievementBand: ProfileAchievementRankBand?
}
