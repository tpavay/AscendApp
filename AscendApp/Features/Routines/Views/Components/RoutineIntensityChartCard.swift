import SwiftUI

struct RoutineIntensityChartCard: View {
    let routine: Routine
    var chartHeight: CGFloat = 56
    var accentBarWidth: CGFloat = 4
    var cornerRadius: CGFloat = 14
    var widthMode: RoutineIntensityBarChartWidthMode = .proportionalToDuration
    var showsEdgeTimeLabels: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: accentBarWidth)

            RoutineCardSurface(
                cornerRadius: cornerRadius,
                darkFillOpacity: 0.35,
                lightFillOpacity: 0.08,
                darkStrokeOpacity: 0,
                lightStrokeOpacity: 0
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    RoutineIntensityBarChart(
                        intervals: routine.intervals,
                        height: chartHeight,
                        widthMode: widthMode
                    )

                    if showsEdgeTimeLabels {
                        HStack {
                            Text("0:00")
                            Spacer()
                            Text(totalDurationLabel)
                        }
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(Color.customGray)
                    }
                }
                .padding(14)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var accentColor: Color {
        Color.heatMapColor(
            for: routine.averageIntensityTier.heatMapScore,
            colorScheme: colorScheme
        )
    }

    private var totalDurationLabel: String {
        let totalSeconds = Int(routine.totalDuration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}

#Preview {
    RoutineIntensityChartCard(routine: BuiltInRoutines.previewTemplates[6])
        .padding(20)
        .preferredColorScheme(.dark)
}
