import Foundation

enum TodayClimbStakeLine: Equatable {
    case unavailable
    case openFirstAscent
    case nextFinisher(Int)
    case joinFinishers(Int)
    case completed(bestDurationSeconds: Int, globalCompletionOrder: Int)
    case completedPendingOrdinal(bestDurationSeconds: Int)
    case firstAscent(bestDurationSeconds: Int)

    var text: String {
        switch self {
        case .unavailable:
            return "Climb it. Claim your place on the board."
        case .openFirstAscent:
            return "First Ascent open. The first finisher claims it forever."
        case .nextFinisher(let order):
            return "Be the \(Self.ordinalText(for: order)) finisher."
        case .joinFinishers(let count):
            return "Join \(Self.bucketText(for: count))+ finishers."
        case .completed(let bestDurationSeconds, let globalCompletionOrder):
            return "Your best: \(Self.timeText(for: bestDurationSeconds)) · \(Self.ordinalText(for: globalCompletionOrder)) finisher"
        case .completedPendingOrdinal(let bestDurationSeconds):
            return "Your best: \(Self.timeText(for: bestDurationSeconds))"
        case .firstAscent(let bestDurationSeconds):
            return "First Ascent · \(Self.timeText(for: bestDurationSeconds)) · yours forever"
        }
    }

    var systemImageName: String {
        switch self {
        case .openFirstAscent, .firstAscent:
            return "flag.checkered"
        case .completed, .completedPendingOrdinal:
            return "checkmark.seal.fill"
        case .nextFinisher, .joinFinishers:
            return "person.2.fill"
        case .unavailable:
            return "mountain.2.fill"
        }
    }

    private static func timeText(for seconds: Int) -> String {
        DurationFormatter.format(duration: TimeInterval(max(seconds, 0)))
    }

    private static func ordinalText(for value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: max(value, 1))) ?? "\(max(value, 1))"
    }

    private static func bucketText(for count: Int) -> String {
        let resolvedCount = max(count, 0)

        switch resolvedCount {
        case 10_000...:
            return "10k"
        case 3_000...:
            return "3k"
        case 1_000...:
            return "1k"
        case 500...:
            return "500"
        default:
            return "100"
        }
    }
}
