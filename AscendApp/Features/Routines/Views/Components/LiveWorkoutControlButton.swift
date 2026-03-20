import SwiftUI

struct LiveWorkoutControlButton: View {
    let systemImage: String
    let isPrimary: Bool
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isPrimary ? LiveWorkoutControlButtonMetrics.primaryIconSize : LiveWorkoutControlButtonMetrics.secondaryIconSize, weight: .semibold))
                .foregroundStyle(isPrimary ? .black : .white.opacity(0.78))
                .frame(
                    width: isPrimary ? LiveWorkoutControlButtonMetrics.primaryButtonSize : LiveWorkoutControlButtonMetrics.secondaryButtonSize,
                    height: isPrimary ? LiveWorkoutControlButtonMetrics.primaryButtonSize : LiveWorkoutControlButtonMetrics.secondaryButtonSize
                )
                .background(
                    Circle()
                        .fill(isPrimary ? Color.accent : Color.jetLighter.opacity(LiveWorkoutControlButtonMetrics.secondaryBackgroundOpacity))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

enum LiveWorkoutControlButtonMetrics {
    static let primaryIconSize: CGFloat = 26
    static let secondaryIconSize: CGFloat = 18
    static let primaryButtonSize: CGFloat = 62
    static let secondaryButtonSize: CGFloat = 46
    static let secondaryBackgroundOpacity = 0.62
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 12) {
            LiveWorkoutControlButton(systemImage: "pause.fill", isPrimary: true) {}
            LiveWorkoutControlButton(systemImage: "forward.fill", isPrimary: false) {}
            LiveWorkoutControlButton(systemImage: "stop.fill", isPrimary: false) {}
        }
    }
}
