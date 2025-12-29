import SwiftUI

struct NextIntervalPreview: View {
    let interval: RoutineInterval?

    var body: some View {
        if let interval = interval {
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle")
                    .font(.system(size: 14, weight: .medium))

                Text("Up next:")
                    .font(.montserratRegular(size: 14))

                Text("\(interval.intensityDisplay) for \(interval.durationFormatted)")
                    .font(.montserratSemiBold(size: 14))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.white.opacity(0.1))
            )
        } else {
            // Last interval - no next
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 14, weight: .medium))
                Text("Final interval")
                    .font(.montserratMedium(size: 14))
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

#Preview {
    ZStack {
        Color.jet.ignoresSafeArea()
        VStack(spacing: 20) {
            NextIntervalPreview(interval: RoutineInterval(
                duration: 300,
                intensityType: .level,
                intensityValue: 10,
                modifiers: .none,
                order: 1
            ))

            NextIntervalPreview(interval: nil)
        }
    }
}
