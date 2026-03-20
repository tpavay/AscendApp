import SwiftUI

struct RoutineGhostCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ghostBars

            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to climb?")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(.white)

                Text("Tap the bookmark on a routine below to save it here, or create your own custom workout.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(Color.customGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.jetLighter.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var ghostBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach([0.18, 0.34, 0.26, 0.42, 0.24, 0.37, 0.21, 0.31], id: \.self) { multiplier in
                UnevenRoundedRectangle(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 2,
                    bottomTrailingRadius: 2,
                    topTrailingRadius: 2,
                    style: .continuous
                )
                .fill(.white.opacity(pulse ? 0.06 : 0.03))
                .frame(maxWidth: .infinity)
                .frame(height: 28 * multiplier, alignment: .bottom)
            }
        }
        .frame(height: 28, alignment: .bottom)
    }
}

#Preview {
    RoutineGhostCard()
        .padding(20)
        .preferredColorScheme(.dark)
}
