import SwiftUI

/// Total, intervals, average level and peak, sitting above the timeline. Every number is
/// derived; a number that moves while you are dragging draws in the accent so you can watch
/// the routine change without looking away from your thumb.
struct RoutineEditorStatsRow: View {
    let stats: RoutineEditorStats
    let liveKeys: Set<RoutineEditorStats.Key>

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statColumn(
                key: .total,
                value: stats.isEmpty ? "0" : "\(stats.totalMinutes)",
                unit: "min",
                title: "Total",
                spokenValue: stats.isEmpty
                    ? "No intervals"
                    : RoutineIntervalVoiceOver.durationDescription(stats.totalDuration)
            )

            statColumn(
                key: .intervalCount,
                value: "\(stats.intervalCount)",
                unit: nil,
                title: "Intervals",
                spokenValue: "\(stats.intervalCount)"
            )

            statColumn(
                key: .averageLevel,
                value: stats.isEmpty ? "–" : "\(stats.averageLevel)",
                unit: nil,
                title: "Avg level",
                spokenValue: stats.isEmpty ? "None" : "Level \(stats.averageLevel)"
            )

            statColumn(
                key: .peakLevel,
                value: stats.isEmpty ? "–" : "\(stats.peakLevel)",
                unit: nil,
                title: "Peak",
                spokenValue: stats.isEmpty ? "None" : "Level \(stats.peakLevel)"
            )
        }
    }

    private func statColumn(
        key: RoutineEditorStats.Key,
        value: String,
        unit: String?,
        title: String,
        spokenValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.montserratBold(size: 19))
                    .tracking(-0.3)
                    .foregroundStyle(valueColor(for: key))

                if let unit {
                    Text(unit)
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Text(title.uppercased())
                .font(.montserratSemiBold(size: 9))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.32))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
    }

    private func valueColor(for key: RoutineEditorStats.Key) -> Color {
        if stats.isEmpty {
            return .white.opacity(0.25)
        }
        return liveKeys.contains(key) ? .accent : .white
    }
}

#Preview {
    VStack(spacing: 28) {
        RoutineEditorStatsRow(
            stats: RoutineEditorStats(
                totalDuration: 1_080,
                intervalCount: 5,
                averageLevel: 10,
                peakLevel: 20
            ),
            liveKeys: []
        )

        RoutineEditorStatsRow(
            stats: RoutineEditorStats(
                totalDuration: 1_200,
                intervalCount: 5,
                averageLevel: 11,
                peakLevel: 20
            ),
            liveKeys: [.total, .averageLevel]
        )

        RoutineEditorStatsRow(stats: .empty, liveKeys: [])
    }
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
