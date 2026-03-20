import SwiftUI

struct RoutineIntervalBuilderCard: View {
    @Binding var level: Int
    @Binding var duration: TimeInterval
    @Binding var stepType: RoutineStepTypeOption

    let isEditing: Bool
    let onCommit: () -> Void
    let onCancelEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var levelScale: CGFloat = 1

    private static let durationOptions: [TimeInterval] = Array(stride(from: 30, through: 1800, by: 30)).map(TimeInterval.init)

    var body: some View {
        RoutineCardSurface(
            cornerRadius: 18,
            darkFillOpacity: 0.36,
            lightFillOpacity: 0.08,
            darkStrokeOpacity: 0,
            lightStrokeOpacity: 0
        ) {
            VStack(alignment: .leading, spacing: 18) {
                header
                SegmentedHeatmapSlider(
                    selectedLevel: $level,
                    height: 24,
                    segmentGap: 1.5,
                    outerCornerRadius: 4,
                    showsLabels: false
                )
                .onChange(of: level) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                        levelScale = 1.12
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8).delay(0.04)) {
                        levelScale = 1
                    }
                }

                stepTypeGrid

                builderFooter
            }
            .padding(18)
            .background(alignment: .topTrailing) {
                RadialGradient(
                    colors: [levelColor.opacity(0.18), .clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 180
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(level)")
                    .font(.montserratBold(size: 56))
                    .foregroundStyle(levelColor)
                    .scaleEffect(levelScale)

                Text("level")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(Color.customGray)
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(Self.durationOptions, id: \.self) { option in
                    Button(durationLabel(for: option)) {
                        duration = option
                        HapticsManager.shared.trigger(.lightImpact)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(durationLabel(for: duration))
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.customGray)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.jetDarker.opacity(0.92))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var stepTypeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(RoutineStepTypeOption.allCases) { option in
                Button {
                    guard stepType != option else { return }
                    stepType = option
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    Text(option.displayName)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(stepType == option ? .accent : Color.customGray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(stepType == option ? .accent.opacity(0.16) : Color.jetDarker.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var builderFooter: some View {
        VStack(spacing: 12) {
            Button {
                HapticsManager.shared.trigger(isEditing ? .success : .success)
                onCommit()
            } label: {
                Text(isEditing ? "Update Interval" : "Add Interval")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.accent)
                    )
            }
            .buttonStyle(.plain)

            if isEditing, onCancelEdit != nil || onDelete != nil {
                HStack(spacing: 16) {
                    if let onDelete {
                        Button("Delete") {
                            onDelete()
                        }
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.red.opacity(0.9))
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if let onCancelEdit {
                        Button("Cancel edit") {
                            onCancelEdit()
                        }
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(Color.customGray)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var levelColor: Color {
        Color.heatMapColor(
            for: IntensityTier.from(level: level).heatMapScore,
            colorScheme: colorScheme
        )
    }

    private func durationLabel(for value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 && seconds > 0 {
            return "\(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes) min"
        }
        return "\(seconds)s"
    }
}

#Preview {
    @Previewable @State var level = 14
    @Previewable @State var duration: TimeInterval = 120
    @Previewable @State var type: RoutineStepTypeOption = .standard

    RoutineIntervalBuilderCard(
        level: $level,
        duration: $duration,
        stepType: $type,
        isEditing: false,
        onCommit: {},
        onCancelEdit: nil,
        onDelete: nil
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
