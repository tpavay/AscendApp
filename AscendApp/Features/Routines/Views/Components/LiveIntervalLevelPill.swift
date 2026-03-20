import SwiftUI

struct LiveIntervalLevelPill: View {
    let levelText: String
    let stepTypeText: String?
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(levelText)
                .font(.montserratBold(size: Metrics.levelFontSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)

            if let stepTypeText {
                Text(stepTypeText)
                    .font(.montserratMedium(size: Metrics.stepTypeFontSize))
                    .foregroundStyle(color.opacity(Metrics.stepTypeOpacity))
                    .lineLimit(1)
                    .padding(.top, Metrics.stepTypeTopPadding)
            }

            Capsule()
                .fill(color.opacity(Metrics.underlineOpacity))
                .frame(width: Metrics.underlineWidth, height: Metrics.underlineHeight)
                .padding(.top, Metrics.underlineTopPadding)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum Metrics {
    static let levelFontSize: CGFloat = 38
    static let stepTypeFontSize: CGFloat = 12
    static let stepTypeOpacity = 0.45
    static let stepTypeTopPadding: CGFloat = 6
    static let underlineTopPadding: CGFloat = 16
    static let underlineWidth: CGFloat = 72
    static let underlineHeight: CGFloat = 1.5
    static let underlineOpacity = 0.5
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            LiveIntervalLevelPill(levelText: "Level 14", stepTypeText: nil, color: .orange)
            LiveIntervalLevelPill(levelText: "Level 9", stepTypeText: "Skip step", color: .yellow)
        }
        .padding(20)
    }
}
