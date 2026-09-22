import SwiftUI

/// The two tiles under the today rows: this week's rank by steps, and the streak of
/// weeks with a climb. The rank tile opens the Leaderboard tab; the streak tile opens
/// Profile, where the activity calendar shows the weeks behind the number.
struct HomeRankStreakSection: View {
    let weeklyRankSummary: HomeWeeklyRankSummary?
    let isRankLoading: Bool
    let currentStreakWeeks: Int
    let onRankTapped: () -> Void
    let onStreakTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HomeRankCard(
                summary: weeklyRankSummary,
                isLoading: isRankLoading,
                action: onRankTapped
            )

            HomeStreakCard(
                weeks: currentStreakWeeks,
                action: onStreakTapped
            )
        }
    }
}

/// Subtle trailing disclosure cue that signals the tiles navigate on tap.
private struct CardDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .accessibilityHidden(true)
    }
}

private struct HomeRankCard: View {
    let summary: HomeWeeklyRankSummary?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("WEEKLY RANK · STEPS")
                        .font(.montserratSemiBold(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(Color.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 4)

                    CardDisclosureChevron()
                }

                Text(summary.map { "#\($0.rank)" } ?? "-")
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(statusText)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116)
            .background(HomeTileBackground())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: String {
        guard let summary else {
            return isLoading ? "Updating rank" : "Climb to be ranked"
        }

        return LeaderboardRankSubtitleFormatter.subtitle(for: summary.subtitleContext)
    }

    private var accessibilityLabel: String {
        guard let summary else {
            return isLoading ? "Weekly rank by steps is updating." : "Not yet ranked. Climb to be ranked."
        }
        return "Weekly rank by steps: number \(summary.rank). \(statusText)."
    }
}

private struct HomeStreakCard: View {
    let weeks: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("STREAK")
                        .font(.montserratSemiBold(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(Color.accent)

                    Spacer(minLength: 4)

                    CardDisclosureChevron()
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weeks.formatted())
                        .font(.montserratBold(size: 34))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(weeks == 1 ? "wk" : "wks")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text(subtitle)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116)
            .background(HomeTileBackground())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The week ends Sunday app-wide (Monday start), so the deadline is always the
    /// same day; what changes is whether this week already counts.
    private var subtitle: String {
        weeks > 0 ? "in a row · ends Sunday" : "Climb this week to start one"
    }

    private var accessibilityLabel: String {
        weeks > 0
            ? "Streak: \(weeks) \(weeks == 1 ? "week" : "weeks") in a row. Ends Sunday."
            : "No streak yet. Climb this week to start one."
    }
}

/// The shared surface behind Home's tiles.
struct HomeTileBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension HomeWeeklyRankSummary {
    var subtitleContext: LeaderboardRankSubtitleContext {
        LeaderboardRankSubtitleContext(
            rank: rank,
            totalClimbers: population,
            tiedForFirst: isTiedForGold,
            stepsAheadOfSecond: stepsAheadOfSecond,
            stepsFromGold: stepsFromGold,
            stepsFromSilver: stepsFromSilver,
            stepsToBronze: stepsToBronze,
            stepsToTopTen: stepsToTop10,
            stepsToTopHundred: stepsToTop100,
            stepsToTopFiftyPercent: stepsToTop50Percent
        )
    }
}
