import SwiftUI

struct HomeRankGlobeSection: View {
    let weeklyRankSummary: HomeWeeklyRankSummary?
    let isRankLoading: Bool
    let completedClimbCount: Int
    let totalClimbCount: Int
    let onRankTapped: () -> Void
    let onGlobeTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HomeRankCard(
                summary: weeklyRankSummary,
                isLoading: isRankLoading,
                action: onRankTapped
            )

            HomeMyGlobeCard(
                count: completedClimbCount,
                total: totalClimbCount,
                action: onGlobeTapped
            )
        }
    }
}

/// Subtle trailing disclosure cue that signals the rank / globe tiles navigate on tap.
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

                Text(summary.map { "#\($0.rank)" } ?? "—")
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
            .background(cardBackground)
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeMyGlobeCard: View {
    let count: Int
    let total: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("MY GLOBE")
                        .font(.montserratSemiBold(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(Color.accent)

                    Spacer(minLength: 4)

                    CardDisclosureChevron()
                }

                Text("\(count) / \(resolvedTotal)")
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .allowsTightening(true)
                    .layoutPriority(2)

                Text(subtitle)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("My globe: \(count) of \(resolvedTotal) climbs collected")
    }

    private var resolvedTotal: Int {
        max(total, count)
    }

    /// Frames the collection as a gap to close — a dare, not a description.
    /// Falls back to the neutral descriptor until the catalog total has loaded.
    private var subtitle: String {
        guard resolvedTotal > 0 else { return "climbs collected" }
        let remaining = resolvedTotal - count
        return remaining > 0 ? "\(remaining) to claim" : "All claimed"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(alignment: .bottomTrailing) {
                Image("HomeMyGlobeArtwork")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .opacity(0.85)
                    .offset(x: 40, y: 40)
                    .accessibilityHidden(true)
            }
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
