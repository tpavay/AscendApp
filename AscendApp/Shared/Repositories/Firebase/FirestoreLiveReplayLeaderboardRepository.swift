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
            updatedAt: timestampValue(for: "updatedAt", in: data)
        )
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> LiveReplayCompletionRank {
        let resolvedDuration = max(completionDurationSeconds, 0)

        async let summary = fetchSummary(context: context)
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

        let resolvedSummary = try await summary
        let fasterCount = try await fasterCompletionCount
        let publishedCount = try await publishedCompletionCount
        let hasPublishedCurrentUser = try await currentUserIsPublished
        let localCompletionAdjustment = hasPublishedCurrentUser ? 0 : 1
        let completedCount = max(
            resolvedSummary.completedCount,
            publishedCount + localCompletionAdjustment,
            fasterCount + 1
        )

        return LiveReplayCompletionRank(
            rank: min(fasterCount + 1, completedCount),
            completedCount: completedCount,
            updatedAt: resolvedSummary.updatedAt
        )
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int
    ) async throws -> LiveReplayCompletionLeaderboard {
        let resolvedLimit = max(limit, 1)

        async let summary = fetchSummary(context: context)
        async let completedCount = countRows(context: context, bucketIndex: 0)
        async let rowSnapshot = entriesCollection(context: context, bucketIndex: 0)
            .order(by: "completionDurationSeconds", descending: false)
            .limit(to: resolvedLimit)
            .getDocuments(source: .server)

        let resolvedSummary = try await summary
        let resolvedCompletedCount = try await completedCount
        let currentUserId = Auth.auth().currentUser?.uid
        let rows = try await rowSnapshot.documents.enumerated().compactMap { offset, document in
            parseCompletionRow(
                id: document.documentID,
                data: document.data(),
                rank: offset + 1,
                currentUserId: currentUserId
            )
        }

        return LiveReplayCompletionLeaderboard(
            rows: rows,
            completedCount: max(resolvedSummary.completedCount, resolvedCompletedCount),
            updatedAt: resolvedSummary.updatedAt
        )
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
        async let totalBucketCount = optionalCountRows(
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

        let collection = entriesCollection(context: context, bucketIndex: bucketIndex)
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
        let query = entriesCollection(context: context, bucketIndex: bucketIndex)
            .whereField("stepsAtBucket", isGreaterThanOrEqualTo: currentSteps)

        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    private func countRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) async throws -> Int {
        let query = entriesCollection(context: context, bucketIndex: bucketIndex)

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

    private func currentUserHasPublishedCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            return false
        }

        let snapshot = try await entriesCollection(context: context, bucketIndex: 0)
            .document(uid)
            .getDocument(source: .server)
        return snapshot.exists
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

    private func optionalCountRows(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int
    ) async -> Int? {
        do {
            return try await countRows(
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
            completionDurationSeconds: doubleValue(for: "completionDurationSeconds", in: data)
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
            isCurrentUser: id == currentUserId,
            isPersonalBest: id == currentUserId,
            completionDurationSeconds: completionDurationSeconds
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
            completionDurationSeconds: row.completionDurationSeconds
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
