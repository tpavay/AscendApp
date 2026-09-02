import Foundation
import os.lock
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

final class FirestoreLiveReplayLeaderboardRepository: LiveReplayLeaderboardRepository, @unchecked Sendable {
    static let shared = FirestoreLiveReplayLeaderboardRepository()

    /// The climber's own entry on one board at one bucket.
    ///
    /// Only the latest bucket is kept: a race walks forward and never asks for a
    /// bucket it has left behind, so a dictionary would only grow.
    ///
    /// Unlike this repository's public board reads, this holds one climber's own
    /// data, so the key names the owner and `clearAccountScopedCaches()` empties
    /// it the moment a session ends.
    private struct OwnPreviousCompletionCache: Sendable {
        let key: String
        let row: LiveReplayLeaderboardRow?
    }

    private let db = Firestore.firestore()
    private let ownPreviousCompletionCache =
        OSAllocatedUnfairLock<OwnPreviousCompletionCache?>(initialState: nil)
    private let finishedRowDiagnostics = OSAllocatedUnfairLock(
        initialState: LiveReplayFinishedRowDiagnostics()
    )
    /// `"{uid}__{contextKey}"` for every board this climber is known to already
    /// stand in. See `optionalCurrentUserIsFinisher`.
    private let knownFinisherClimbers = OSAllocatedUnfairLock(
        initialState: Set<String>()
    )

    private init() {}

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        let snapshot = try await leaderboardDocument(context: context).getDocument(source: .server)
        guard let data = snapshot.data() else {
            return .empty
        }

