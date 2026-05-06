import SwiftUI

struct ClimbCardView: View {
    @Bindable var viewModel: GlobeViewModel
    let onOpenClimb: (Climb) -> Void

    var body: some View {
        dailyRecommendationEntry()
    }

    private func dailyRecommendationEntry() -> some View {
        Button(action: { onOpenClimb(recommendedHomeClimb) }) {
            dailyRecommendationCard(climb: recommendedHomeClimb)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open today's recommended live climb")
    }

    private func dailyRecommendationCard(climb: Climb) -> some View {
        ClimbSplitCardSurface(
            leadingWidth: 118,
            minimumHeight: 132,
            glowColor: climb.tier.glowColor,
            borderColors: climb.tier.borderColors,
            shadowColor: climb.tier.shadowColor,
            isEmphasizedBorderStyle: climb.tier.usesEmphasizedBorderStyle,
            borderAnimationStyle: .ambient,
            leading: {
                ClimbLeadingArtworkPanel(climb: climb)
            },
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY'S LIVE CLIMB")
                        .font(.montserratSemiBold(size: 10))
                        .tracking(1.3)
                        .foregroundStyle(climb.tier.color)

                    Text(climb.name)
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    Text(climb.displayLocation)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("\(climb.referenceStepCount.formatted()) steps")
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(.white.opacity(0.9))

                        Text("|")
                            .font(.montserratMedium(size: 11))
                            .foregroundStyle(.white.opacity(0.26))

                        Text(estimatedTimeText(for: climb))
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
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

    private func activeCard(summary: ActiveClimbSummary) -> some View {
        ClimbSplitCardSurface(
            leadingWidth: 118,
            minimumHeight: 132,
            glowColor: summary.climb.tier.glowColor,
            borderColors: summary.climb.tier.borderColors,
            shadowColor: summary.climb.tier.shadowColor,
            isEmphasizedBorderStyle: summary.climb.tier.usesEmphasizedBorderStyle,
            leading: {
                ClimbLeadingArtworkPanel(climb: summary.climb)
            },
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE CLIMB")
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.6)
                        .foregroundStyle(summary.climb.tier.color)

                        Text(summary.climb.name)
                            .font(.montserratBold(size: 17))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)

                    Text("\(summary.climb.city) · \(summary.climb.calculatedFloors.formatted()) floors")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Progress")
                                .font(.montserratMedium(size: 13))
                                .foregroundStyle(.white.opacity(0.56))

                            Spacer()

                            Text("\(summary.progressPercent)%")
                                .font(.montserratBold(size: 15))
                                .foregroundStyle(.accent)
                        }

                        GeometryReader { geometry in
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(hex: "829624"), .accent],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * summary.progressFraction)
                                }
                        }
                        .frame(height: 7)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        )
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
