import SwiftUI

/// The climber's own period: one big number, two stats with their gains, then what they
/// earned and the best efforts they set - each part labelled, each badge named in words.
struct PeriodRecapYourPage: View {
    @Environment(\.recapIsStatic) private var isStatic

    let summary: PeriodRecapPersonal

    private var recap: PeriodRecap.Active {
        summary.recap
    }

    private var period: LeaderboardPeriod {
        summary.period
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RecapSectionLabel(PeriodRecapCopy.yourSectionLabel(for: period))
                    .padding(.top, 24)
                    .recapEntrance(0)

                hero
                    .padding(.top, 6)
                    .recapEntrance(1)

                pair
                    .padding(.top, 26)
                    .padding(.bottom, 22)
                    .recapEntrance(2)

                if !earnedRows.isEmpty {
                    divider
                    RecapSectionLabel(PeriodRecapCopy.earnedSectionLabel(for: period))
                        .padding(.bottom, 12)
                        .recapEntrance(3)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(earnedRows) { row in
                            earnedRow(row)
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.bottom, 20)
                    .recapEntrance(4)
                }

                if !summary.bestEfforts.isEmpty {
                    divider
                    RecapSectionLabel("NEW BEST EFFORTS")
                        .padding(.bottom, 12)
                        .recapEntrance(5)
                    VStack(spacing: 10) {
                        ForEach(summary.bestEfforts, id: \.title) { effort in
                            bestEffortRow(effort)
                        }
                    }
                    .frame(maxWidth: 300)
                    .padding(.bottom, 12)
                    .recapEntrance(6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var hero: some View {
        if let rank = recap.rank, let climberCount = recap.climberCount {
            VStack(spacing: 8) {
                Text("#\(rank.formatted())")
                    .font(.montserratBold(size: 96))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Rank \(rank)")

                Text(PeriodRecapCopy.rankContext(climberCount: climberCount, percentileBand: recap.percentileBand))
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(RecapStyle.secondaryText)
            }
        } else {
            VStack(spacing: 8) {
                RecapCountUpText(
                    value: recap.steps,
                    font: .montserratBold(size: 72),
                    alignment: .center,
                    isStatic: isStatic
                )
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)

                Text(period.timeFrame == .monthly ? "steps this month" : "steps this week")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(RecapStyle.secondaryText)
            }
        }
    }

    private var pair: some View {
        HStack(alignment: .top, spacing: 48) {
            if recap.rank != nil, recap.climberCount != nil {
                stat(value: recap.climbs, label: "CLIMBS", gain: PeriodRecapCopy.gainLine(current: recap.climbs, previous: recap.previousClimbs, period: period))
                stat(value: recap.steps, label: "STEPS", gain: PeriodRecapCopy.gainLine(current: recap.steps, previous: recap.previousSteps, period: period))
            } else {
                stat(value: recap.climbs, label: "CLIMBS", gain: PeriodRecapCopy.gainLine(current: recap.climbs, previous: recap.previousClimbs, period: period))
                stat(value: recap.floors, label: "FLOORS", gain: nil)
            }
        }
    }

    private func stat(value: Int, label: String, gain: String?) -> some View {
        VStack(spacing: 6) {
            RecapCountUpText(
                value: value,
                font: .montserratBold(size: 40),
                alignment: .center,
                delay: 0.1,
                isStatic: isStatic
            )
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)

            RecapSectionLabel(label)

            Text(gain ?? " ")
                .font(.montserratBold(size: 11))
                .foregroundStyle(Color.accent)
                .opacity(gain == nil ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.bottom, 18)
    }

    private var earnedRows: [PeriodRecapEarnedRow] {
        PeriodRecapCopy.earnedRows(for: recap, period: period) { climbId in
            try? ClimbService.shared.climb(for: climbId)?.name
        }
    }

    private func earnedRow(_ row: PeriodRecapEarnedRow) -> some View {
        HStack(spacing: 14) {
            Image(row.asset)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                Text(row.detail)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bestEffortRow(_ effort: PeriodRecapBestEffort) -> some View {
        HStack(spacing: 12) {
            AppIcon(token: .bestEffortTrophy, pointSize: 20, weight: .semibold)
                .foregroundStyle(BestEffortUIStyle.trophyColor(for: 1))
                .frame(width: 26)
                .accessibilityHidden(true)

            Text(effort.title)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(effort.value)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
