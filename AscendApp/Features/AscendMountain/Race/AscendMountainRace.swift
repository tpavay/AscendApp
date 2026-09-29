import Foundation
import Observation

/// The race on the Mountain during one live session: who the climber chose to race, and every
/// ghost that choice puts on the stairs.
///
/// The session's leaderboard windows are the only input, so the stairs and the board can never
/// disagree about who is climbing. The scene reads `ghosts` once per rendered frame; it is
/// rebuilt only when a window arrives or a switch changes.
@MainActor
@Observable
final class AscendMountainRace {
    var selection = MountainRaceSelection() {
        didSet { rebuildGhosts() }
    }

    private(set) var field = MountainRaceField()
    @ObservationIgnored private var labels: [String: String] = [:]
    @ObservationIgnored private(set) var ghosts: [MountainGhost] = []

    /// Whether the climber has a previous best on this board to race.
    var hasYourBest: Bool {
        field.yourBest != nil
    }

    /// Folds in a window the session fetched. `identities` are the same rows through the shared
    /// moderation resolver, the only place a tag's name may come from.
    func ingest(_ window: LiveReplayLeaderboardWindow, identities: [ModeratedReplayLeaderboardRow]) {
        field.ingest(window)
        for row in identities {
            labels[row.userId ?? row.id] = Self.tagLabel(for: row.identity)
        }
        rebuildGhosts()
    }

    private func rebuildGhosts() {
        ghosts = Self.ghosts(field: field, labels: labels, selection: selection)
    }

    /// The ghosts a selection puts on the stairs, keyed by climber so each keeps one kit and one
    /// lane however many windows they appear in.
    nonisolated static func ghosts(
        field: MountainRaceField,
        labels: [String: String],
        selection: MountainRaceSelection
    ) -> [MountainGhost] {
        var ghosts: [MountainGhost] = []
        if selection.showsEveryone {
            for climber in field.climbers.values.sorted(by: { $0.id < $1.id }) {
                let id = ghostID(for: climber)
                let curve = climber.curve
                ghosts.append(MountainGhost(id: id, kind: .rival, label: labels[id] ?? "") { curve.steps(at: $0) })
            }
        }
        if selection.showsYourBest, let curve = field.yourBest {
            ghosts.append(MountainGhost(id: "your-best", kind: .personalBest, label: "YOUR BEST") { curve.steps(at: $0) })
        }
        if selection.showsPacer {
            ghosts.append(.pacer(stepsPerMinute: Double(selection.pacerStepsPerMinute)))
        }
        return ghosts
    }

    /// A climber is one ghost however their row is identified; a row with no climber behind it
    /// stands on its own id.
    nonisolated static func ghostID(for climber: MountainRaceField.Climber) -> String {
        climber.userId ?? climber.id
    }

    /// What a climber's tag says: their first name, from the moderated identity and nothing
    /// else. A hidden identity - blocked, or not yet cleared - wears no tag at all.
    nonisolated static func tagLabel(for identity: ResolvedUserIdentity) -> String {
        guard !identity.isHidden,
              let first = identity.displayName.split(whereSeparator: \.isWhitespace).first else { return "" }
        let name = first.uppercased()
        return name.count > 12 ? String(name.prefix(11)) + "…" : name
    }
}
