import SwiftUI

struct SegmentedHeatmapSlider: View {
    @Binding var selectedLevel: Int

    var range: ClosedRange<Int> = 1...25
    var height: CGFloat = 24
    var segmentGap: CGFloat = 2
    var outerCornerRadius: CGFloat = 4
    var showsLabels: Bool = true
    var labelValues: [Int] = [1, 5, 10, 15, 20, 25]
    var unfilledDarkOpacity: CGFloat = 0.06
    var unfilledLightOpacity: CGFloat = 0.08
    var onSelectionChanged: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var clampedSelectedLevel: Int {
        min(max(selectedLevel, range.lowerBound), range.upperBound)
    }

    private var segmentValues: [Int] {
        Array(range)
    }

    private var segmentCount: Int {
        segmentValues.count
    }

    var body: some View {
        VStack(spacing: showsLabels ? 8 : 0) {
            GeometryReader { geometry in
                HStack(spacing: segmentGap) {
                    ForEach(segmentValues, id: \.self) { level in
                        UnevenRoundedRectangle(
                            topLeadingRadius: level == range.lowerBound ? outerCornerRadius : 0,
                            bottomLeadingRadius: level == range.lowerBound ? outerCornerRadius : 0,
                            bottomTrailingRadius: level == range.upperBound ? outerCornerRadius : 0,
                            topTrailingRadius: level == range.upperBound ? outerCornerRadius : 0,
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
            .frame(height: height)

            if showsLabels {
                HStack {
                    ForEach(labelValues, id: \.self) { label in
                        Text("\(label)")
                            .font(.montserratRegular(size: 11))
                            .foregroundStyle(.secondary)

                        if label != labelValues.last {
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func segmentColor(for level: Int) -> Color {
        guard level <= clampedSelectedLevel else {
            return colorScheme == .dark ? .white.opacity(unfilledDarkOpacity) : .black.opacity(unfilledLightOpacity)
        }

        let normalizedLevel = Double(level - range.lowerBound) / Double(max(segmentCount - 1, 1))
        return Color.heatMapColor(for: normalizedLevel, colorScheme: colorScheme)
    }

    private func updateSelection(at location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        let progress = min(max(location / width, 0), 0.9999)
        let levelCount = segmentCount
        let newLevel = range.lowerBound + Int(progress * Double(levelCount))
        let clampedLevel = min(max(newLevel, range.lowerBound), range.upperBound)

        guard clampedLevel != selectedLevel else { return }
        selectedLevel = clampedLevel
        HapticsManager.shared.trigger(.lightImpact)
        onSelectionChanged?(clampedLevel)
    }
}

#Preview {
    @Previewable @State var level = 12

    VStack(spacing: 24) {
        SegmentedHeatmapSlider(selectedLevel: $level)
        SegmentedHeatmapSlider(
            selectedLevel: $level,
            segmentGap: 1.5,
            showsLabels: false
        )
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
