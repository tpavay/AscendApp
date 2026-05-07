import ActivityKit
import Foundation

struct LiveClimbActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var steps: Int
        var rank: Int?
        var rankTotal: Int
        var durationSeconds: Int
        var progress: Double
        var isPaused: Bool
        var status: LiveClimbActivityStatus
        var climbPhotoURLString: String?
        var updatedAt: Date

        var clampedProgress: Double {
            min(max(progress, 0), 1)
        }

        var rankLabel: String {
            rank.map { "#\($0)" } ?? "--"
        }

        var rankDetailLabel: String {
            guard let rank else { return "Rank --" }

            if rankTotal > 0 {
                return "#\(rank) of \(rankTotal)"
            }

            return "#\(rank)"
        }

        var durationLabel: String {
            let totalSeconds = max(durationSeconds, 0)
            let hours = totalSeconds / 3_600
            let minutes = (totalSeconds % 3_600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
            }

            return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }
    }

    var sessionID: String
    var climbID: String
    var climbName: String
    var climbLocation: String
    var targetSteps: Int
}

enum LiveClimbActivityStatus: String, Codable, Hashable, Sendable {
    case recording
    case paused
    case saving
    case finished
    case failed
    case ended
}
