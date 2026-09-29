import SwiftUI

/// The two tiles under the today rows: this week's rank by steps, and the streak of
/// weeks with a climb. The rank tile opens the Leaderboard tab; the streak tile opens
/// Profile, where the activity calendar shows the weeks behind the number.
struct HomeRankStreakSection: View {
    let weeklyRankSummary: HomeWeeklyRankSummary?
    let isRankLoading: Bool
    let streak: WeeklyStreak
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
                streak: streak,
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

/// A tile's accent title and disclosure chevron. The row keeps one height however far the
/// title shrinks to fit, so the two tiles' lines below it stay level.
private struct HomeTileHeader: View {
    let title: String

    var body: some View {
        HomeTileLine(font: .montserratSemiBold(size: 10)) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                CardDisclosureChevron()
            }
        }
    }
}

/// One line of a tile, as tall as a line of `font` with `content` on its baseline, whatever
/// `content` is: a line that shrinks to fit, or reads differently from state to state, never
/// moves the lines beneath it out of step with the neighbouring tile.
private struct HomeTileLine<Content: View>: View {
    let font: Font
    @ViewBuilder let content: Content

    var body: some View {
        Text(verbatim: "0")
            .font(font)
            .lineLimit(1)
            .hidden()
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leadingFirstTextBaseline) {
                content
            }
    }
}

private struct HomeRankCard: View {
    let summary: HomeWeeklyRankSummary?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HomeTileHeader(title: "WEEKLY RANK · STEPS")

                rankValue

                Text(statusText)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116, alignment: .top)
            .background(HomeTileBackground())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Never a bare "-": level with the streak tile's number, a lone dash read as a minus
    /// sign on the streak ("-2 wks").
    private var rankValue: some View {
        HomeTileLine(font: .montserratBold(size: 34)) {
            if let summary {
                Text("#\(summary.rank)")
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if isLoading {
                Text(verbatim: "#00")
                    .font(.montserratBold(size: 34))
                    .redacted(reason: .placeholder)
            } else {
                Text("Unranked")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
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
    let streak: WeeklyStreak
    let action: () -> Void

    var body: some View {
        let copy = HomeStreakCopy(streak: streak)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HomeTileHeader(title: "STREAK")

                HomeTileLine(font: .montserratBold(size: 34)) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(streak.weeks.formatted())
                            .font(.montserratBold(size: 34))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(copy.unit)
                            .font(.montserratBold(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Text(copy.subtitle)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116, alignment: .top)
            .background(HomeTileBackground())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy.accessibilityLabel)
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
