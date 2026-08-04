import Foundation

/// The scale under the timeline. Ticks land on round minutes and the last label is always
/// the routine's real length, so the ruler tells the truth even where the width floor has
/// overstated a short block.
enum RoutineTimelineRuler {
    private static let candidateStepsInMinutes = [1, 2, 5, 10, 15, 30, 60, 120, 240]
    private static let maximumGaps = 5

    /// A tick and where it belongs along the strip, as a fraction of the routine's length.
    /// The label has to sit over the minute it names, so the position travels with the text.
    struct Tick: Equatable, Identifiable {
        let text: String
        let fraction: Double

        var id: Double { fraction }
    }

    static func ticks(totalDuration: TimeInterval) -> [Tick] {
        guard totalDuration > 0 else { return [] }

        let totalMinutes = totalDuration / 60
        let step = Double(stepInMinutes(totalMinutes: totalMinutes))

        var ticks: [Tick] = []
        var minute = 0.0

        // Stop before the end label so the two never collide.
        while minute < totalMinutes - step / 2 {
            ticks.append(Tick(text: "\(Int(minute))", fraction: minute / totalMinutes))
            minute += step
        }

        ticks.append(Tick(text: endLabel(totalMinutes: totalMinutes), fraction: 1))
        return ticks
    }

    static func labels(totalDuration: TimeInterval) -> [String] {
        ticks(totalDuration: totalDuration).map(\.text)
    }

    private static func stepInMinutes(totalMinutes: Double) -> Int {
        candidateStepsInMinutes.first { totalMinutes / Double($0) <= Double(maximumGaps) }
            ?? candidateStepsInMinutes[candidateStepsInMinutes.count - 1]
    }

    private static func endLabel(totalMinutes: Double) -> String {
        // Durations sit on a 30-second grid, so a half minute is the only fraction possible.
        guard totalMinutes != totalMinutes.rounded(.down) else {
            return "\(Int(totalMinutes)) MIN"
        }
        return "\(Int(totalMinutes)).5 MIN"
    }
}
