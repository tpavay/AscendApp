import SwiftUI

/// The rank-first hero at the top of the completion summary.
///
/// One rule governs every word below the ordinal: the screen may only state a
/// placement it can substantiate. A field line ("FASTEST OF 1,284") asserts an
/// ordering over a named population, so it is drawn only where the hero holds
/// both a field size and a standing whose population it can characterise.
/// Everywhere else - a live session's own race window, a standing with no
/// denominator - the hero's own detail line stands instead, which describes the
/// standing without claiming a field.
struct LiveClimbSummaryRankHeroView: View {
    let hero: LiveClimbSummaryRankHero
    let rankingMetric: LiveReplayRankingMetric
    let onRetrySync: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                if let label = hero.label {
                    Text(label)
                        .font(.montserratBold(size: 10))
                        .foregroundStyle(.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                rankingValue

                Text(detailText)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            if hero.showsRetrySync {
                Button(action: onRetrySync) {
                    Text("Retry sync")
                        .font(.montserratBold(size: 10))
                        .foregroundStyle(.accent)
                        .underline()
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rankingValue: some View {
        switch hero.value {
        case .rank(let rank):
            Text(rank.rankOrdinalText)
                .font(.montserratBold(size: 72))
                .foregroundStyle(.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

        case .loading:
            AscendSkeletonText(width: 144, height: 58)

        case .unranked:
            EmptyView()
        }
    }

    private var detailText: String {
        fieldLine ?? hero.detail
    }

    /// The plain-language ordering, or nil wherever asserting one would outrun
    /// what the hero actually knows.
    private var fieldLine: String? {
        guard case .rank = hero.value,
              let standing = hero.standing,
              standing.basis != .liveSession,
              let total = hero.total
        else { return nil }

        let basis = switch rankingMetric {
        case .fastestCompletion:
            "FASTEST"
        case .mostSteps:
            "MOST STEPS"
        }

        return "\(basis) OF \(total.formatted())"
    }

    private var accessibilityLabel: String {
        let position = switch hero.value {
        case .rank(let rank):
            "\(rank.rankOrdinalText), \(detailText.lowercased())"
        case .loading, .unranked:
            hero.detail.lowercased()
        }

        guard let label = hero.label else { return position }
        return "\(label.lowercased()), \(position)"
    }
}
