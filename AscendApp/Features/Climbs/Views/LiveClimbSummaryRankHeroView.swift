import SwiftUI

struct LiveClimbSummaryRankHeroView: View {
    let hero: LiveClimbSummaryRankHero
    let rankingMetric: LiveReplayRankingMetric
    let onRetrySync: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
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
                Button("Retry sync", action: onRetrySync)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(.accent)
                    .underline()
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
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
        guard case .rank = hero.value else { return hero.detail }

        let basis = switch rankingMetric {
        case .fastestCompletion:
            "FASTEST"
        case .mostSteps:
            "MOST STEPS"
        }

        guard let total = hero.total else { return basis }
        return "\(basis) OF \(total.formatted())"
    }

    private var accessibilityLabel: String {
        switch hero.value {
        case .rank(let rank):
            return "\(rank.rankOrdinalText), \(detailText.lowercased())"
        case .loading, .unranked:
            return hero.detail
        }
    }
}
