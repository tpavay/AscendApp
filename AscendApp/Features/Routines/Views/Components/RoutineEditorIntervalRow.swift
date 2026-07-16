import SwiftUI

struct RoutineEditorIntervalRow: View {
    let interval: RoutineInterval
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                LeadingAccentStripe(color: accentColor, width: 4, cornerRadius: 16)

                RoutineCardSurface(
                    cornerRadius: 16,
                    darkFillOpacity: 0.35,
                    lightFillOpacity: 0.08,
                    darkStrokeOpacity: 0,
                    lightStrokeOpacity: 0
                ) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(interval.resolvedLevel)")
                                .font(.montserratSemiBold(size: 15))
                                .foregroundStyle(.white)

                            Text(RoutineStepTypeOption.from(modifiers: interval.modifiers).displayName)
                                .font(.montserratMedium(size: 12))
                                .foregroundStyle(Color.customGray)
                        }

                        Spacer(minLength: 8)

                        Text(interval.durationFormattedShort)
                            .font(.montserratSemiBold(size: 15))
                            .foregroundStyle(Color.customGray)

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.customGray.opacity(0.75))
                            .frame(width: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: 16))
    }

    private var accentColor: Color {
        Color.heatMapColor(
            for: interval.intensityTier.heatMapScore,
            colorScheme: colorScheme
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        RoutineEditorIntervalRow(
            interval: RoutineInterval(duration: 120, intensityValue: 5),
            isSelected: false,
            onTap: {}
        )
        RoutineEditorIntervalRow(
            interval: RoutineInterval(duration: 300, intensityValue: 10),
            isSelected: true,
            onTap: {}
        )
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
