import SwiftUI

struct IntervalTimerDisplay: View {
    let intensity: String
    let remainingTime: String
    let isNearEnd: Bool

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 20) {
            // Current intensity
            Text(intensity)
                .font(.montserratBold(size: 36))
                .foregroundStyle(.white)

            // Large countdown timer
            Text(remainingTime)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(isNearEnd ? .orange : .white)
                .scaleEffect(pulseScale)
                .monospacedDigit()
        }
        .onChange(of: isNearEnd) { _, newValue in
            if newValue {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
    }

    private func stopPulseAnimation() {
        // Use a non-repeating animation to override the repeatForever animation
        withAnimation(.easeOut(duration: 0.15)) {
            pulseScale = 1.0
        }
    }
}

#Preview {
    ZStack {
        Color.jet.ignoresSafeArea()
        IntervalTimerDisplay(
            intensity: "Level 12",
            remainingTime: "3:24",
            isNearEnd: false
        )
    }
}

#Preview("Near End") {
    ZStack {
        Color.jet.ignoresSafeArea()
        IntervalTimerDisplay(
            intensity: "Level 8",
            remainingTime: "0:04",
            isNearEnd: true
        )
    }
}
