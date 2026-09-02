import ActivityKit
import Foundation

struct LiveClimbActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var steps: Int
        /// The leaderboard placing, or nil where the board holds no other
        /// climber and so has no leaderboard placing to state.
        var rank: Int?
        var rankTotal: Int
        /// Where this run places among the climber's own climbs of this board.
        /// The only thing a solo board can substantiate, and what it states
        /// instead of an ordinal nothing measured.
        var ownClimbsPlacing: Int?
        var ownClimbsTotal: Int
        var durationSeconds: Int
        var progress: Double
        var status: LiveClimbActivityStatus
        var climbPhotoURLString: String?
        var updatedAt: Date

        var clampedProgress: Double {
            min(max(progress, 0), 1)
        }

        /// The compact value, and the caption that names what it counted.
        ///
        /// The two travel together on purpose: an ordinal captioned `rank` on a
        /// board with no field is the defect this pair exists to prevent.
        var standingValue: String {
            if let rank {
                return "#\(rank)"
            }

            guard let ownClimbsPlacing else { return "--" }
            return Self.ordinalText(ownClimbsPlacing)
        }

        var standingCaption: String {
            rank == nil && ownClimbsPlacing != nil ? "climbs" : "rank"
        }

        var standingTitle: String {
            rank == nil && ownClimbsPlacing != nil ? "Your climbs" : "Rank"
        }

        var compactStepsLabel: String {
            max(steps, 0).formatted()
        }

        var minimalStepsLabel: String {
            let stepCount = max(steps, 0)

            guard stepCount >= 1_000 else {
                return "\(stepCount)"
            }

            if stepCount >= 10_000 {
                return "\(stepCount / 1_000)k"
            }

            let roundedTenths = (stepCount + 50) / 100
            let wholeThousands = roundedTenths / 10
            let tenths = roundedTenths % 10

            if tenths == 0 {
                return "\(wholeThousands)k"
            }

            return "\(wholeThousands).\(tenths)k"
        }

        var standingDetailLabel: String {
            if let rank {
                return rankTotal > 0 ? "#\(rank) of \(rankTotal)" : "#\(rank)"
            }

            guard let ownClimbsPlacing else { return "Rank --" }

            let total = max(ownClimbsTotal, ownClimbsPlacing)
            return "\(Self.ordinalText(ownClimbsPlacing)) of your \(total)"
        }

        /// Spelled here rather than through the app's shared helper because the
        /// widget extension compiles this file and not that one.
        private static func ordinalText(_ value: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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

    var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = "ascendapp"
        components.host = "live-climb"
        components.queryItems = [
            URLQueryItem(name: "sessionID", value: sessionID),
            URLQueryItem(name: "climbID", value: climbID)
        ]
        return components.url
    }
}

enum LiveClimbActivityStatus: String, Codable, Hashable, Sendable {
    case recording
    case saving
    case finished
    case failed
    case ended
}
