import SwiftUI

struct BaseLevelSlider: View {
    @Binding var selectedLevel: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(1...25, id: \.self) { level in
                        UnevenRoundedRectangle(
                            topLeadingRadius: level == 1 ? 4 : 0,
                            bottomLeadingRadius: level == 1 ? 4 : 0,
                            bottomTrailingRadius: level == 25 ? 4 : 0,
                            topTrailingRadius: level == 25 ? 4 : 0,
                            style: .continuous
                        )
                        .fill(segmentColor(for: level))
                    }
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateSelection(at: value.location.x, width: geometry.size.width)
                        }
                )
            }
            .frame(height: 24)

            HStack {
                ForEach([1, 5, 10, 15, 20, 25], id: \.self) { label in
                    Text("\(label)")
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(.secondary)

                    if label != 25 {
                        Spacer()
                    }
                }
            }
        }
    }

    private func segmentColor(for level: Int) -> Color {
        if level <= selectedLevel {
            return Color.heatMapColor(for: Double(level - 1) / 24.0, colorScheme: colorScheme)
        }

        return colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.08)
    }

    private func updateSelection(at location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let progress = min(max(location / width, 0), 0.9999)
        let newLevel = SPMMappingService.clampedLevel(Int(progress * 25) + 1)

        guard newLevel != selectedLevel else { return }
        selectedLevel = newLevel
        HapticsManager.shared.trigger(.lightImpact)
    }
}
