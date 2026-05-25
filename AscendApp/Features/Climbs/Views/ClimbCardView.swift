import SwiftUI

struct ClimbCardView: View {
    @Bindable var viewModel: GlobeViewModel
    let onOpenClimb: (Climb) -> Void

    var body: some View {
        let climb = recommendedHomeClimb

        Button(action: { onOpenClimb(climb) }) {
            dailyRecommendationCard(climb: climb)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open today's recommended live climb")
    }

    private func dailyRecommendationCard(climb: Climb) -> some View {
        ZStack(alignment: .bottomLeading) {
            ClimbArtworkView(climb: climb, variant: .card)

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: UnitPoint(x: 0.5, y: 0.42),
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S CLIMB")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(1.6)
                    .foregroundStyle(.white)

                Text(climb.name)
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .padding(.top, 2)

                Text(climb.displayLocation)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                todayStakeLine
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animatedClimbCardBorder(
            colors: climb.tier.borderColors,
            shadowColor: climb.tier.shadowColor,
            cornerRadius: 24,
            lineWidth: 1.5,
            isEmphasized: climb.tier.usesEmphasizedBorderStyle,
            animationStyle: .ambient
        )
    }

    private func completedCard(summary: CompletedClimbSummary) -> some View {
        ClimbSplitCardSurface(
            leadingWidth: 112,
            minimumHeight: 132,
            glowColor: Color(hex: "D6B35B").opacity(0.1),
            borderColors: [Color(hex: "7E6730"), Color(hex: "D8BE6C")],
            shadowColor: Color(hex: "B7913A"),
            leading: {
                ClimbLeadingArtworkPanel(climb: summary.climb)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.accent))
                            .padding(10)
                    }
            },
            content: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LAST LIVE CLIMB")
                            .font(.montserratSemiBold(size: 11))
                            .tracking(1.4)
                            .foregroundStyle(Color(hex: "E7D58F"))

                        Text(summary.climb.name)
                            .font(.montserratBold(size: 17))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(completedCardSubtitle(summary: summary))
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text("\(summary.collectionCount.formatted())")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(Color(hex: "F3E58A"))

                            Text("/\(summary.totalClimbs.formatted()) collected")
                                .font(.montserratMedium(size: 13))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        )
    }

    private var todayStakeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: viewModel.todayClimbStakeLine.systemImageName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accent)
                .frame(width: 16, alignment: .leading)

            Text(viewModel.todayClimbStakeLine.text)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.todayClimbStakeLine.text)
    }

    private var recommendedHomeClimb: Climb {
        if let dailyRecommendedClimb = viewModel.dailyRecommendedClimb {
            return dailyRecommendedClimb
        }

        if let featuredClimbId = viewModel.featuredClimbId,
           let featuredClimb = viewModel.visibleClimbs.first(where: { $0.id == featuredClimbId }) {
            return featuredClimb
        }

        if let empireState = viewModel.visibleClimbs.first(where: { $0.id == "empire-state-building" }) {
            return empireState
        }

        return viewModel.visibleClimbs.first ?? .preview
    }

    private func estimatedTimeText(for climb: Climb) -> String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: climb.referenceStepCount,
            spm: SettingsManager.shared.effectiveBaseLevelSPM
        )
    }

    private func completedCardSubtitle(summary: CompletedClimbSummary) -> String {
        let timeText: String
        if let bestCompletionDurationSeconds = summary.bestCompletionDurationSeconds {
            timeText = "\(DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds))) best"
        } else {
            timeText = "Completed"
        }

        let repeatText = summary.completionsCount == 1
            ? "1×"
            : "\(summary.completionsCount)×"

        if let collectionOrder = summary.collectionOrder {
            return "\(timeText) · \(repeatText) · #\(collectionOrder)"
        }

        return "\(timeText) · \(repeatText)"
    }
}
