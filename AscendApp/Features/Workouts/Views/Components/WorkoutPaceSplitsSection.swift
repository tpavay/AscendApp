import SwiftUI

struct WorkoutPaceSplitsSection: View {
    let splits: [LiveClimbPaceSplit]
    let averageStepsPerMinute: Double?
    let effectiveColorScheme: ColorScheme

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.54) : .black.opacity(0.52)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06)
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    private var minStepsPerMinute: Double {
        splits.map(\.stepsPerMinute).min() ?? 0
    }

    private var maxStepsPerMinute: Double {
        splits.map(\.stepsPerMinute).max() ?? 0
    }

    private var averageText: String {
        let average: Double
        if let averageStepsPerMinute {
            average = averageStepsPerMinute
        } else if splits.isEmpty {
            average = 0
        } else {
            average = splits.map(\.stepsPerMinute).reduce(0, +) / Double(splits.count)
        }

        return Int(average.rounded()).formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Splits")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(primaryTextColor)

                HStack(spacing: 5) {
                    Text("\(splits.count.formatted()) \(splits.count == 1 ? "segment" : "segments")")
                    Text("·")
                        .foregroundStyle(.accent)
                    Text("Avg \(averageText) SPM")
                }
                .font(.montserratMedium(size: 12))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }

            VStack(spacing: 0) {
                ForEach(splits) { split in
                    WorkoutPaceSplitRow(
                        split: split,
                        minStepsPerMinute: minStepsPerMinute,
                        maxStepsPerMinute: maxStepsPerMinute,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor
                    )

                    if split.id != (splits.last?.id ?? split.id) {
                        Divider()
                            .background(borderColor)
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
    }
}

private struct WorkoutPaceSplitRow: View {
    let split: LiveClimbPaceSplit
    let minStepsPerMinute: Double
    let maxStepsPerMinute: Double
    let primaryTextColor: Color
    let secondaryTextColor: Color

    private var timeRangeText: String {
        "\(clockTime(split.startElapsedSeconds))-\(clockTime(split.endElapsedSeconds))"
    }

    private var barProgress: Double {
        guard maxStepsPerMinute > minStepsPerMinute else { return 1 }

        let range = maxStepsPerMinute - minStepsPerMinute
        let normalizedValue = min(max((split.stepsPerMinute - minStepsPerMinute) / range, 0), 1)
        return 0.25 + (normalizedValue * 0.75)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(split.index + 1)")
                .font(.montserratBold(size: 12))
                .foregroundStyle(secondaryTextColor)
                .monospacedDigit()
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timeRangeText)
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 104, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit()

                    Text("\(split.steps.formatted()) steps")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 0)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(split.stepsPerMinute.rounded()).formatted())")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(primaryTextColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("SPM")
                            .font(.montserratBold(size: 8))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .frame(width: 64, alignment: .trailing)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(secondaryTextColor.opacity(0.15))

                        Capsule()
                            .fill(splitBarGradient)
                            .frame(width: max(proxy.size.width * barProgress, 12))
                            .shadow(color: .accent.opacity(0.22), radius: 8, x: 0, y: 0)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeRangeText), \(split.steps.formatted()) steps, \(Int(split.stepsPerMinute.rounded()).formatted()) steps per minute")
    }

    private var splitBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accent.opacity(0.42),
                Color.accent.opacity(0.82),
                Color.accent
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private func clockTime(_ seconds: Int) -> String {
    let totalSeconds = max(seconds, 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
}

#Preview {
    WorkoutPaceSplitsSection(
        splits: [
            LiveClimbPaceSplit(index: 0, startElapsedSeconds: 0, endElapsedSeconds: 300, steps: 394, stepsPerMinute: 78.8),
            LiveClimbPaceSplit(index: 1, startElapsedSeconds: 300, endElapsedSeconds: 600, steps: 417, stepsPerMinute: 83.4),
            LiveClimbPaceSplit(index: 2, startElapsedSeconds: 600, endElapsedSeconds: 900, steps: 390, stepsPerMinute: 78)
        ],
        averageStepsPerMinute: 80,
        effectiveColorScheme: .dark
    )
    .padding(20)
    .background(Color.black)
}