        return LiveReplayLeaderboardSummary(
            totalClimbers: intValue(for: "totalClimbers", in: data) ?? 0,
            completedCount: intValue(for: "completedCount", in: data) ?? 0,
            personalBestDurationSeconds: doubleValue(for: "personalBestDurationSeconds", in: data),
            firstAscent: firstAscentValue(in: data),
            updatedAt: timestampValue(for: "updatedAt", in: data)
        )
    }

    /// The standing this attempt holds on the board as it stands right now.
    ///
    /// Counts climbers on every board: one document per climber from the
    /// `finishers` subcollection, taken at their standing best, so a rival's
    /// five faster attempts are one climber ahead and the denominator names the
    /// same people the numerator counted. The hero takes its noun from the same
    /// `recomputedFieldPopulation`, so a recomputed "of N" cannot name a
    /// population it did not count.
    ///
    /// Not the entry rows: `just_climb` and `routine` boards carry no
    /// `isBestForUser` flag at all, so a filter over their entries matches
    /// nothing and would report every climber first of one. Finishers are
    /// maintained on every context type, which is why they are the one field
    /// this side counts.
    ///
    /// The rank still belongs to *this* climb's own time; `ownLeadingRowCount`
    /// says why.
    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        try await climberCompletionRank(
            context: context,
            attemptRankingValue: rankingValue(
                context: context,
                completionDurationSeconds: completionDurationSeconds,
                finalSteps: finalSteps
            )
        )
    }

    /// The population a recomputed standing counts on this board.
    ///
    /// The `.current` basis' half of the invariant the hero's field line
    /// asserts: it resolves from the one property the hero takes its noun from,
    /// so a recomputed "of N" cannot name a population it did not count.
    static func recomputedFieldPopulation(
        for context: LiveReplayLeaderboardContext
    ) -> LiveReplayFieldPopulation {
        context.type.recomputedFieldPopulation
    }

    /// The standing a climber holds among the climbers of their board.
    ///
    /// Pure so the arithmetic is checkable without a Firestore behind it. The
    /// climber joins the field only when they hold no completion on it yet, and
    /// the rank can never outrun the population it was measured against.
    ///
    /// `betterClimberCount` arrives with the climber's own leading finisher
    /// already removed. Both operands are read from the one finishers
    /// collection, so that subtraction can only ever take out a document the
    /// count really included - and it is floored anyway, because a count of
    /// rivals ahead has no negative value and "#0" would state a placement
    /// nobody holds.
    static func climberStanding(
        betterClimberCount: Int,
        raceFieldCount: Int,
        climberAlreadyInField: Bool
    ) -> LiveReplayCompletionRank {
        let climbersAhead = max(betterClimberCount, 0)
        let completedCount = max(
            raceFieldCount + (climberAlreadyInField ? 0 : 1),
            climbersAhead + 1
        )

        return LiveReplayCompletionRank(
            rank: min(climbersAhead + 1, completedCount),
            completedCount: completedCount,
            updatedAt: nil
        )
    }

    /// Whether the climber's own finisher document stands ahead of this attempt.
    ///
    /// The client half of the server's `ownLeadingFinisherCount`, and it exists
    /// for the same reason: a board that shows one row per climber must never
    /// seat a climber behind themselves, so their own leading row is removed
    /// from the count of climbers ahead of this attempt.
    ///
    /// The rank still belongs to *this climb's own time* - each completion
    /// summary is a permanent record of the climb it sits on, so a 9:40 shows
    /// the rank a 9:40 earned and an 8:12 shows the rank an 8:12 earned. Ranking
    /// on the climber's all-time best instead would tell a climber their slower
    /// run came first on a board somebody beat that run on.
    static func ownLeadingRowCount(
        metric: LiveReplayRankingMetric,
        storedBest: Double?,
        attemptRankingValue: Double
    ) -> Int {
        guard let storedBest else { return 0 }

        let leads = metric.ranksHighestFirst
            ? storedBest > attemptRankingValue
            : storedBest < attemptRankingValue
        return leads ? 1 : 0
    }

    /// One row per climber, on their standing best.
    ///
    /// The field is the `finishers` subcollection - one document per climber by
    /// construction, written in the same transaction as the row it stands for,
    /// and maintained on every context type. It is also the collection the
    /// server's collapsing numerator counts, so a recomputed standing and the
    /// stamp that will replace it measure the same field rather than two that
    /// only agree eventually.
    ///
    /// Both halves come out of that one collection: the climber's own stored
    /// best is read from their own finisher document, so the row the count
    /// included and the row the subtraction removes are the same row. The
    /// climber joins the field only if they are not already standing in it,
    /// which is a question about the *climber*, not about whether this
    /// particular attempt published.
    private func climberCompletionRank(
        context: LiveReplayLeaderboardContext,
        attemptRankingValue: Double
    ) async throws -> LiveReplayCompletionRank {
        let finisher = try await currentUserFinisher(context: context)
        let ownLeadingRows = Self.ownLeadingRowCount(
            metric: context.type.rankingMetric,
            storedBest: finisher?.storedBest,
            attemptRankingValue: attemptRankingValue
        )

        async let betterClimberCount = countFinishersBetterThan(
            context: context,
            rankingValue: attemptRankingValue
        )
        async let climberFieldCount = countFinishers(context: context)

        return Self.climberStanding(
            betterClimberCount: try await betterClimberCount - ownLeadingRows,
            raceFieldCount: try await climberFieldCount,
            climberAlreadyInField: finisher != nil
        )
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        let resolvedWorkoutId = workoutId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedWorkoutId.isEmpty == false else {
            return nil
        }

        let snapshot = try await completionSnapshotDocument(
            context: context,
            workoutId: resolvedWorkoutId
        )
        .getDocument(source: .server)

        guard let data = snapshot.data(),
              let rank = intValue(for: "rank", in: data),
              let completedCount = intValue(for: "completedCount", in: data),
              let completionDurationSeconds = doubleValue(
                for: "completionDurationSeconds",
                in: data
              ) else {
            return nil
        }

        return LiveReplayCompletionRankSnapshot(
            workoutId: stringValue(for: "workoutId", in: data) ?? resolvedWorkoutId,
            rank: rank,
            completedCount: completedCount,
            completionDurationSeconds: completionDurationSeconds,
            rankedAt: timestampValue(for: "rankedAt", in: data),
            rankingMetric: stringValue(for: "rankingMetric", in: data) ?? "completionDurationSeconds",
            tiePolicy: stringValue(for: "tiePolicy", in: data) ?? "competition_rank_equal_durations_share_rank"
        )
    }

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return nil
        }

        let resolvedWorkoutId = workoutId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedWorkoutId.isEmpty == false else {
            return nil
        }

        let snapshot = try await publishStatusDocument(
            userId: uid,
            workoutId: resolvedWorkoutId
        )
        .getDocument(source: .server)

        guard let data = snapshot.data(),
              let rawState = stringValue(for: "state", in: data),
              let state = LiveReplayPublishState(rawValue: rawState) else {
            return nil
        }

        return LiveReplayPublishStatus(
            state: state,
            workoutId: stringValue(for: "workoutId", in: data) ?? resolvedWorkoutId,
            userId: stringValue(for: "userId", in: data),
            contextType: stringValue(for: "contextType", in: data) ?? "",
            contextId: stringValue(for: "contextId", in: data) ?? "",
            rankAtCompletion: intValue(for: "rankAtCompletion", in: data),
            completedCountAtCompletion: intValue(for: "completedCountAtCompletion", in: data),
            finisherOrder: intValue(for: "finisherOrder", in: data),
            lastErrorCode: stringValue(for: "lastErrorCode", in: data),
            lastErrorMessageSafe: stringValue(for: "lastErrorMessageSafe", in: data),
            updatedAt: timestampValue(for: "updatedAt", in: data),
            publishedAt: timestampValue(for: "publishedAt", in: data)
        )
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return nil
        }

        let metric = context.type.rankingMetric
        let bestDocument = try await currentUserBestCompletionDocument(context: context)

        guard let bestDocument,
              let completionDurationSeconds = doubleValue(
                for: "completionDurationSeconds",
                in: bestDocument.data()
              ) else {
            return nil
        }

        let bestRankingValue = rankingValue(for: metric, in: bestDocument.data())

        async let betterCompletionCount = countRowsBetterThan(
            context: context,
            rankingValue: bestRankingValue
        )
        async let publishedCompletionCount = countRows(
            context: context,
            bucketIndex: 0
        )
        async let tiedCompletionCount = countRowsMatching(
            context: context,
            rankingValue: bestRankingValue
        )

        let betterCount = try await betterCompletionCount
        let publishedCount = try await publishedCompletionCount
        let tiedCount = try await tiedCompletionCount
        let completedCount = max(publishedCount, betterCount + 1)

        return LiveReplayCurrentUserCompletion(
            rank: min(betterCount + 1, completedCount),
            completedCount: completedCount,
            completionDurationSeconds: completionDurationSeconds,
            workoutId: stringValue(for: "workoutId", in: bestDocument.data()) ?? bestDocument.documentID,
            updatedAt: timestampValue(for: "updatedAt", in: bestDocument.data()),
            isTied: tiedCount > 1
        )
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return nil
        }

        let snapshot = try await finisherDocument(context: context, userId: uid)
            .getDocument(source: .server)
        guard let data = snapshot.data(),
              let globalCompletionOrder = intValue(for: "globalCompletionOrder", in: data) else {
            return nil
        }

        return LiveReplayFinisherStatus(
            globalCompletionOrder: globalCompletionOrder,
            firstCompletedAt: timestampValue(for: "firstCompletedAt", in: data),
            bestCompletionDurationSeconds: doubleValue(for: "bestCompletionDurationSeconds", in: data),
            updatedAt: timestampValue(for: "updatedAt", in: data)
        )
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        let resolvedLimit = max(limit, 1)
        let metric = context.type.rankingMetric
        // Document ID is the immutable workout ID, so it is the deterministic tiebreak
        // that keeps rows tied on the metric in one stable order across every fetch.
        var query: Query = entriesCollection(context: context, bucketIndex: 0)
            .order(by: metric.field, descending: metric.ranksHighestFirst)
            .order(by: FieldPath.documentID(), descending: false)

        if let cursor {
            query = query.start(after: [
                cursor.sortKey,
                cursor.rowID
            ])
        }

        query = query.limit(to: resolvedLimit)

        let source: FirestoreSource = forceRefresh ? .server : .default

        async let summary = fetchSummary(context: context)
        async let rowSnapshot = query.getDocuments(source: source)

        let resolvedSummary = try await summary
        let resolvedCompletedCount: Int
        if cursor == nil {
            resolvedCompletedCount = try await countRows(context: context, bucketIndex: 0)
        } else {
            resolvedCompletedCount = 0
        }

        let snapshot = try await rowSnapshot
        let currentUserId = Auth.auth().currentUser?.uid

        // Rank on the raw metric value, matching the server's strict better-than
        // narrowing in functions/src/liveReplayLeaderboard.ts (leadingRows) - and so
        // matching the pinned row, which derives its rank from countRowsBetterThan.
        let rankable = snapshot.documents.compactMap { document -> RankableCompletion? in
            guard doubleValue(
                for: "completionDurationSeconds",
                in: document.data()
            ) != nil else {
                return nil
            }

            return RankableCompletion(
                id: document.documentID,
                data: document.data(),
                rankingValue: rankingValue(for: metric, in: document.data())
            )
        }

        let ranks = CompetitionRanking.ranks(
            for: rankable,
            continuing: cursor?.rankingContinuation,
            key: \.rankingValue
        )
        let rows = zip(rankable, ranks).compactMap { completion, rank in
            parseCompletionRow(
                id: completion.id,
                data: completion.data,
                rank: rank,
                currentUserId: currentUserId
            )
        }
        let completedCount = max(
            resolvedCompletedCount,
            (cursor?.rankedCount ?? 0) + rows.count
        )

        return LiveReplayCompletionLeaderboard(
            rows: rows,
            completedCount: completedCount,
            updatedAt: resolvedSummary.updatedAt,
            nextCursor: nextCompletionLeaderboardCursor(
                documents: snapshot.documents,
                metric: metric,
                rows: rows,
                rankedCount: (cursor?.rankedCount ?? 0) + rows.count,
                completedCount: completedCount,
                pageSize: resolvedLimit
            )
        )
    }

    private struct RankableCompletion {
        let id: String
        let data: [String: Any]
        /// The value this row is ranked on, in the context's own metric.
        let rankingValue: Double
    }

    /// Reads a stored entry's value for one metric, or nil when the ranking field is
    /// absent. Used as a pagination position, where a sentinel would encode an empty
    /// start-after page and silently truncate the board.
    private func optionalRankingValue(
        for metric: LiveReplayRankingMetric,
        in data: [String: Any]
    ) -> Double? {
        switch metric {
        case .fastestCompletion:
            return doubleValue(for: "completionDurationSeconds", in: data)
        case .mostSteps:
            return intValue(for: "finalSteps", in: data).map(Double.init)
        }
    }

    /// Reads a stored entry's value for one metric. A missing value sorts last in either
    /// direction so a malformed row can never outrank a real completion.
    private func rankingValue(
        for metric: LiveReplayRankingMetric,
        in data: [String: Any]
    ) -> Double {
        optionalRankingValue(for: metric, in: data)
            ?? (metric.ranksHighestFirst ? -1 : .greatestFiniteMagnitude)
    }

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow {
        let currentUserId = Auth.auth().currentUser?.uid
        async let summary = fetchSummary(context: context)
        async let runningAheadRows = fetchRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .ahead,
            limit: rowsAhead,
            currentUserId: currentUserId
        )
        // Optional on purpose. The finished half needs a composite index the
        // running half does not, so if that index is ever missing the board
        // loses the rivals already home rather than failing mid-climb - which
        // is the behaviour it had before this read existed, not a worse one.
        async let finishedAheadRows = optionalFetchFinishedRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .ahead,
            limit: rowsAhead,
            currentUserId: currentUserId
        )
        async let standing = windowStanding(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps
        )
        async let behindRows = fetchRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .behind,
            limit: rowsBehind,
            currentUserId: currentUserId
        )
        async let ownPreviousCompletion = optionalOwnPreviousCompletionRow(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps
        )
        async let finishedBehindRows = optionalFetchFinishedRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .behind,
            limit: rowsBehind,
            currentUserId: currentUserId
        )

        let resolvedSummary = try await summary
        let fetchedRunningAheadRows = try await runningAheadRows
        let fetchedFinishedAheadRows = await finishedAheadRows
        let rowsAhead = Self.mergedAheadRows(
            running: fetchedRunningAheadRows,
            finished: fetchedFinishedAheadRows,
            limit: rowsAhead,
            metric: context.type.rankingMetric
        )
        let ownPreviousCompletionRow = await ownPreviousCompletion
        let fetchedRunningBehindRows = try await behindRows
        let fetchedFinishedBehindRows = await finishedBehindRows
        let rowsBehind = Self.mergedBehindRows(
            running: fetchedRunningBehindRows,
            finished: fetchedFinishedBehindRows,
            limit: rowsBehind,
            metric: context.type.rankingMetric
        )
        let resolvedStanding = await standing
        let currentUserRank = Self.aheadCount(
            running: resolvedStanding.runningAheadCount,
            finished: resolvedStanding.finishedAheadCount,
            fetchedRows: rowsAhead
        ) + 1
        let totalClimbers = max(
            resolvedSummary.totalClimbers + resolvedStanding.joiningClimber,
            currentUserRank
        )

        let rankedAheadRows = rankedAheadRows(
            Array(rowsAhead.reversed()),
            currentUserRank: currentUserRank
        )
        let rankedBehindRows = rankedBehindRows(
            rowsBehind,
            currentUserRank: currentUserRank
        )

        return LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: max(currentSteps, 0),
            fetchedAt: Date(),
            rows: rankedAheadRows + rankedBehindRows,
            currentUserRank: currentUserRank,
            totalClimbers: totalClimbers,
            ownPreviousCompletionRow: ownPreviousCompletionRow
        )
    }

    /// A live window's rank and the denominator it is measured against.
    ///
    /// One shape on every board. Each ghost carries `isBestForUser` and so
    /// stands for exactly one climber, so counting the ghosts ahead at this
    /// bucket already counts people, and the summary's distinct-climber count
    /// is the field they were counted out of.
    private struct WindowStanding {
        let runningAheadCount: Int?
        let finishedAheadCount: Int?
        /// A climber joins the field only when they hold no completion on it
        /// yet - a question about the climber, never inferred from a count.
        let joiningClimber: Int
    }

    /// Resolves the rank and denominator a live window reports.
    ///
    /// Ranked on what the window itself measures at this bucket - position among
    /// the rows beside it - and never on a finishers read. A finishers read
    /// answers a question about a *finished* attempt, so mid-race it compares a
    /// climber against the elapsed session clock: they would start first and
    /// slide down as time passed, with performance playing no part.
    ///
    /// Settled by the captain on 2026-09-02: all three board types race off one
    /// mechanism. The server writes `isBestForUser` on every context now, so the
    /// ghosts are one row per climber at their best everywhere and both halves
    /// of this pair count climbers without a second query shape.
    private func windowStanding(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async -> WindowStanding {
        async let runningAheadCount = optionalCountRowsAhead(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps
        )
        async let finishedAheadCount = optionalCountFinishedRowsAhead(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps
        )
        async let alreadyInField = optionalCurrentUserIsFinisher(context: context)

        return WindowStanding(
            runningAheadCount: await runningAheadCount,
            finishedAheadCount: await finishedAheadCount,
            joiningClimber: (await alreadyInField) ? 0 : 1
        )
    }

    private enum WindowDirection {
        case ahead
        case behind
    }

    private func fetchRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        direction: WindowDirection,
        limit: Int,
        currentUserId: String?
    ) async throws -> [LiveReplayLeaderboardRow] {
        guard limit > 0 else { return [] }

        let collection = liveRaceEntries(context: context, bucketIndex: bucketIndex)
        let query: Query

        switch direction {
        case .ahead:
            query = collection
                .whereField("stepsAtBucket", isGreaterThanOrEqualTo: currentSteps)
                .order(by: "stepsAtBucket", descending: false)
                .limit(to: limit)
        case .behind:
            query = collection
                .whereField("stepsAtBucket", isLessThan: currentSteps)
                .order(by: "stepsAtBucket", descending: true)
                .limit(to: limit)
        }

        let snapshot = try await query.getDocuments(source: .server)
        return snapshot.documents.compactMap { document in
            parseRow(
                id: document.documentID,
                data: document.data(),
                currentSteps: currentSteps,
                currentUserId: currentUserId
            )
        }
    }

    /// The signed-in climber's id, but only on a board that collapses repeat
    /// finishers.
    ///
    /// That allowlist is the whole scope of the previous-best marker: a per-climb
    /// or per-routine-template board races one row per climber, so a row of the
    /// climber's own is their previous best. Just Climb and a plain routine race
    /// every completed attempt as its own opponent, and withdrawing the climber's
    /// own attempts there would delete rivals the board is meant to hold.
    private func collapsingBoardUserId(
        context: LiveReplayLeaderboardContext
    ) -> String? {
        guard context.type.collapsesRepeatFinishers else { return nil }
        return Auth.auth().currentUser?.uid
    }

    /// The climber's own entry on this board, read straight by owner rather than
    /// hoped for inside the fetched page.
    ///
    /// The window holds at most eight rows either side of the climber, so a
    /// previous best further away than that used to vanish from the board and
    /// take the `BEST` marker with it mid-race. A collapsing board stores exactly
    /// one entry per climber, so this is a single-document read that always finds
    /// it - and it is what the rank and the field size are corrected by.
    private func fetchOwnPreviousCompletionRow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async throws -> LiveReplayLeaderboardRow? {
        guard let currentUserId = collapsingBoardUserId(context: context) else {
            return nil
        }

        let snapshot = try await liveRaceEntries(context: context, bucketIndex: bucketIndex)
            .whereField("userId", isEqualTo: currentUserId)
            .limit(to: 1)
            .getDocuments(source: .server)

        return snapshot.documents.lazy.compactMap { document in
            self.parseRow(
                id: document.documentID,
                data: document.data(),
                currentSteps: currentSteps,
                currentUserId: currentUserId
            )
        }.first
    }

    /// The same read, served from the last bucket's answer where it still applies.
    ///
    /// A completion published before this session started cannot move inside a
    /// bucket, and the marker's motion between buckets is `projected(...)` on the
    /// client rather than a re-read - so the periodic refresh, which runs more
    /// often than the bucket advances, was paying for the same document twice.
    /// Only the row's gap to the live climber is re-derived. A read that failed is
    /// never cached, so the next refresh tries again.
    private func optionalOwnPreviousCompletionRow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async -> LiveReplayLeaderboardRow? {
        guard let currentUserId = collapsingBoardUserId(context: context) else {
            return nil
        }

        let key = "\(currentUserId)|\(context.contextKey)|\(max(bucketIndex, 0))"
        if let cached = ownPreviousCompletionCache.withLock({ $0 }), cached.key == key {
            return cached.row?.rebased(currentSteps: currentSteps)
        }

        do {
            let row = try await fetchOwnPreviousCompletionRow(
                context: context,
                bucketIndex: bucketIndex,
                currentSteps: currentSteps
            )
            ownPreviousCompletionCache.withLock {
                $0 = OwnPreviousCompletionCache(key: key, row: row)
            }
            return row
        } catch {
            return nil
        }
    }

    /// Drops everything this repository holds on behalf of one climber.
    ///
    /// A signed-in uid in the cache key stops the next account reading this one's
    /// row, but it leaves it resident in a process-wide singleton that outlives
    /// the store wipe - so the session's end empties it as well.
    func clearAccountScopedCaches() {
        ownPreviousCompletionCache.withLock { $0 = nil }
    }

    /// The attempts that have already finished by this bucket, each held at the
    /// step count it finished on.
    ///
    /// A published attempt writes one entry per bucket it ran for and not one
    /// more, so from the bucket after it completes it is absent from the board
    /// entirely. Reading only the current bucket therefore erased every rival
    /// who had already finished - the climber's own earlier completion first of
    /// all - and promoted the attempt still running to first place. A finisher
    /// does not leave the race; it holds its final steps for the rest of it.
    ///
    /// Both sides of the window need it. A landmark climb hides the behind half
    /// of the defect, because every completion is at or past the target and so
    /// stands ahead until the climber overshoots; an open Just Climb has no
    /// target at all, so a rival who stopped at 200 steps vanishes the moment
    /// the climber passes 200 - the same disappearance, below the row instead of
    /// above it.
    private func finishedRowsQuery(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        direction: WindowDirection
    ) -> Query {
        // `splitBucketCount` is the exact count of buckets an entry was written
        // to, so this predicate is the precise complement of "present in this
        // bucket": no attempt can be read as both running and finished, and none
        // can fall between the two.
        let finished = liveRaceEntries(context: context, bucketIndex: 0)
            .whereField("splitBucketCount", isLessThanOrEqualTo: bucketIndex)

        switch direction {
        case .ahead:
            return finished
                .whereField("finalSteps", isGreaterThanOrEqualTo: currentSteps)
                .order(by: "finalSteps", descending: false)
                .order(by: "splitBucketCount", descending: false)
        case .behind:
            return finished
                .whereField("finalSteps", isLessThan: currentSteps)
                .order(by: "finalSteps", descending: true)
                .order(by: "splitBucketCount", descending: true)
        }
    }

    private func fetchFinishedRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        direction: WindowDirection,
        limit: Int,
        currentUserId: String?
    ) async throws -> [LiveReplayLeaderboardRow] {
        guard limit > 0, bucketIndex > 0 else { return [] }

        let snapshot = try await finishedRowsQuery(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: direction
        )
        .limit(to: limit)
        .getDocuments(source: .server)

        return snapshot.documents.compactMap { document in
            parseRow(
                id: document.documentID,
                data: document.data(),
                currentSteps: currentSteps,
                currentUserId: currentUserId
            )?.holdingFinalSteps(currentSteps: currentSteps)
        }
    }

    private func countFinishedRowsAhead(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async throws -> Int {
        guard bucketIndex > 0 else { return 0 }

        let snapshot = try await finishedRowsQuery(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .ahead
        )
        .count
        .getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// A window row and whether it is already home, which steps alone cannot say.
    private struct MergeableRow {
        let row: LiveReplayLeaderboardRow
        let isFinished: Bool
    }

    private static func mergeable(
        running: [LiveReplayLeaderboardRow],
        finished: [LiveReplayLeaderboardRow]
    ) -> [MergeableRow] {
        running.map { MergeableRow(row: $0, isFinished: false) } +
            finished.map { MergeableRow(row: $0, isFinished: true) }
    }

    /// The value a window row is ranked on, in the board's own metric. A row
    /// carrying no value for it sorts last in either direction, so a running
    /// attempt can never borrow a rank from a number it has not produced.
    private static func windowRankingValue(
        _ row: LiveReplayLeaderboardRow,
        metric: LiveReplayRankingMetric
    ) -> Double {
        switch metric {
        case .fastestCompletion:
            return row.completionDurationSeconds ?? .greatestFiniteMagnitude
        case .mostSteps:
            return Double(row.finalSteps)
        }
    }

    /// Whether `lhs` is the better attempt of two rows tied on steps, or nil when
    /// nothing but the document ID separates them.
    ///
    /// A live climb clamps every recorded step count to the target and the
    /// server publishes only a target-reached stop, so every finisher on a climb
    /// board holds *exactly* the target: ties on steps are not the edge case
    /// there, they are the only case, and ordering them on document ID threw
    /// away the speed ordering the query had already produced. The board's own
    /// `rankingMetric` settles them instead - the same value the panel's field
    /// line names, so the ordering and the label cannot disagree. An attempt
    /// already home always leads one still running, whatever the metric says.
    private static func isBetterOnTie(
        _ lhs: MergeableRow,
        _ rhs: MergeableRow,
        metric: LiveReplayRankingMetric
    ) -> Bool? {
        if lhs.isFinished != rhs.isFinished {
            return lhs.isFinished
        }

        let lhsValue = windowRankingValue(lhs.row, metric: metric)
        let rhsValue = windowRankingValue(rhs.row, metric: metric)
        guard lhsValue != rhsValue else { return nil }

        return metric.ranksHighestFirst ? lhsValue > rhsValue : lhsValue < rhsValue
    }

    /// The rows standing ahead of the live attempt, nearest first.
    ///
    /// Both halves arrive sorted by steps ascending - the running half from the
    /// bucket query, the finished half from its own - so this is a merge of two
    /// sorted runs, and the window keeps the `limit` nearest, which is the head.
    /// A board with more finishers than the window holds shows the ones the
    /// climber is actually closing on, not the leaders.
    ///
    /// `fetchWindow` reverses this half before ranking it, so rows tied on steps
    /// are ordered worst first: the better attempt ends up nearest rank 1.
    static func mergedAheadRows(
        running: [LiveReplayLeaderboardRow],
        finished: [LiveReplayLeaderboardRow],
        limit: Int,
        metric: LiveReplayRankingMetric
    ) -> [LiveReplayLeaderboardRow] {
        guard limit > 0 else { return [] }
        guard !finished.isEmpty else { return Array(running.prefix(limit)) }

        let merged = mergeable(running: running, finished: finished)
            .sorted { lhs, rhs in
                guard lhs.row.stepsAtBucket == rhs.row.stepsAtBucket else {
                    return lhs.row.stepsAtBucket < rhs.row.stepsAtBucket
                }
                guard let lhsIsBetter = isBetterOnTie(lhs, rhs, metric: metric) else {
                    return lhs.row.id < rhs.row.id
                }
                return !lhsIsBetter
            }
        return merged.prefix(limit).map(\.row)
    }

    /// The rows standing behind the live attempt, nearest first.
    ///
    /// The twin of `mergedAheadRows`, sorted the other way: both halves arrive
    /// descending by steps, and the window keeps the `limit` nearest, which is
    /// again the head. Rank never consults this side - it is `aheadCount + 1` -
    /// so the finished rows below cost a fetch and no count.
    ///
    /// This half is ranked in the order it comes out, so rows tied on steps are
    /// ordered best first - the opposite orientation to the ahead half.
    static func mergedBehindRows(
        running: [LiveReplayLeaderboardRow],
        finished: [LiveReplayLeaderboardRow],
        limit: Int,
        metric: LiveReplayRankingMetric
    ) -> [LiveReplayLeaderboardRow] {
        guard limit > 0 else { return [] }
        guard !finished.isEmpty else { return Array(running.prefix(limit)) }

        let merged = mergeable(running: running, finished: finished)
            .sorted { lhs, rhs in
                guard lhs.row.stepsAtBucket == rhs.row.stepsAtBucket else {
                    return lhs.row.stepsAtBucket > rhs.row.stepsAtBucket
                }
                guard let lhsIsBetter = isBetterOnTie(lhs, rhs, metric: metric) else {
                    return lhs.row.id < rhs.row.id
                }
                return lhsIsBetter
            }
        return merged.prefix(limit).map(\.row)
    }

    /// How many attempts stand ahead of the live one: those still running that
    /// are further up this bucket, plus every attempt already home.
    ///
    /// Both halves or neither. Summing a real count with a fallback would report
    /// a rank measured against a population that was never counted, so a failed
    /// read falls back to the rows actually on screen.
    static func aheadCount(
        running: Int?,
        finished: Int?,
        fetchedRows: [LiveReplayLeaderboardRow]
    ) -> Int {
        guard let running, let finished else { return fetchedRows.count }
        return running + finished
    }

    private func countRowsAhead(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async throws -> Int {
        let query = liveRaceEntries(context: context, bucketIndex: bucketIndex)
            .whereField("stepsAtBucket", isGreaterThanOrEqualTo: currentSteps)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// Counts every completed attempt, matching the static board's one row per completion.
    private func countRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) async throws -> Int {
        let query = entriesCollection(context: context, bucketIndex: bucketIndex)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// Counts the climbers standing on this board - one finisher document each,
    /// the same population the summary's `totalClimbers` carries, written in the
    /// same transaction as the row that produced it.
    private func countFinishers(
        context: LiveReplayLeaderboardContext
    ) async throws -> Int {
        let snapshot = try await finishersCollection(context: context)
            .count
            .getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// The value a completion is ranked on in this context, read from whichever of its
    /// two numbers the context's metric ranks.
    private func rankingValue(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) -> Double {
        switch context.type.rankingMetric {
        case .fastestCompletion:
            return max(completionDurationSeconds, 0)
        case .mostSteps:
            return Double(max(finalSteps, 0))
        }
    }

    /// Counts completions strictly better than `rankingValue` on this context's metric.
    ///
    /// Strictly better, never "better or equal", is what makes the rank competition
    /// style: everyone tied on the metric counts the same rivals ahead of them and so
    /// shares one rank. That matters most on a routine board, where steps are coarse
    /// integers and ties are common. It mirrors the server's `leadingRows` narrowing,
    /// applied here to entry rows because this is a current board rank over every
    /// published attempt; the server's frozen stamp applies the same inequality to
    /// finisher documents wherever the board collapses repeat finishers.
    private func countRowsBetterThan(
        context: LiveReplayLeaderboardContext,
        rankingValue: Double
    ) async throws -> Int {
        let metric = context.type.rankingMetric
        let entries = entriesCollection(context: context, bucketIndex: 0)
        let query = metric.ranksHighestFirst
            ? entries.whereField(metric.field, isGreaterThan: rankingValue)
            : entries.whereField(metric.field, isLessThan: rankingValue)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// Counts the climbers whose standing best leads one value.
    ///
    /// The `countRowsBetterThan` twin for a board that ranks climbers: the same
    /// strict inequality, applied to the one finisher document each climber
    /// holds, so climbers tied on the metric still share a rank and a repeat
    /// finisher is one rival rather than several.
    ///
    /// A single-field inequality, which Firestore indexes by default - declare
    /// no composite index for it, and never let a field override strip
    /// `finishers.bestCompletionDurationSeconds` or `finishers.bestFinalSteps`
    /// of that default index.
    private func countFinishersBetterThan(
        context: LiveReplayLeaderboardContext,
        rankingValue: Double
    ) async throws -> Int {
        let metric = context.type.rankingMetric
        let finishers = finishersCollection(context: context)
        let query = metric.ranksHighestFirst
            ? finishers.whereField(metric.finisherBestField, isGreaterThan: rankingValue)
            : finishers.whereField(metric.finisherBestField, isLessThan: rankingValue)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// The signed-in climber's finisher document, when they hold one.
    ///
    /// Its presence answers whether they already stand in the field; its stored
    /// best is the value that decides whether they stand ahead of the attempt
    /// being ranked. Both answers come from the same document as the count they
    /// are used beside.
    private struct CurrentUserFinisher {
        let storedBest: Double?
    }

    private func currentUserFinisher(
        context: LiveReplayLeaderboardContext
    ) async throws -> CurrentUserFinisher? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return nil
        }

        let snapshot = try await finisherDocument(context: context, userId: uid)
            .getDocument(source: .server)
        guard let data = snapshot.data() else {
            return nil
        }

        return CurrentUserFinisher(
            storedBest: doubleValue(
                for: context.type.rankingMetric.finisherBestField,
                in: data
            )
        )
    }

    /// The signed-in climber's best completion row on this board, or nil when
    /// they hold none.
    ///
    /// Ties on the metric resolve on document ID, which is the immutable workout ID,
    /// so every recompute picks the same winner instead of jittering between them.
    private func currentUserBestCompletionDocument(
        context: LiveReplayLeaderboardContext
    ) async throws -> QueryDocumentSnapshot? {
        guard let uid = Auth.auth().currentUser?.uid else {
            return nil
        }

        let snapshot = try await entriesCollection(context: context, bucketIndex: 0)
            .whereField("userId", isEqualTo: uid)
            .getDocuments(source: .server)
        let metric = context.type.rankingMetric

        return snapshot.documents.min { lhs, rhs in
            let lhsValue = rankingValue(for: metric, in: lhs.data())
            let rhsValue = rankingValue(for: metric, in: rhs.data())
            if lhsValue == rhsValue {
                return lhs.documentID < rhs.documentID
            }
            return metric.ranksHighestFirst ? lhsValue > rhsValue : lhsValue < rhsValue
        }
    }

    private func countRowsMatching(
        context: LiveReplayLeaderboardContext,
        rankingValue: Double
    ) async throws -> Int {
        let query = entriesCollection(context: context, bucketIndex: 0)
            .whereField(context.type.rankingMetric.field, isEqualTo: rankingValue)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    /// Whether the climber already stands in the field this board's denominator
    /// counts.
    ///
    /// Asked of `finishers`, because that is what the denominator counts: the
    /// summary's `totalClimbers` is the server's `completedCount`, one per
    /// finisher document. Asking `entries` instead could disagree with it -
    /// `deleteReplayEntriesForId` takes a climber's rows back out when a workout
    /// is deleted or becomes ineligible, while the finisher document is only
    /// ever created or merged and `completedCount` never decreases - so a
    /// climber who deleted the workout behind their only completion would be
    /// added to a total that already counted them.
    private func currentUserIsFinisher(
        context: LiveReplayLeaderboardContext
    ) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            return false
        }

        return try await finisherDocument(context: context, userId: uid)
            .getDocument(source: .server)
            .exists
    }

    private func optionalCountRowsAhead(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async -> Int? {
        do {
            return try await countRowsAhead(
                context: context,
                bucketIndex: bucketIndex,
                currentSteps: currentSteps
            )
        } catch {
            return nil
        }
    }

    /// Reports a swallowed finished-row read, at most once per read per session.
    ///
    /// `debugLog` is compiled out of Staging and Release, and Release is exactly
    /// the build where a composite index that has not been deployed yet makes
    /// this swallowed error the live path, so the report has to reach
    /// Crashlytics too. The bound is what keeps it off the App Hang path.
    private func reportFinishedRowFailure(
        _ error: Error,
        read: LiveReplayFinishedRowRead,
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) {
        debugLog(
            "Live replay finished-row read \(read.rawValue) failed for " +
            "\(context.contextKey) bucket \(bucketIndex): \(error.localizedDescription)"
        )

        guard finishedRowDiagnostics.withLock({ $0.shouldReport(read) }) else { return }

        TelemetryManager.shared.recordError(
            error,
            context: .firestore,
            code: read.rawValue,
            additionalInfo: ["contextType": context.type.rawValue]
        )
    }

    /// Swallowing the error is the point - the board keeps racing without the
    /// rivals already home - but a swallowed error and an empty finished field
    /// look identical, and the likeliest cause is the composite index this read
    /// needs not being deployed yet, which degrades straight back into the
    /// vanishing-rows defect. Say which it was.
    private func optionalFetchFinishedRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        direction: WindowDirection,
        limit: Int,
        currentUserId: String?
    ) async -> [LiveReplayLeaderboardRow] {
        do {
            return try await fetchFinishedRows(
                context: context,
                bucketIndex: bucketIndex,
                currentSteps: currentSteps,
                direction: direction,
                limit: limit,
                currentUserId: currentUserId
            )
        } catch {
            reportFinishedRowFailure(
                error,
                read: direction == .ahead ? .aheadFetch : .behindFetch,
                context: context,
                bucketIndex: bucketIndex
            )
            return []
        }
    }

    private func optionalCountFinishedRowsAhead(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async -> Int? {
        do {
            return try await countFinishedRowsAhead(
                context: context,
                bucketIndex: bucketIndex,
                currentSteps: currentSteps
            )
        } catch {
            reportFinishedRowFailure(
                error,
                read: .aheadCount,
                context: context,
                bucketIndex: bucketIndex
            )
            return nil
        }
    }

    /// A read that could not answer reports the climber as already standing in
    /// the field, so the denominator never gains a climber nothing measured.
    ///
    /// `fetchWindow` asks this on a ~10s bucket clock for the whole of a race
    /// and is forced more often than that, so a settled answer is remembered:
    /// a finisher document is only ever created or merged, which makes a
    /// positive permanent for the life of the process. A negative is never
    /// cached, because this climber's own attempt writes that document at the
    /// end of the session and a remembered "not in the field yet" would add a
    /// phantom climber to the denominator of their next climb on the same board.
    private func optionalCurrentUserIsFinisher(
        context: LiveReplayLeaderboardContext
    ) async -> Bool {
        let key = Auth.auth().currentUser.map { "\($0.uid)__\(context.contextKey)" }
        if let key, knownFinisherClimbers.withLock({ $0.contains(key) }) {
            return true
        }

        guard let isFinisher = try? await currentUserIsFinisher(context: context) else {
            return true
        }

        if isFinisher, let key {
            knownFinisherClimbers.withLock { $0.insert(key) }
        }

        return isFinisher
    }

    /// One live-race row.
    ///
    /// `currentUserId` is what makes a climber's own earlier completion read as
    /// theirs. Without it every published row was parsed as a stranger, so a
    /// repeat climber raced a row that wore initials, a demographic subtitle and
    /// a link to a stranger's profile - their own.
    private func parseRow(
        id: String,
        data: [String: Any],
        currentSteps: Int,
        currentUserId: String?
    ) -> LiveReplayLeaderboardRow? {
        guard let stepsAtBucket = intValue(for: "stepsAtBucket", in: data) else {
            return nil
        }

        let userId = (data["userId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let isCurrentUser = userId != nil && userId == currentUserId
        let isSynthetic = isTrustedSyntheticRecord(data)
        let identity = PublicClimberIdentity.resolve(
            userId: userId,
            storedDisplayName: data["displayName"] as? String,
            storedPhotoURL: photoURLValue(for: "photoURL", in: data),
            storedAvatarToken: data["avatarToken"] as? String,
            isSynthetic: isSynthetic,
            isCurrentUser: isCurrentUser
        )

        return LiveReplayLeaderboardRow(
            id: id,
            rank: intValue(for: "rank", in: data),
            displayName: identity.displayName,
            avatarToken: identity.avatarToken,
            photoURL: identity.photoURL,
            stepsAtBucket: stepsAtBucket,
            finalSteps: intValue(for: "finalSteps", in: data) ?? stepsAtBucket,
            deltaFromUser: stepsAtBucket - currentSteps,
            isCurrentUser: isCurrentUser,
            isPersonalBest: (data["isPersonalBest"] as? Bool) ?? false,
            completionDurationSeconds: doubleValue(for: "completionDurationSeconds", in: data),
            userId: userId,
            isSynthetic: isSynthetic,
            gender: stringValue(for: "gender", in: data),
            age: intValue(for: "age", in: data),
            locationCity: stringValue(for: "locationCity", in: data)
        )
    }

    private func parseCompletionRow(
        id: String,
        data: [String: Any],
        rank: Int,
        currentUserId: String?
    ) -> LiveReplayLeaderboardRow? {
        guard let completionDurationSeconds = doubleValue(
            for: "completionDurationSeconds",
            in: data
        ) else {
            return nil
        }

        let userId = (data["userId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let isCurrentUser = userId == currentUserId
        let isSynthetic = isTrustedSyntheticRecord(data)
        let identity = PublicClimberIdentity.resolve(
            userId: userId,
            storedDisplayName: data["displayName"] as? String,
            storedPhotoURL: photoURLValue(for: "photoURL", in: data),
            storedAvatarToken: data["avatarToken"] as? String,
            isSynthetic: isSynthetic,
            isCurrentUser: isCurrentUser
        )
        let stepsAtBucket = intValue(for: "stepsAtBucket", in: data) ?? 0

        return LiveReplayLeaderboardRow(
            id: id,
            rank: max(rank, 1),
            displayName: identity.displayName,
            avatarToken: identity.avatarToken,
            photoURL: identity.photoURL,
            stepsAtBucket: stepsAtBucket,
            finalSteps: intValue(for: "finalSteps", in: data) ?? stepsAtBucket,
            deltaFromUser: 0,
            isCurrentUser: isCurrentUser,
            isPersonalBest: isCurrentUser,
            completionDurationSeconds: completionDurationSeconds,
            userId: userId,
            isSynthetic: isSynthetic,
            gender: stringValue(for: "gender", in: data),
            age: intValue(for: "age", in: data),
            locationCity: stringValue(for: "locationCity", in: data)
        )
    }

    private func rankedAheadRows(
        _ rows: [LiveReplayLeaderboardRow],
        currentUserRank: Int
    ) -> [LiveReplayLeaderboardRow] {
        rows.enumerated().map { offset, row in
            rankedRow(
                row,
                rank: currentUserRank - rows.count + offset
            )
        }
    }

    private func rankedBehindRows(
        _ rows: [LiveReplayLeaderboardRow],
        currentUserRank: Int
    ) -> [LiveReplayLeaderboardRow] {
        rows.enumerated().map { offset, row in
            rankedRow(
                row,
                rank: currentUserRank + offset + 1
            )
        }
    }

    private func rankedRow(
        _ row: LiveReplayLeaderboardRow,
        rank: Int
    ) -> LiveReplayLeaderboardRow {
        row.updating(
            rank: row.rank ?? max(rank, 1)
        )
    }

    private func nextCompletionLeaderboardCursor(
        documents: [QueryDocumentSnapshot],
        metric: LiveReplayRankingMetric,
        rows: [LiveReplayLeaderboardRow],
        rankedCount: Int,
        completedCount: Int,
        pageSize: Int
    ) -> LiveReplayCompletionLeaderboardCursor? {
        guard documents.count >= pageSize,
              !rows.isEmpty,
              let lastDocument = documents.last,
              let lastRank = rows.last?.rank,
              rankedCount < completedCount,
              let sortKey = optionalRankingValue(
                for: metric,
                in: lastDocument.data()
              ) else {
            return nil
        }

        return LiveReplayCompletionLeaderboardCursor(
            sortKey: sortKey,
            rowID: lastDocument.documentID,
            lastRank: lastRank,
            rankedCount: rankedCount
        )
    }

    private func leaderboardDocument(
        context: LiveReplayLeaderboardContext
    ) -> DocumentReference {
        db.collection("live_replay_leaderboards")
            .document(context.contextKey)
    }

    private func entriesCollection(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) -> CollectionReference {
        leaderboardDocument(context: context)
            .collection("splitBuckets")
            .document("\(max(bucketIndex, 0))")
            .collection("entries")
    }

    /// Entries as the live race ranks them.
    ///
    /// A per-climb race is a field of climbers, not of attempts, so a repeat
    /// finisher races as a single rival on their fastest completion. The server
    /// owns the flag; the static completion board reads the same entries
    /// unfiltered to keep showing every completion.
    ///
    /// Every other context races every completed attempt as its own opponent and
    /// carries no flag, so filtering there would empty the field.
    private func liveRaceEntries(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) -> Query {
        // Every context type carries the flag now, so one mechanism collapses
        // the race on all three board types rather than one of them behaving
        // differently for want of a field. It also stops a repeat climber's own
        // earlier attempts lining up against them as separate racers.
        entriesCollection(context: context, bucketIndex: bucketIndex)
            .whereField("isBestForUser", isEqualTo: true)
    }

    /// One document per climber who has completed on this board, on every
    /// context type - the server writes it in the same transaction as the entry
    /// row, whether or not the board collapses repeat finishers.
    private func finishersCollection(
        context: LiveReplayLeaderboardContext
    ) -> CollectionReference {
        leaderboardDocument(context: context)
            .collection("finishers")
    }

    private func finisherDocument(
        context: LiveReplayLeaderboardContext,
        userId: String
    ) -> DocumentReference {
        finishersCollection(context: context)
            .document(userId)
    }

    private func completionSnapshotDocument(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) -> DocumentReference {
        leaderboardDocument(context: context)
            .collection("completionSnapshots")
            .document(workoutId)
    }

    private func publishStatusDocument(
        userId: String,
        workoutId: String
    ) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("liveClimbPublishStatuses")
            .document(workoutId)
    }

    private func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return nil
    }

    private func doubleValue(for key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        if let value = data[key] as? Int64 { return Double(value) }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private func timestampValue(for key: String, in data: [String: Any]) -> Date? {
        if let timestamp = data[key] as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = data[key] as? Date {
            return date
        }
        return nil
    }

    private func photoURLValue(for key: String, in data: [String: Any]) -> URL? {
        guard let value = (data[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return nil
        }

        return url
    }

    private func firstAscentValue(in data: [String: Any]) -> LiveReplayFirstAscent? {
        guard let completedAt = timestampValue(for: "firstAscentCompletedAt", in: data) else {
            return nil
        }

        let isSynthetic = (data["firstAscentIsSynthetic"] as? Bool) == true
        let identity = PublicClimberIdentity.resolve(
            userId: stringValue(for: "firstAscentUserId", in: data),
            storedDisplayName: stringValue(for: "firstAscentDisplayName", in: data),
            storedPhotoURL: photoURLValue(for: "firstAscentPhotoURL", in: data),
            storedAvatarToken: stringValue(for: "firstAscentAvatarToken", in: data),
            isSynthetic: isSynthetic
        )

        return LiveReplayFirstAscent(
            userId: stringValue(for: "firstAscentUserId", in: data),
            displayName: identity.displayName,
            avatarToken: identity.avatarToken,
            photoURL: identity.photoURL,
            isSynthetic: isSynthetic,
            completedAt: completedAt
        )
    }

    private func stringValue(for key: String, in data: [String: Any]) -> String? {
        (data[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func isTrustedSyntheticRecord(_ data: [String: Any]) -> Bool {
        (data["isSynthetic"] as? Bool) == true ||
            stringValue(for: "source", in: data) == "synthetic"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
