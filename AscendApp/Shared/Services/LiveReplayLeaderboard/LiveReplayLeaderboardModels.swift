import Foundation

struct LiveReplayLeaderboardSummary: Equatable, Sendable {
    let totalClimbers: Int
    let completedCount: Int
    let personalBestDurationSeconds: TimeInterval?
    let firstAscent: LiveReplayFirstAscent?
    let updatedAt: Date?

    init(
        totalClimbers: Int,
        completedCount: Int = 0,
        personalBestDurationSeconds: TimeInterval?,
        firstAscent: LiveReplayFirstAscent? = nil,
        updatedAt: Date?
    ) {
        self.totalClimbers = max(totalClimbers, 0)
        self.completedCount = max(completedCount, 0)
        self.personalBestDurationSeconds = personalBestDurationSeconds
        self.firstAscent = firstAscent
        self.updatedAt = updatedAt
    }

    static let empty = LiveReplayLeaderboardSummary(
        totalClimbers: 0,
        completedCount: 0,
        personalBestDurationSeconds: nil,
        firstAscent: nil,
        updatedAt: nil
    )
}

struct LiveReplayFirstAscent: Equatable, Sendable {
    let userId: String?
    let displayName: String
    let avatarToken: String
    let photoURL: URL?
    let completedAt: Date

