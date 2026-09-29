import Foundation
import Observation

/// The race on the Mountain during one live session: who the climber chose to race, and every
/// ghost that choice puts on the stairs.
///
/// Everyone comes from the session's own leaderboard windows, so the stairs and the board can
/// never disagree about who is climbing; a filtered race reads each chosen climber's best from the
/// board by owner instead. The scene reads `ghosts` once per rendered frame; it is rebuilt only
/// when a window or a checkpoint arrives or a switch changes.
@MainActor
@Observable
final class AscendMountainRace {
    var selection = MountainRaceSelection() {
        didSet { rebuildGhosts() }
    }

    private(set) var field = MountainRaceField()
    @ObservationIgnored private var labels: [String: String] = [:]
    @ObservationIgnored private(set) var ghosts: [MountainGhost] = []
    /// This climb's own marks on the stairs: the gold line where the climber's best ended.
    @ObservationIgnored private(set) var markers: [MountainMarker] = []
    @ObservationIgnored private let goal: JustClimbGoal?
    @ObservationIgnored private let board: MountainRaceBoard?
    @ObservationIgnored private let filterStore: MountainRaceFilterRepository?
    @ObservationIgnored private let userId: String?
    /// Saves run one after another, each writing the difference from the server's copy.
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// Each chosen climber's best entry and how many buckets it ran, once looked up.
    @ObservationIgnored private var chosenBests: [String: MountainRaceBest] = [:]
    /// The last bucket each chosen climber was asked about, so a read happens once a bucket.
    @ObservationIgnored private var chosenReadBucket: [String: Int] = [:]
    @ObservationIgnored private var isRefreshingChosen = false

    /// - Parameters:
    ///   - goal: the session's goal, which decides where the best's line stands.
    ///   - board: where a chosen climber's best is read; nil races only the windows.
    ///   - filterStore: where the climber's chosen climbers are kept, for `userId`.
    init(
        goal: JustClimbGoal? = nil,
        board: MountainRaceBoard? = nil,
        filterStore: MountainRaceFilterRepository? = nil,
        userId: String? = nil
    ) {
        self.goal = goal
        self.board = board
        self.filterStore = filterStore
        self.userId = userId
    }

    /// Starts the climb with the climbers kept from the last one. A list that cannot be read
    /// races everyone, which is the default anyway.
    func loadChosen() async {
        guard let filterStore, let userId,
              let chosen = try? await filterStore.fetchChosen(userId: userId) else { return }
        selection.chosen = Array(chosen.prefix(MountainRaceSelection.chosenLimit))
    }

    /// Races the chosen climbers from now on and keeps them for every climb after. Returns the
    /// save, which runs behind the change.
    @discardableResult
    func choose(_ chosen: [String]) -> Task<Void, Never>? {
        selection.chosen = Array(chosen.prefix(MountainRaceSelection.chosenLimit))
        guard let filterStore, let userId else { return nil }
        let wanted = selection.chosen
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await filterStore.save(userId: userId, chosen: wanted)
            } catch {
                TelemetryManager.shared.recordError(error, context: .firestore, code: "mountain_race_filter_save_failed")
            }
        }
        return saving
    }

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

    /// Reads what is new about the chosen climbers at this bucket: each one's best the first time,
    /// then where it stood at the end of the bucket while it was still climbing. At most one read
    /// per chosen climber per bucket; one that fails is asked again next bucket.
    func refreshChosen(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        moderate: ([LiveReplayLeaderboardRow]) -> [ModeratedReplayLeaderboardRow]
    ) async {
        guard let board, selection.isFiltered, !isRefreshingChosen else { return }
        isRefreshingChosen = true
        defer { isRefreshingChosen = false }

        let interval = context.bucketIntervalSeconds
        for userId in selection.chosen where chosenReadBucket[userId] != bucketIndex {
            chosenReadBucket[userId] = bucketIndex
            if chosenBests[userId] == nil {
                guard let best = try? await board.raceBest(context: context, userId: userId) else { continue }
                chosenBests[userId] = best
                field.learnChosen(userId: userId, best: best.row, bucketIntervalSeconds: interval)
                for row in moderate([best.row]) {
                    labels[userId] = Self.tagLabel(for: row.identity)
                }
            }
            guard let best = chosenBests[userId], bucketIndex > 0,
                  (best.splitBucketCount ?? .max) > bucketIndex,
                  let steps = try? await board.stepsAtBucket(context: context, entryId: best.row.id, bucketIndex: bucketIndex) else {
                continue
            }
            field.recordChosen(userId: userId, steps: steps, bucketIndex: bucketIndex, bucketIntervalSeconds: interval)
        }
        rebuildGhosts()
    }

    private func rebuildGhosts() {
        ghosts = Self.ghosts(field: field, labels: labels, selection: selection)
        markers = selection.showsYourBest
            ? field.yourBest.flatMap { Self.bestLine(for: $0, goal: goal) }.map { [$0] } ?? []
            : []
    }

    /// The line the climber's best leaves on the stairs, settled by the captain as "the gold line
    /// plus your old self": on an open climb where it ended, on a timed one how far it had come by
    /// the time, and none on a step goal, whose finish is already the goal itself.
    nonisolated static func bestLine(for best: MountainRivalCurve, goal: JustClimbGoal?) -> MountainMarker? {
        let steps: Double
        switch goal?.kind ?? .open {
        case .open:
            steps = best.finalSteps
        case .duration:
            steps = best.steps(at: Double((goal?.durationMinutes ?? 0) * 60))
        case .steps:
            return nil
        }
        let count = Int(steps.rounded())
        guard count > 0 else { return nil }
        return MountainMarker(
            id: "your-best-line-\(count)",
            step: count,
            kind: .line,
            title: "YOUR BEST",
            subtitle: "\(count.formatted()) STEPS"
        )
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
            let racing = selection.isFiltered
                ? selection.chosen.compactMap { field.chosen[$0] }
                : field.climbers.values.sorted(by: { $0.id < $1.id })
            for climber in racing {
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
