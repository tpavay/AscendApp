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
        ///
        /// One optional pair rather than two fields: a Live Activity started by
        /// an older binary is still on the Lock Screen when the app updates, and
        /// a stored state missing this key has to decode as "nothing measured"
        /// rather than fail - a state that cannot decode is one `activities`
        /// omits and the manager can never end.
        var ownClimbs: OwnClimbsPlacing?
        /// Who else is on this board, as the session's standing settled it.
        ///
        /// This is what keeps "no rank to state" apart from "rank not resolved":
        /// both arrive with `rank` nil, and only the second is a `--`. Nil only
        /// on a state an older binary wrote, which reads as racing so its
        /// missing rank keeps rendering as unresolved.
        var board: Board?
        var durationSeconds: Int
        var progress: Double
        var status: LiveClimbActivityStatus
        var climbPhotoURLString: String?
        var updatedAt: Date

        struct OwnClimbsPlacing: Codable, Hashable, Sendable {
            var placing: Int
            var total: Int
        }

        enum Board: String, Codable, Hashable, Sendable {
            /// Other climbers have finished this board, so a leaderboard
            /// placing exists even where this state could not resolve it.
            case racing
            /// Nobody else has finished this board. There is no leaderboard
            /// placing to state, and nothing about that has failed.
            case alone
        }

        /// The one thing this surface may say about where the climber stands.
        ///
        /// Three states that must never share a glyph: a placing, a placing
        /// that could not be resolved (`--` is that, and only that), and a
        /// board with legitimately nothing to place against - a first-ever
        /// climber nobody else has raced. Rendering the third as the second
        /// told the one climber with no field at all that their rank had
        /// failed to load, for the whole climb.
        enum Standing: Hashable, Sendable {
            case rank(Int)
            case ownClimbs(OwnClimbsPlacing)
            case unresolved
            case nobodyElse
        }

        var standing: Standing {
            if board != .alone, let rank {
                return .rank(rank)
            }

            if let ownClimbs {
                return .ownClimbs(ownClimbs)
            }

            return board == .alone ? .nobodyElse : .unresolved
        }

        /// Present tense on purpose, unlike the finish card's frozen
        /// `NOBODY ELSE HAD FINISHED`: this is redrawn while the board is live
        /// and the session's own standing is what set it, so it is retired the
        /// tick somebody else finishes.
        static let nobodyElseCaption = "nobody else"
        static let nobodyElseDetail = "Nobody else has finished"
        static let fieldTitle = "Field"

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
        ///
        /// Nil where there is nothing to state: no ordinal, and no `--` either,
        /// because that glyph means a rank that could not be resolved and this
        /// one could not exist. The caption then carries the whole statement.
        var standingValue: String? {
            switch standing {
            case .rank(let rank):
                return "#\(rank)"
            case .ownClimbs(let ownClimbs):
                return Self.ordinalText(ownClimbs.placing)
            case .unresolved:
                return "--"
            case .nobodyElse:
                return nil
            }
        }

        /// The noun alone, never the count: this renders in the Dynamic Island's
        /// compact slot at 7pt in about 44 points of width, and `of 27 climbers`
        /// only fits there by scaling to illegibility. The figure is already on
        /// the value line directly above, so the caption naming the population
        /// is what makes that ordinal a labelled number rather than a bare one.
        var standingCaption: String {
            switch standing {
            case .rank:
                return "climbers"
            case .ownClimbs:
                return "your climbs"
            case .unresolved:
                return "rank"
            case .nobodyElse:
                return Self.nobodyElseCaption
            }
        }

        var standingTitle: String {
            switch standing {
            case .rank, .unresolved:
                return "Rank"
            case .ownClimbs:
                return "Your climbs"
            case .nobodyElse:
                return Self.fieldTitle
            }
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

        /// The Lock Screen and expanded-island value, or nil where there is
        /// nothing to state and the secondary line carries the statement alone.
        var standingDetailLabel: String? {
            switch standing {
            case .rank(let rank):
                return "#\(rank) of \(Self.climberField(max(rankTotal, rank)))"
            case .ownClimbs:
                return ownClimbsDetailLabel
            case .unresolved:
                return "--"
            case .nobodyElse:
                return nil
            }
        }

        /// The climber's own history, stated beneath the leaderboard placing
        /// where there is room for both - the Lock Screen and the expanded
        /// Dynamic Island - and nil where there is nothing measured to state.
        ///
        /// Where the climber is alone on the board this is the whole statement
        /// and `standingDetailLabel` carries it instead, so the two never appear
        /// twice on one surface. Where nobody else has finished and there is no
        /// history to place this run in, the line names that condition and
        /// nothing else.
        var standingSecondaryLabel: String? {
            switch standing {
            case .rank:
                return ownClimbsDetailLabel
            case .ownClimbs, .unresolved:
                return nil
            case .nobodyElse:
                return Self.nobodyElseDetail
            }
        }

        private var ownClimbsDetailLabel: String? {
            guard let ownClimbs else { return nil }

            let total = max(ownClimbs.total, ownClimbs.placing)
            return "\(Self.ordinalText(ownClimbs.placing)) of your \(Self.climbField(total))"
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
