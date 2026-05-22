import Foundation

struct LiveReplayLeaderboardSummary: Equatable, Sendable {
    let totalClimbers: Int
    let completedCount: Int
    let personalBestDurationSeconds: TimeInterval?
    let updatedAt: Date?

    init(
        totalClimbers: Int,
        completedCount: Int = 0,
        personalBestDurationSeconds: TimeInterval?,
        updatedAt: Date?
    ) {
        self.totalClimbers = max(totalClimbers, 0)
        self.completedCount = max(completedCount, 0)
        self.personalBestDurationSeconds = personalBestDurationSeconds
        self.updatedAt = updatedAt
    }

    static let empty = LiveReplayLeaderboardSummary(
        totalClimbers: 0,
        completedCount: 0,
        personalBestDurationSeconds: nil,
        updatedAt: nil
    )
}

struct LiveReplayCompletionRank: Equatable, Sendable {
    let rank: Int
    let completedCount: Int
    let updatedAt: Date?

    init(rank: Int, completedCount: Int, updatedAt: Date?) {
        self.rank = max(rank, 1)
        self.completedCount = max(completedCount, 1)
        self.updatedAt = updatedAt
    }
}

struct LiveReplayCompletionLeaderboard: Equatable, Sendable {
    let rows: [LiveReplayLeaderboardRow]
    let completedCount: Int
    let updatedAt: Date?

    init(
        rows: [LiveReplayLeaderboardRow],
        completedCount: Int,
        updatedAt: Date?
    ) {
        self.rows = rows
        self.completedCount = max(completedCount, rows.count, 0)
        self.updatedAt = updatedAt
    }

    static let empty = LiveReplayCompletionLeaderboard(
        rows: [],
        completedCount: 0,
        updatedAt: nil
    )
}

struct LiveReplayLeaderboardRow: Identifiable, Equatable, Sendable {
    let id: String
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
        userId: String? = nil
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

    static func currentUser(
        rank: Int?,
        steps: Int,
        avatarToken: String = "YOU",
        photoURL: URL? = nil,
        isPersonalBest: Bool = false
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
            userId: nil
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
        deltaFromUser: Int? = nil
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
            userId: userId
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
