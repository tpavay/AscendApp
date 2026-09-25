import Foundation
@preconcurrency import FirebaseFirestore

/// Reads the server's `home_today_activity/global` document into a feed.
///
/// Pure over a Firestore data dictionary, so the shape contract is unit-testable
/// without a listener. A row that cannot be read is dropped rather than failing the
/// feed: one malformed row is a fact about that row, not a reason to hide the rest.
enum HomeTodayActivityFeedDecoder {
    static func feed(from data: [String: Any]?) -> HomeTodayActivityFeed {
        guard let data else { return .empty }
        let rows = (data["rows"] as? [Any] ?? []).compactMap { item in
            row(from: item as? [String: Any])
        }
        return HomeTodayActivityFeed(
            rows: rows,
            updatedAt: date(for: "updatedAt", in: data)
        )
    }

    static func row(from data: [String: Any]?) -> HomeTodayActivityRow? {
        guard let data,
              let workoutId = nonEmptyString(for: "workoutId", in: data),
              let userId = nonEmptyString(for: "userId", in: data),
              let kindRawValue = data["kind"] as? String,
              let kind = HomeTodayActivityKind(rawValue: kindRawValue),
              let steps = intValue(for: "steps", in: data),
              let durationSeconds = doubleValue(for: "durationSeconds", in: data),
              let completedAt = date(for: "completedAt", in: data),
              let publishedAt = date(for: "publishedAt", in: data),
              let displayName = data["displayName"] as? String else {
            return nil
        }

        let goalKind = (data["justClimbGoalKind"] as? String)
            .flatMap(HomeTodayJustClimbGoalKind.init(rawValue:))
        let photoURL = nonEmptyString(for: "photoURL", in: data).flatMap(URL.init(string:))

        return HomeTodayActivityRow(
            workoutId: workoutId,
            userId: userId,
            kind: kind,
            climbId: nonEmptyString(for: "climbId", in: data),
            routineTemplateId: nonEmptyString(for: "routineTemplateId", in: data),
            steps: steps,
            durationSeconds: durationSeconds,
            completedAt: completedAt,
            publishedAt: publishedAt,
            justClimbGoalKind: goalKind,
            justClimbGoalValue: intValue(for: "justClimbGoalValue", in: data),
            displayName: displayName,
            photoURL: photoURL,
            avatarToken: data["avatarToken"] as? String ?? "",
            isSynthetic: data["isSynthetic"] as? Bool ?? false
        )
    }

    private static func nonEmptyString(for key: String, in data: [String: Any]) -> String? {
        guard let value = data[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int {
            return value
        }
        if let value = data[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func doubleValue(for key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double {
            return value
        }
        if let value = data[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private static func date(for key: String, in data: [String: Any]) -> Date? {
        if let timestamp = data[key] as? Timestamp {
            return timestamp.dateValue()
        }
        return data[key] as? Date
    }
}
