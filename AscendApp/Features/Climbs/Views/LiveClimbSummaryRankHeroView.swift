import SwiftUI

/// The rank-first hero at the top of the completion summary.
///
/// One rule governs every word below the ordinal: the screen may only state a
/// placement it can substantiate. A field line ("FASTEST OF 1,284 CLIMBERS")
/// asserts an ordering over a named population, so it is drawn only where the
/// hero holds both a field size and a standing whose population it can
/// characterise - and it names that population, because the static per-climb
/// board deliberately counts a different one and the two must not read as a
/// contradiction.
/// Everywhere else - a live session's own race window, a standing with no
/// denominator - the hero's own detail line stands instead, which describes the
/// standing without claiming a field.
struct LiveClimbSummaryRankHeroView: View {
    let hero: LiveClimbSummaryRankHero
    let rankingMetric: LiveReplayRankingMetric
    /// Who the field this rank was measured against counts.
    let fieldPopulation: LiveReplayFieldPopulation
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
                    .foregroundStyle(detailColor)
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

    /// The ordinal is the accent lime in every case, whether it counts a real
    /// field of climbers or the climber's own climbs. The label beneath it
    /// already names whose field it is, so a colour split would be saying the
    /// same thing twice.
    @ViewBuilder
    private var rankingValue: some View {
        switch hero.value {
        case .rank(let rank):
            ordinal(rank)

        case .personalPlacing(let placing):
            ordinal(placing.ordinal)

        case .firstAscent:
            // The permanent thing takes the hero. It is the one state with no
            // number, because every number here expires and a First Ascent
            // does not.
            Image("FirstAscentBadgeDetailed")
                .resizable()
                .scaledToFit()
                .frame(width: Self.firstAscentFlagSize, height: Self.firstAscentFlagSize)
                .accessibilityHidden(true)

        case .loading:
            AscendSkeletonText(width: 144, height: 58)

        case .unranked:
            EmptyView()
        }
    }

    private static let firstAscentFlagSize: CGFloat = 88

    private func ordinal(_ value: Int) -> some View {
        Text(value.rankOrdinalText)
            .font(.montserratBold(size: 72))
            .foregroundStyle(.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.64)
    }

    private var detailText: String {
        fieldLine ?? hero.detail
    }

    private var detailColor: Color {
        switch hero.detailEmphasis {
        case .neutral:
            return .white.opacity(0.66)
        case .prestige:
            return .ascendMedalGold
        }
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

        return "\(basis) OF \(fieldPopulation.fieldSizeLabel(count: total))"
    }

    private var accessibilityLabel: String {
        let position = switch hero.value {
        case .rank(let rank):
            "\(rank.rankOrdinalText), \(detailText.lowercased())"
        case .personalPlacing(let placing):
            "\(placing.ordinal.rankOrdinalText), \(detailText.lowercased())"
        case .firstAscent:
            hero.detail.lowercased()
        case .loading, .unranked:
            hero.detail.lowercased()
        }

        guard let label = hero.label else { return position }
        return "\(label.lowercased()), \(position)"
    }
}
