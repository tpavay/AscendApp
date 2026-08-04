import Foundation

/// The scale under the timeline. Ticks land on round minutes and the last label is always the
/// real time the strip ends at, so the ruler tells the truth even where the width floor has
/// overstated a short block.
///
/// It describes whatever the strip above it is drawing. That is the whole routine while the
/// intervals still fit, and the working window's slice of the routine's clock once they do not -
/// a window that opens at six minutes is labelled from six, never from zero.
enum RoutineTimelineRuler {
    private static let candidateStepsInMinutes = [1, 2, 5, 10, 15, 30, 60, 120, 240]
    private static let maximumGaps = 5

    /// A tick and where it belongs along the strip, as a fraction of the strip's span. The label
    /// has to sit over the minute it names, so the position travels with the text.
    struct Tick: Equatable, Identifiable {
        let text: String
        let fraction: Double

        var id: Double { fraction }
    }

    static func ticks(startTime: TimeInterval, endTime: TimeInterval) -> [Tick] {
        let span = endTime - startTime
        guard span > 0 else { return [] }

        let startMinutes = startTime / 60
        let endMinutes = endTime / 60
        let step = Double(stepInMinutes(totalMinutes: span / 60))

        var ticks: [Tick] = []
        var minute = startMinutes

        // Stop before the end label so the two never collide.
        while minute < endMinutes - step / 2 {
            ticks.append(
                Tick(text: minuteLabel(minute), fraction: (minute - startMinutes) / (endMinutes - startMinutes))
            )
            minute += step
        }

        ticks.append(Tick(text: endLabel(totalMinutes: endMinutes), fraction: 1))
        return ticks
    }

    static func labels(startTime: TimeInterval, endTime: TimeInterval) -> [String] {
        ticks(startTime: startTime, endTime: endTime).map(\.text)
    }

    private static func stepInMinutes(totalMinutes: Double) -> Int {
        candidateStepsInMinutes.first { totalMinutes / Double($0) <= Double(maximumGaps) }
            ?? candidateStepsInMinutes[candidateStepsInMinutes.count - 1]
    }

    private static func minuteLabel(_ minutes: Double) -> String {
        guard minutes != minutes.rounded(.down) else { return "\(Int(minutes))" }
        return "\(Int(minutes)).5"
    }

    private static func endLabel(totalMinutes: Double) -> String {
        // Durations sit on a 30-second grid, so a half minute is the only fraction possible.
        "\(minuteLabel(totalMinutes)) MIN"
    }
}
