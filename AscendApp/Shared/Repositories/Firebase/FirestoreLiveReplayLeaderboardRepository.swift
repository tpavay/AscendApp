import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

final class FirestoreLiveReplayLeaderboardRepository: LiveReplayLeaderboardRepository, @unchecked Sendable {
    static let shared = FirestoreLiveReplayLeaderboardRepository()

    private let db = Firestore.firestore()

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

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> LiveReplayCompletionRank {
        let resolvedDuration = max(completionDurationSeconds, 0)

        async let fasterCompletionCount = countRowsFasterThan(
            context: context,
            completionDurationSeconds: resolvedDuration
        )
        async let publishedCompletionCount = countRows(
            context: context,
            bucketIndex: 0
        )
        async let currentUserIsPublished = currentUserHasPublishedCompletion(
            context: context
        )

        let fasterCount = try await fasterCompletionCount
        let publishedCount = try await publishedCompletionCount
        let hasPublishedCurrentUser = try await currentUserIsPublished
        let localCompletionAdjustment = hasPublishedCurrentUser ? 0 : 1
        let completedCount = max(
            publishedCount + localCompletionAdjustment,
            fasterCount + 1
        )

        return LiveReplayCompletionRank(
            rank: min(fasterCount + 1, completedCount),
            completedCount: completedCount,
            updatedAt: nil
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

        let snapshot = try await entriesCollection(context: context, bucketIndex: 0)
            .whereField("userId", isEqualTo: uid)
            .getDocuments(source: .server)

        let bestDocument = snapshot.documents.min { lhs, rhs in
            let lhsDuration = doubleValue(for: "completionDurationSeconds", in: lhs.data()) ?? .greatestFiniteMagnitude
            let rhsDuration = doubleValue(for: "completionDurationSeconds", in: rhs.data()) ?? .greatestFiniteMagnitude
            if lhsDuration == rhsDuration {
                return lhs.documentID < rhs.documentID
            }
            return lhsDuration < rhsDuration
        }

        guard let bestDocument,
              let completionDurationSeconds = doubleValue(
                for: "completionDurationSeconds",
                in: bestDocument.data()
              ) else {
            return nil
        }

        async let fasterCompletionCount = countRowsFasterThan(
            context: context,
            completionDurationSeconds: completionDurationSeconds
        )
        async let publishedCompletionCount = countRows(
            context: context,
            bucketIndex: 0
        )
        async let sameDurationCompletionCount = countRowsMatching(
            context: context,
            completionDurationSeconds: completionDurationSeconds
        )

        let fasterCount = try await fasterCompletionCount
        let publishedCount = try await publishedCompletionCount
        let sameDurationCount = try await sameDurationCompletionCount
        let completedCount = max(publishedCount, fasterCount + 1)

        return LiveReplayCurrentUserCompletion(
            rank: min(fasterCount + 1, completedCount),
            completedCount: completedCount,
            completionDurationSeconds: completionDurationSeconds,
            workoutId: stringValue(for: "workoutId", in: bestDocument.data()) ?? bestDocument.documentID,
            updatedAt: timestampValue(for: "updatedAt", in: bestDocument.data()),
            isTied: sameDurationCount > 1
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
        var query: Query = entriesCollection(context: context, bucketIndex: 0)
            .order(by: "completionDurationSeconds", descending: false)
            .order(by: FieldPath.documentID(), descending: false)

        if let cursor {
            query = query.start(after: [
                cursor.completionDurationSeconds,
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

        // Rank on the raw duration, matching the server's strict `<` count in
        // functions/src/liveReplayLeaderboard.ts (completionRankForPayload) — and so
        // matching the pinned row, which derives its rank from countRowsFasterThan.
        let rankable = snapshot.documents.compactMap { document -> RankableCompletion? in
            guard let durationSeconds = doubleValue(
                for: "completionDurationSeconds",
                in: document.data()
            ) else {
                return nil
            }

            return RankableCompletion(
                id: document.documentID,
                data: document.data(),
                durationSeconds: durationSeconds
            )
        }

        let ranks = CompetitionRanking.ranks(
            for: rankable,
            continuing: cursor?.rankingContinuation,
            key: \.durationSeconds
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
        let durationSeconds: TimeInterval
    }

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow {
        async let summary = fetchSummary(context: context)
        async let aheadRows = fetchRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .ahead,
            limit: rowsAhead
        )
        async let aheadCount = optionalCountRowsAhead(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps
        )
        async let totalBucketCount = optionalCountBestPerUserRows(
            context: context,
            bucketIndex: bucketIndex
        )
        async let behindRows = fetchRows(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: currentSteps,
            direction: .behind,
            limit: rowsBehind
        )

        let resolvedSummary = try await summary
        let rowsAhead = try await aheadRows
        let rowsBehind = try await behindRows
        let currentUserRank = (await aheadCount ?? rowsAhead.count) + 1
        let rankedAheadRows = rankedAheadRows(
            Array(rowsAhead.reversed()),
            currentUserRank: currentUserRank
        )
        let rankedBehindRows = rankedBehindRows(
            rowsBehind,
            currentUserRank: currentUserRank
        )
        let visibleWindowCount = currentUserRank + rowsBehind.count
        let totalClimbers = max(
            resolvedSummary.totalClimbers,
            (await totalBucketCount).map { $0 + 1 } ?? 0,
            visibleWindowCount
        )

        return LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: bucketIndex,
            currentSteps: max(currentSteps, 0),
            fetchedAt: Date(),
            rows: rankedAheadRows + rankedBehindRows,
            currentUserRank: currentUserRank,
            totalClimbers: totalClimbers
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
        limit: Int
    ) async throws -> [LiveReplayLeaderboardRow] {
        guard limit > 0 else { return [] }

        let collection = bestPerUserEntries(context: context, bucketIndex: bucketIndex)
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
                currentSteps: currentSteps
            )
        }
    }

    private func countRowsAhead(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int
    ) async throws -> Int {
        let query = bestPerUserEntries(context: context, bucketIndex: bucketIndex)
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

    /// Counts distinct climbers, so a repeat finisher anchors live rank once.
    private func countBestPerUserRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) async throws -> Int {
        let query = bestPerUserEntries(context: context, bucketIndex: bucketIndex)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    private func countRowsFasterThan(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> Int {
        let query = entriesCollection(context: context, bucketIndex: 0)
            .whereField("completionDurationSeconds", isLessThan: max(completionDurationSeconds, 0))

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    private func countRowsMatching(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> Int {
        let query = entriesCollection(context: context, bucketIndex: 0)
            .whereField("completionDurationSeconds", isEqualTo: max(completionDurationSeconds, 0))

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    private func currentUserHasPublishedCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            return false
        }

        let snapshot = try await entriesCollection(context: context, bucketIndex: 0)
            .whereField("userId", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments(source: .server)
        return snapshot.documents.isEmpty == false
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

    private func optionalCountBestPerUserRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) async -> Int? {
        do {
            return try await countBestPerUserRows(
                context: context,
                bucketIndex: bucketIndex
            )
        } catch {
            return nil
        }
    }

    private func parseRow(
        id: String,
        data: [String: Any],
        currentSteps: Int
    ) -> LiveReplayLeaderboardRow? {
        guard let stepsAtBucket = intValue(for: "stepsAtBucket", in: data) else {
            return nil
        }

        let displayName = (data["displayName"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            ?? "Climber"
        let userId = (data["userId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return LiveReplayLeaderboardRow(
            id: id,
            rank: intValue(for: "rank", in: data),
            displayName: displayName,
            avatarToken: (data["avatarToken"] as? String) ?? Self.avatarToken(for: displayName),
            photoURL: photoURLValue(for: "photoURL", in: data),
            stepsAtBucket: stepsAtBucket,
            finalSteps: intValue(for: "finalSteps", in: data) ?? stepsAtBucket,
            deltaFromUser: stepsAtBucket - currentSteps,
            isCurrentUser: false,
            isPersonalBest: (data["isPersonalBest"] as? Bool) ?? false,
            completionDurationSeconds: doubleValue(for: "completionDurationSeconds", in: data),
            userId: userId,
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

        let displayName = (data["displayName"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            ?? "Climber"
        let userId = (data["userId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let stepsAtBucket = intValue(for: "stepsAtBucket", in: data) ?? 0

        return LiveReplayLeaderboardRow(
            id: id,
            rank: max(rank, 1),
            displayName: displayName,
            avatarToken: (data["avatarToken"] as? String) ?? Self.avatarToken(for: displayName),
            photoURL: photoURLValue(for: "photoURL", in: data),
            stepsAtBucket: stepsAtBucket,
            finalSteps: intValue(for: "finalSteps", in: data) ?? stepsAtBucket,
            deltaFromUser: 0,
            isCurrentUser: userId == currentUserId,
            isPersonalBest: userId == currentUserId,
            completionDurationSeconds: completionDurationSeconds,
            userId: userId,
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
        LiveReplayLeaderboardRow(
            id: row.id,
            rank: row.rank ?? max(rank, 1),
            displayName: row.displayName,
            avatarToken: row.avatarToken,
            photoURL: row.photoURL,
            stepsAtBucket: row.stepsAtBucket,
            finalSteps: row.finalSteps,
            deltaFromUser: row.deltaFromUser,
            isCurrentUser: row.isCurrentUser,
            isPersonalBest: row.isPersonalBest,
            completionDurationSeconds: row.completionDurationSeconds,
            userId: row.userId,
            gender: row.gender,
            age: row.age,
            locationCity: row.locationCity
        )
    }

    private func nextCompletionLeaderboardCursor(
        documents: [QueryDocumentSnapshot],
        rows: [LiveReplayLeaderboardRow],
        rankedCount: Int,
        completedCount: Int,
        pageSize: Int
    ) -> LiveReplayCompletionLeaderboardCursor? {
        guard documents.count >= pageSize,
              !rows.isEmpty,
              let lastDocument = documents.last,
              let durationSeconds = doubleValue(
                for: "completionDurationSeconds",
                in: lastDocument.data()
              ) ?? rows.last?.completionDurationSeconds,
              let lastRank = rows.last?.rank,
              rankedCount < completedCount else {
            return nil
        }

        return LiveReplayCompletionLeaderboardCursor(
            completionDurationSeconds: durationSeconds,
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

    /// Entries narrowed to one row per opponent: each climber's fastest completion.
    ///
    /// The live race is a field of climbers, not of attempts, so a repeat finisher
    /// races as a single rival on their best time. The server owns the flag; the
    /// static completion board reads the same entries unfiltered to keep showing
    /// every completion.
    private func bestPerUserEntries(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) -> Query {
        entriesCollection(context: context, bucketIndex: bucketIndex)
            .whereField("isBestForUser", isEqualTo: true)
    }

    private func finisherDocument(
        context: LiveReplayLeaderboardContext,
        userId: String
    ) -> DocumentReference {
        leaderboardDocument(context: context)
            .collection("finishers")
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

        let displayName = stringValue(for: "firstAscentDisplayName", in: data) ?? "Climber"
        let avatarToken = stringValue(for: "firstAscentAvatarToken", in: data) ??
            Self.avatarToken(for: displayName)

        return LiveReplayFirstAscent(
            userId: stringValue(for: "firstAscentUserId", in: data),
            displayName: displayName,
            avatarToken: avatarToken,
            photoURL: photoURLValue(for: "firstAscentPhotoURL", in: data),
            completedAt: completedAt
        )
    }

    private func stringValue(for key: String, in data: [String: Any]) -> String? {
        (data[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func avatarToken(for displayName: String) -> String {
        let initials = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let token = String(initials).uppercased()
        return token.isEmpty ? "A" : token
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