    init(
        userId: String?,
        displayName: String,
        avatarToken: String,
        photoURL: URL?,
        completedAt: Date
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarToken = avatarToken
        self.photoURL = photoURL
        self.completedAt = completedAt
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct LiveReplayCompletionRank: Equatable, Sendable {
    /// Standard competition rank — one more than the number of strictly faster attempts.
    let rank: Int
    let completedCount: Int
    let updatedAt: Date?
    /// Whether another attempt shares this exact completion time, and so this rank.
    let isTied: Bool

    init(rank: Int, completedCount: Int, updatedAt: Date?, isTied: Bool = false) {
        self.rank = max(rank, 1)
        self.completedCount = max(completedCount, 1)
        self.updatedAt = updatedAt
        self.isTied = isTied
    }
}

struct LiveReplayCurrentUserCompletion: Equatable, Sendable {
    /// Standard competition rank — one more than the number of strictly faster attempts.
    let rank: Int
    let completedCount: Int
    let completionDurationSeconds: TimeInterval
    let workoutId: String
    let updatedAt: Date?
    /// Whether another attempt shares this exact completion time, and so this rank.
    let isTied: Bool

    init(
        rank: Int,
        completedCount: Int,
        completionDurationSeconds: TimeInterval,
        workoutId: String,
        updatedAt: Date?,
        isTied: Bool = false
    ) {
        self.rank = max(rank, 1)
        self.completedCount = max(completedCount, 1)
        self.completionDurationSeconds = max(completionDurationSeconds, 0)
        self.workoutId = workoutId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = updatedAt
        self.isTied = isTied
    }
}

struct LiveReplayCompletionRankSnapshot: Equatable, Sendable {
    let workoutId: String
    let rank: Int
    let completedCount: Int
    let completionDurationSeconds: TimeInterval
    let rankedAt: Date?
    let rankingMetric: String
    let tiePolicy: String

    init(
        workoutId: String,
        rank: Int,
        completedCount: Int,
        completionDurationSeconds: TimeInterval,
        rankedAt: Date?,
        rankingMetric: String,
        tiePolicy: String
    ) {
        self.workoutId = workoutId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rank = max(rank, 1)
        self.completedCount = max(completedCount, 1)
        self.completionDurationSeconds = max(completionDurationSeconds, 0)
        self.rankedAt = rankedAt
        self.rankingMetric = rankingMetric.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tiePolicy = tiePolicy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LiveReplayFinisherStatus: Equatable, Sendable {
    let globalCompletionOrder: Int
    let firstCompletedAt: Date?
    let bestCompletionDurationSeconds: TimeInterval?
    let updatedAt: Date?

    init(
        globalCompletionOrder: Int,
        firstCompletedAt: Date?,
        bestCompletionDurationSeconds: TimeInterval?,
        updatedAt: Date?
    ) {
        self.globalCompletionOrder = max(globalCompletionOrder, 1)
        self.firstCompletedAt = firstCompletedAt
        self.bestCompletionDurationSeconds = bestCompletionDurationSeconds
        self.updatedAt = updatedAt
    }
}

enum LiveReplayPublishState: String, Sendable {
    case publishing
    case published
    case failedRetryable = "failed_retryable"
}

struct LiveReplayPublishStatus: Equatable, Sendable {
    let state: LiveReplayPublishState
    let workoutId: String
    let userId: String?
    let contextType: String
    let contextId: String
    let rankAtCompletion: Int?
    let completedCountAtCompletion: Int?
    let finisherOrder: Int?
    let lastErrorCode: String?
    let lastErrorMessageSafe: String?
    let updatedAt: Date?
    let publishedAt: Date?

    init(
        state: LiveReplayPublishState,
        workoutId: String,
        userId: String?,
        contextType: String,
        contextId: String,
        rankAtCompletion: Int?,
        completedCountAtCompletion: Int?,
        finisherOrder: Int?,
        lastErrorCode: String?,
        lastErrorMessageSafe: String?,
        updatedAt: Date?,
        publishedAt: Date?
    ) {
        self.state = state
        self.workoutId = workoutId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.contextType = contextType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextId = contextId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rankAtCompletion = rankAtCompletion.map { max($0, 1) }
        self.completedCountAtCompletion = completedCountAtCompletion.map { max($0, 1) }
        self.finisherOrder = finisherOrder.map { max($0, 1) }
        self.lastErrorCode = lastErrorCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.lastErrorMessageSafe = lastErrorMessageSafe?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.updatedAt = updatedAt
        self.publishedAt = publishedAt
    }
}

struct LiveReplayCompletionLeaderboardCursor: Equatable, Sendable {
    /// Ranking value of the last fetched row - the Firestore pagination position. Its
    /// meaning follows the context's `LiveReplayRankingMetric`: seconds on a climb
    /// board, steps on a routine board. Both are carried as a `Double` so one
    /// continuation type serves either metric.
    let sortKey: Double
    let rowID: String
    /// Competition rank of the last ranked row. Carried so a tie group split across a
    /// page boundary keeps one rank instead of restarting at the next position.
    let lastRank: Int
    /// How many rows have been ranked across every page so far.
    let rankedCount: Int

    init(
        sortKey: Double,
        rowID: String,
        lastRank: Int,
        rankedCount: Int
    ) {
        self.sortKey = max(sortKey, 0)
        self.rowID = rowID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastRank = max(lastRank, 1)
        self.rankedCount = max(rankedCount, 0)
    }

    var rankingContinuation: CompetitionRanking.Continuation<Double> {
        CompetitionRanking.Continuation(
            lastKey: sortKey,
            lastRank: lastRank,
            rankedCount: rankedCount
        )
    }
}

struct LiveReplayCompletionLeaderboard: Equatable, Sendable {
    let rows: [LiveReplayLeaderboardRow]
    let completedCount: Int
    let updatedAt: Date?
    let nextCursor: LiveReplayCompletionLeaderboardCursor?

    /// Rows arrive already carrying their competition rank — only the repository knows
    /// the full ordering and the pagination continuation needed to assign one. Tie flags
    /// are derived here instead, so a tie group split across a page boundary corrects
    /// itself the moment `appending(_:)` merges the neighbouring page.
    init(
        rows: [LiveReplayLeaderboardRow],
        completedCount: Int,
        updatedAt: Date?,
        nextCursor: LiveReplayCompletionLeaderboardCursor? = nil
    ) {
        self.rows = Self.flaggingTies(in: rows)
        self.completedCount = max(completedCount, rows.count, 0)
        self.updatedAt = updatedAt
        self.nextCursor = nextCursor
    }

    private static func flaggingTies(
        in rows: [LiveReplayLeaderboardRow]
    ) -> [LiveReplayLeaderboardRow] {
        var countsByRank: [Int: Int] = [:]
        for rank in rows.compactMap(\.rank) {
            countsByRank[rank, default: 0] += 1
        }

        return rows.map { row in
            let isTied = row.rank.map { (countsByRank[$0] ?? 0) > 1 } ?? false
            return row.isTied == isTied ? row : row.updating(isTied: isTied)
        }
    }

    var hasMoreRows: Bool {
        nextCursor != nil
    }

    func appending(_ page: LiveReplayCompletionLeaderboard) -> LiveReplayCompletionLeaderboard {
        var seenRowIDs = Set(rows.map(\.id))
        let appendedRows = page.rows.filter { row in
            seenRowIDs.insert(row.id).inserted
        }

        return LiveReplayCompletionLeaderboard(
            rows: rows + appendedRows,
            completedCount: max(completedCount, page.completedCount),
            updatedAt: page.updatedAt ?? updatedAt,
            nextCursor: page.nextCursor
        )
    }

    static let empty = LiveReplayCompletionLeaderboard(
        rows: [],
        completedCount: 0,
        updatedAt: nil,
        nextCursor: nil
    )
}

struct LiveReplayLeaderboardRow: Identifiable, Equatable, Sendable {
    let id: String
    /// Standard competition rank ("1, 2, 2, 4") — tied rows share a rank.
    let rank: Int?
    let displayName: String
    let avatarToken: String
    let photoURL: URL?
    let stepsAtBucket: Int
    let finalSteps: Int
    let deltaFromUser: Int
    let isCurrentUser: Bool
    let isPersonalBest: Bool
    let completionDurationSeconds: TimeInterval?
    let userId: String?
    let gender: String?
    let age: Int?
    let locationCity: String?
    /// Whether at least one other row shares this rank.
    let isTied: Bool

    init(
        id: String,
        rank: Int?,
        displayName: String,
        avatarToken: String,
        photoURL: URL?,
        stepsAtBucket: Int,
        finalSteps: Int,
        deltaFromUser: Int,
        isCurrentUser: Bool,
        isPersonalBest: Bool,
        completionDurationSeconds: TimeInterval?,
        userId: String? = nil,
        gender: String? = nil,
        age: Int? = nil,
        locationCity: String? = nil,
        isTied: Bool = false
    ) {
        self.id = id
        self.rank = rank
        self.displayName = displayName
        self.avatarToken = avatarToken
        self.photoURL = photoURL
        self.stepsAtBucket = stepsAtBucket
        self.finalSteps = finalSteps
        self.deltaFromUser = deltaFromUser
        self.isCurrentUser = isCurrentUser
        self.isPersonalBest = isPersonalBest
        self.completionDurationSeconds = completionDurationSeconds
        self.userId = userId
        self.gender = Self.cleanedString(gender)
        self.age = Self.validAge(age)
        self.locationCity = Self.cleanedString(locationCity)
        self.isTied = isTied
    }


    var averageStepsPerMinute: Double? {
        guard let completionDurationSeconds,
              completionDurationSeconds > 0,
              finalSteps > 0 else {
            return nil
        }

        let value = Double(finalSteps) / (completionDurationSeconds / 60)
        return value.isFinite ? value : nil
    }

    var demographicSummaryText: String? {
        let parts = [
            genderAbbreviation,
            age.map(String.init),
            locationCity
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var genderAbbreviation: String? {
        switch gender?.lowercased() {
        case "man", "male", "m":
            return "M"
        case "woman", "female", "f":
            return "F"
        default:
            return nil
        }
    }

    static func currentUser(
        rank: Int?,
        steps: Int,
        avatarToken: String = "YOU",
        photoURL: URL? = nil,
        isPersonalBest: Bool = false,
        gender: String? = nil,
        age: Int? = nil,
        locationCity: String? = nil
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "current-user",
            rank: rank,
            displayName: "You",
            avatarToken: avatarToken,
            photoURL: photoURL,
            stepsAtBucket: max(steps, 0),
            finalSteps: max(steps, 0),
            deltaFromUser: 0,
            isCurrentUser: true,
            isPersonalBest: isPersonalBest,
            completionDurationSeconds: nil,
            userId: nil,
            gender: gender,
            age: age,
            locationCity: locationCity
        )
    }

    func projected(elapsedSeconds: Int, bucketElapsedSeconds: Int) -> LiveReplayLeaderboardRow {
        guard !isCurrentUser else { return self }

        let projectedSteps: Int
        if let completionDurationSeconds,
           completionDurationSeconds > 0,
           finalSteps > 0 {
            let progress = min(max(TimeInterval(elapsedSeconds) / completionDurationSeconds, 0), 1)
            projectedSteps = Int((Double(finalSteps) * progress).rounded())
        } else if finalSteps > stepsAtBucket {
            let fallbackDuration = fallbackReplayDurationSeconds(
                bucketElapsedSeconds: bucketElapsedSeconds
            )
            let progress = min(max(Double(elapsedSeconds) / fallbackDuration, 0), 1)
            projectedSteps = Int((Double(finalSteps) * progress).rounded())
        } else {
            projectedSteps = stepsAtBucket
        }

        return updating(
            stepsAtBucket: min(max(projectedSteps, stepsAtBucket), max(finalSteps, stepsAtBucket))
        )
    }

    func rebased(currentSteps: Int) -> LiveReplayLeaderboardRow {
        updating(
            rank: rank,
            deltaFromUser: stepsAtBucket - max(currentSteps, 0)
        )
    }

    func updating(
        rank: Int? = nil,
        stepsAtBucket: Int? = nil,
        deltaFromUser: Int? = nil,
        isTied: Bool? = nil
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: rank ?? self.rank,
            displayName: displayName,
            avatarToken: avatarToken,
            photoURL: photoURL,
            stepsAtBucket: stepsAtBucket ?? self.stepsAtBucket,
            finalSteps: finalSteps,
            deltaFromUser: deltaFromUser ?? self.deltaFromUser,
            isCurrentUser: isCurrentUser,
            isPersonalBest: isPersonalBest,
            completionDurationSeconds: completionDurationSeconds,
            userId: userId,
            gender: gender,
            age: age,
            locationCity: locationCity,
            isTied: isTied ?? self.isTied
        )
    }

    private func fallbackReplayDurationSeconds(bucketElapsedSeconds: Int) -> Double {
        if bucketElapsedSeconds > 0, stepsAtBucket > 0 {
            let observedSPM = Double(stepsAtBucket) / (Double(bucketElapsedSeconds) / 60)
            if observedSPM.isFinite, observedSPM > 0 {
                return max(Double(finalSteps) / observedSPM * 60, Double(bucketElapsedSeconds + 10))
            }
        }

        let defaultSyntheticSPM = 72.0
        return max(Double(finalSteps) / defaultSyntheticSPM * 60, 90)
    }

    private static func cleanedString(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }

        return cleaned
    }

    private static func validAge(_ value: Int?) -> Int? {
        guard let value,
              (13...120).contains(value) else {
            return nil
        }

        return value
    }
}

struct LiveReplayLeaderboardWindow: Equatable, Sendable {
    let context: LiveReplayLeaderboardContext
    let bucketIndex: Int
    let currentSteps: Int
    let fetchedAt: Date
    let rows: [LiveReplayLeaderboardRow]
    let currentUserRank: Int?
    let totalClimbers: Int

    var bucketElapsedSeconds: Int {
        bucketIndex * context.bucketIntervalSeconds
    }

    func locallyRankedRows(
        currentSteps liveCurrentSteps: Int,
        currentElapsedSeconds: Int
    ) -> [LiveReplayLeaderboardRow] {
        let clampedCurrentSteps = max(liveCurrentSteps, 0)
        let projectedCompetitorRows = rows.map {
            $0.projected(
                elapsedSeconds: currentElapsedSeconds,
                bucketElapsedSeconds: bucketElapsedSeconds
            )
        }
        let crossedFetchedAheadRows = zip(rows, projectedCompetitorRows)
            .filter { originalRow, projectedRow in
                originalRow.stepsAtBucket >= currentSteps &&
                    projectedRow.stepsAtBucket < clampedCurrentSteps
            }
            .count
        let passedByFetchedBehindRows = zip(rows, projectedCompetitorRows)
            .filter { originalRow, projectedRow in
                originalRow.stepsAtBucket < currentSteps &&
                    projectedRow.stepsAtBucket >= clampedCurrentSteps
            }
            .count
        let adjustedCurrentRank = currentUserRank.map {
            max($0 - crossedFetchedAheadRows + passedByFetchedBehindRows, 1)
        }
        let currentUserRow = LiveReplayLeaderboardRow.currentUser(
            rank: adjustedCurrentRank,
            steps: clampedCurrentSteps
        )
        let competitorRows = projectedCompetitorRows.map {
            $0.rebased(currentSteps: clampedCurrentSteps)
        }
        let orderedRows = (competitorRows + [currentUserRow])
            .sorted(by: Self.sortRowsByLivePosition)

        guard let adjustedCurrentRank,
              let currentUserIndex = orderedRows.firstIndex(where: \.isCurrentUser) else {
            return orderedRows
        }

        return orderedRows.enumerated().map { offset, row in
            row.updating(
                rank: max(adjustedCurrentRank + offset - currentUserIndex, 1)
            )
        }
    }

    private static func sortRowsByLivePosition(
        _ lhs: LiveReplayLeaderboardRow,
        _ rhs: LiveReplayLeaderboardRow
    ) -> Bool {
        if lhs.stepsAtBucket != rhs.stepsAtBucket {
            return lhs.stepsAtBucket > rhs.stepsAtBucket
        }

        if lhs.isCurrentUser != rhs.isCurrentUser {
            return rhs.isCurrentUser
        }

        return (lhs.rank ?? Int.max) < (rhs.rank ?? Int.max)
    }

    func needsFreshWindow(
        currentSteps liveCurrentSteps: Int,
        currentElapsedSeconds: Int
    ) -> Bool {
        let minimumBufferedRowsPerSide = 1
        let rankedRows = locallyRankedRows(
            currentSteps: liveCurrentSteps,
            currentElapsedSeconds: currentElapsedSeconds
        )
        guard let currentUserIndex = rankedRows.firstIndex(where: \.isCurrentUser),
              let currentUserRank = rankedRows[currentUserIndex].rank else {
            return false
        }

        if let fetchedCurrentUserRank = self.currentUserRank,
           currentUserRank != fetchedCurrentUserRank {
            return true
        }

        let visibleRowsAhead = rankedRows[..<currentUserIndex]
            .filter { !$0.isCurrentUser }
            .count
        let visibleRowsBehind = rankedRows[rankedRows.index(after: currentUserIndex)...]
            .filter { !$0.isCurrentUser }
            .count

        let hasKnownRowsAhead = currentUserRank > 1 || rows.contains { row in
            guard let rowRank = row.rank,
                  let fetchedCurrentUserRank = self.currentUserRank else {
                return row.stepsAtBucket >= currentSteps
            }

            return rowRank < fetchedCurrentUserRank
        }
        let hasKnownRowsBehind = currentUserRank < totalClimbers || rows.contains { row in
            guard let rowRank = row.rank,
                  let fetchedCurrentUserRank = self.currentUserRank else {
                return row.stepsAtBucket < currentSteps
            }

            return rowRank > fetchedCurrentUserRank
        }

        if hasKnownRowsAhead && visibleRowsAhead <= minimumBufferedRowsPerSide {
            return true
        }

        if hasKnownRowsBehind && visibleRowsBehind <= minimumBufferedRowsPerSide {
            return true
        }

        return false
    }
}
