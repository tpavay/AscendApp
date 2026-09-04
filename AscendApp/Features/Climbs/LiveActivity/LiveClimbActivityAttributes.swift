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
        /// The two travel together on purpose: an ordinal captioned `rank` names
        /// no population, and a number with no population beside it is the whole
        /// defect this pair exists to prevent. The compact slot holds one
        /// number, so the leaderboard placing leads and the personal placing is
        /// the one dropped - the finish card's own hierarchy.
        var standingValue: String {
            if let rank {
                return "#\(rank)"
            }

            guard let ownClimbsPlacing else { return "--" }
            return Self.ordinalText(ownClimbsPlacing)
        }

        /// The noun alone, never the count: this renders in the Dynamic Island's
        /// compact slot at 7pt in about 44 points of width, and `of 27 climbers`
        /// only fits there by scaling to illegibility. The figure is already on
        /// the value line directly above, so the caption naming the population
        /// is what makes that ordinal a labelled number rather than a bare one.
        var standingCaption: String {
            if rank != nil {
                return "climbers"
            }

            return ownClimbsPlacing == nil ? "rank" : "your climbs"
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
                return "#\(rank) of \(Self.climberField(max(rankTotal, rank)))"
            }

            return ownClimbsDetailLabel ?? "--"
        }

        /// The climber's own history, stated beneath the leaderboard placing
        /// where there is room for both - the Lock Screen and the expanded
        /// Dynamic Island - and nil where there is nothing measured to state.
        ///
        /// Where the climber is alone on the board this is the whole statement
        /// and `standingDetailLabel` carries it instead, so the two never appear
        /// twice on one surface.
        var standingSecondaryLabel: String? {
            rank == nil ? nil : ownClimbsDetailLabel
        }

        private var ownClimbsDetailLabel: String? {
            guard let ownClimbsPlacing else { return nil }

            let total = max(ownClimbsTotal, ownClimbsPlacing)
            return "\(Self.ordinalText(ownClimbsPlacing)) of your \(Self.climbField(total))"
        }

        /// Spelled here rather than through the app's shared helper because the
        /// widget extension compiles this file and not that one.
        private static func ordinalText(_ value: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        private static func climberField(_ count: Int) -> String {
            "\(count) climber\(count == 1 ? "" : "s")"
        }

        private static func climbField(_ count: Int) -> String {
            "\(count) climb\(count == 1 ? "" : "s")"
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
