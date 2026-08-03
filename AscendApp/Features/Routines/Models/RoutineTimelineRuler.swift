import Foundation

/// The scale under the timeline. Ticks land on round minutes and the last label is always
/// the routine's real length, so the ruler tells the truth even where the width floor has
/// overstated a short block.
enum RoutineTimelineRuler {
    private static let candidateStepsInMinutes = [1, 2, 5, 10, 15, 30, 60, 120, 240]
    private static let maximumGaps = 5

    static func labels(totalDuration: TimeInterval) -> [String] {
        guard totalDuration > 0 else { return [] }

        let totalMinutes = totalDuration / 60
        let step = Double(stepInMinutes(totalMinutes: totalMinutes))

        var labels: [String] = []
        var tick = 0.0

        // Stop before the end label so the two never collide.
        while tick < totalMinutes - step / 2 {
            labels.append("\(Int(tick))")
            tick += step
        }

        labels.append(endLabel(totalMinutes: totalMinutes))
        return labels
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
        return "\(Int(totalMinutes)).5"
    }
}
