import SwiftUI

struct ClimbCardView: View {
    @Bindable var viewModel: GlobeViewModel
    let onBrowse: () -> Void
    let onOpenClimb: (Climb) -> Void

    var body: some View {
        switch viewModel.homeCardState {
        case .neverClimbed(let totalClimbs):
            Button(action: onBrowse) {
                newUserCard(totalClimbs: totalClimbs)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Browse landmark climbs")

        case .inactive(let summary):
            Button(action: onBrowse) {
                completedCard(summary: summary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose your next climb")

        case .active(let summary):
            Button(action: { onOpenClimb(summary.climb) }) {
                activeCard(summary: summary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open your active climb")
        }
    }

    private func newUserCard(totalClimbs: Int) -> some View {
        ClimbSplitCardSurface(
            leadingWidth: 108,
            minimumHeight: 132,
            glowColor: featuredNewUserClimb.tier.glowColor,
            borderColors: featuredNewUserClimb.tier.borderColors,
            shadowColor: featuredNewUserClimb.tier.shadowColor,
            isEmphasizedBorderStyle: featuredNewUserClimb.tier.usesEmphasizedBorderStyle,
            leading: {
                ClimbLeadingArtworkPanel(climb: featuredNewUserClimb)
            },
            content: {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Climb Anything")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text("\(totalClimbs.formatted())+ real-world landmarks. Collect cards. Explore climbs.")
                        .font(.montserratRegular(size: 10.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    inlineAction(title: "Explore climbs")
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
                        Text("LAST COMPLETED")
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

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "E2C56A"))
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
                    Text("ACTIVE CLIMB")
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

    private var featuredNewUserClimb: Climb {
        if let featuredClimbId = viewModel.featuredClimbId,
           let featuredClimb = viewModel.visibleClimbs.first(where: { $0.id == featuredClimbId }) {
            return featuredClimb
        }

        if let empireState = viewModel.visibleClimbs.first(where: { $0.id == "empire-state-building" }) {
            return empireState
        }

        return viewModel.visibleClimbs.first ?? .preview
    }

    private func inlineAction(title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.montserratBold(size: 14))

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(.accent)
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
