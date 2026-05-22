import SwiftUI

struct ClimbPreviewCardView: View {
    let summary: ClimbPreviewSummary
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                ClimbSplitCardSurface(
                    leadingWidth: 110,
                    minimumHeight: 138,
                    glowColor: summary.climb.tier.glowColor,
                    borderColors: summary.climb.tier.borderColors,
                    shadowColor: summary.climb.tier.shadowColor,
                    lineWidth: 1.8,
                    isEmphasizedBorderStyle: summary.climb.tier.usesEmphasizedBorderStyle,
                    leading: {
                        ClimbLeadingArtworkPanel(climb: summary.climb)
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.climb.name)
                                .font(.montserratBold(size: 14.5))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            HStack(spacing: 5) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.46))

                                Text(summary.climb.displayLocation)
                                    .font(.montserratRegular(size: 12))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }

                            HStack(spacing: 10) {
                                Text("\(summary.climb.referenceStepCount.formatted()) steps")
                                    .font(.montserratSemiBold(size: 12))
                                    .foregroundStyle(.white)

                                Text("|")
                                    .font(.montserratMedium(size: 11))
                                    .foregroundStyle(.white.opacity(0.26))

                                Text(estimatedTimeText)
                                    .font(.montserratSemiBold(size: 12))
                                    .foregroundStyle(.white.opacity(0.88))
                            }

                            Text("Finish in one live attempt")
                                .font(.montserratMedium(size: 10))
                                .italic()
                                .foregroundStyle(.white.opacity(0.32))
                                .lineLimit(2)
                                .lineSpacing(1)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        .padding(.trailing, 46)
                        .padding(.vertical, 12)
                    }
                )
                .frame(height: 138)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    private var estimatedTimeText: String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: summary.climb.referenceStepCount,
            spm: SettingsManager.shared.effectiveBaseLevelSPM
        )
    }

}

#Preview("New Climb") {
    ClimbPreviewCardView(
        summary: ClimbPreviewSummary(climb: .preview, isCompleted: false),
        onSelect: {},
        onClose: {}
    )
    .padding(16)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Completed Climb") {
    ClimbPreviewCardView(
        summary: ClimbPreviewSummary(climb: .preview, isCompleted: true),
        onSelect: {},
        onClose: {}
    )
    .padding(16)
    .background(.black)
    .preferredColorScheme(.dark)
}
