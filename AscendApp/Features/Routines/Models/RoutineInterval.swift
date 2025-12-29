import Foundation

/// A single interval/segment within a routine
struct RoutineInterval: Codable, Identifiable, Equatable {
    var id: UUID
    var duration: TimeInterval
    var intensityType: IntensityType
    var intensityValue: Int
    var modifiers: IntervalModifiers
    var order: Int

    init(
        id: UUID = UUID(),
        duration: TimeInterval,
        intensityType: IntensityType = .level,
        intensityValue: Int,
        modifiers: IntervalModifiers = IntervalModifiers(),
        order: Int = 0
    ) {
        self.id = id
        self.duration = duration
        self.intensityType = intensityType
        self.intensityValue = intensityValue
        self.modifiers = modifiers
        self.order = order
    }

    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if seconds > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            if seconds > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "\(minutes) min"
            }
        } else {
            return "\(seconds)s"
        }
    }

    var durationFormattedShort: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 && seconds > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(seconds)s"
        }
    }

    var intensityDisplay: String {
        switch intensityType {
        case .level:
            return "Level \(intensityValue)"
        case .stepsPerMinute:
            return "\(intensityValue) SPM"
        }
    }

    var intensityDisplayShort: String {
        switch intensityType {
        case .level:
            return "Lvl \(intensityValue)"
        case .stepsPerMinute:
            return "\(intensityValue) SPM"
        }
    }
}
