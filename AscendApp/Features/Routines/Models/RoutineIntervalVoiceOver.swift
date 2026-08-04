import Foundation

/// What VoiceOver says about a timeline block. Dragging bars on a timeline is an invented
/// interaction, so every gesture needs a spoken equivalent: the level rides the adjustable
/// action, everything the swipe cannot carry becomes a custom action in the rotor.
enum RoutineIntervalVoiceOver {
    static let levelHint = "Swipe up or down to change the level."
    static let timelineLabel = "Routine timeline"

    /// The overview is a drag, so it needs the same treatment the blocks got: a spoken way to
    /// move the window one interval at a time.
    static let overviewLabel = "Routine overview"
    static let overviewHint = "Swipe up or down to change which intervals you're viewing."

    static func overviewValue(visibleRange: Range<Int>, count: Int) -> String {
        guard !visibleRange.isEmpty else { return "Showing every interval" }
        return "Showing intervals \(visibleRange.lowerBound + 1) to \(visibleRange.upperBound) of \(count)"
    }

    /// Rotor actions, in the order the design board lists them.
    enum Action {
        static let addTime = "Add 30 seconds"
        static let subtractTime = "Subtract 30 seconds"
        static let changeStepType = "Change step type"
        static let moveEarlier = "Move earlier"
        static let moveLater = "Move later"
        static let delete = "Delete interval"
    }

    static func label(position: Int, count: Int) -> String {
        "Interval \(position) of \(count)"
    }

    /// "Level 7, 4 minutes", plus the step type when it is anything but Standard.
    static func value(for interval: RoutineInterval) -> String {
        var value = "Level \(interval.resolvedLevel), \(durationDescription(interval.duration))"

        let stepType = RoutineStepTypeOption.from(modifiers: interval.modifiers)
        if stepType != .standard {
            value += ", \(stepType.displayName)"
        }

        return value
    }

    static func durationDescription(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        let minutePart = minutes > 0 ? "\(minutes) \(minutes == 1 ? "minute" : "minutes")" : nil
        let secondPart = seconds > 0 ? "\(seconds) \(seconds == 1 ? "second" : "seconds")" : nil

        let parts = [minutePart, secondPart].compactMap { $0 }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
