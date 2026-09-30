import Foundation
@preconcurrency import FirebaseFirestore

/// Reads a climber's unseen recaps and marks them seen.
///
/// Marking a recap seen is the one client write the recap adds: `seenAt`, once, to the
/// server's clock (`firestore.rules`). It is what keeps a recap from showing twice on this
/// phone, another phone, or after a reinstall.
protocol PeriodRecapReading: Sendable {
    func fetchUnseen(userId: String, limit: Int) async throws -> [PeriodRecap]
    func markSeen(userId: String, recapIDs: [String]) async throws
    /// Marks every unseen recap whose period ended at or before `cutoff` seen.
    func markUnseenSeen(userId: String, endingOnOrBefore cutoff: Date) async throws
}

final class PeriodRecapRepository: PeriodRecapReading, Sendable {
    static let shared = PeriodRecapRepository()

    private init() {}

    private var db: Firestore {
        Firestore.firestore()
    }

    func fetchUnseen(userId: String, limit: Int) async throws -> [PeriodRecap] {
        let snapshot = try await recaps(userId: userId)
            .whereField("seenAt", isEqualTo: NSNull())
            .order(by: "periodEndAt", descending: true)
            .limit(to: max(limit, 0))
            .getDocuments(source: .server)
        return snapshot.documents.compactMap {
            PeriodRecapParser.recap(id: $0.documentID, data: $0.data())
        }
    }

    func markSeen(userId: String, recapIDs: [String]) async throws {
        guard !recapIDs.isEmpty else { return }
        let batch = db.batch()
        for recapID in Set(recapIDs) {
            batch.updateData(
                ["seenAt": FieldValue.serverTimestamp()],
                forDocument: recaps(userId: userId).document(recapID)
            )
        }
        try await batch.commit()
    }

    func markUnseenSeen(userId: String, endingOnOrBefore cutoff: Date) async throws {
        let pageSize = 100
        // A weekly and a monthly recap per period for twenty years is well under this.
        for _ in 0..<20 {
            let snapshot = try await recaps(userId: userId)
                .whereField("seenAt", isEqualTo: NSNull())
                .whereField("periodEndAt", isLessThanOrEqualTo: Timestamp(date: cutoff))
                .order(by: "periodEndAt", descending: true)
                .limit(to: pageSize)
                .getDocuments(source: .server)
            try await markSeen(userId: userId, recapIDs: snapshot.documents.map(\.documentID))
            if snapshot.documents.count < pageSize { return }
        }
    }

    private func recaps(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("recaps")
    }
}

/// Parses recap documents. Pure, so the shape is testable without Firestore.
enum PeriodRecapParser {
    static func recap(id: String, data: [String: Any]) -> PeriodRecap? {
        guard let rawCadence = data["cadence"] as? String,
              let cadence = LeaderboardTimeFrame(rawValue: rawCadence),
              cadence == .weekly || cadence == .monthly,
              let periodKey = data["periodKey"] as? String,
              let startAt = date(data["periodStartAt"]),
              let endAt = date(data["periodEndAt"]),
              let rawVariant = data["variant"] as? String,
              let variant = PeriodRecap.Variant(rawValue: rawVariant) else {
            return nil
        }

        let active = (data["active"] as? [String: Any]).map(active(from:))
        let inactive = (data["inactive"] as? [String: Any]).map(inactive(from:))
        if variant == .active, active == nil { return nil }

        return PeriodRecap(
            id: id,
            period: LeaderboardPeriod(timeFrame: cadence, key: periodKey, startAt: startAt, endAt: endAt),
            variant: variant,
            active: variant == .active ? active : nil,
            inactive: variant == .inactive ? inactive : nil,
            seenAt: date(data["seenAt"])
        )
    }

    private static func active(from data: [String: Any]) -> PeriodRecap.Active {
        let firstAscents = (data["firstAscents"] as? [Any] ?? []).compactMap { value -> PeriodRecap.FirstAscent? in
            guard let map = value as? [String: Any],
                  let climbId = map["climbId"] as? String,
                  !climbId.isEmpty else { return nil }
            return PeriodRecap.FirstAscent(climbId: climbId, name: nonEmpty(map["name"]))
        }
        return PeriodRecap.Active(
            rank: positiveInt(data["rank"]),
            climberCount: positiveInt(data["climberCount"] ?? data["fieldSize"]),
            percentileBand: nonEmpty(data["percentileBand"]),
            climbs: max(int(data["climbs"]) ?? 0, 0),
            steps: max(int(data["steps"]) ?? 0, 0),
            floors: max(int(data["floors"]) ?? 0, 0),
            previousClimbs: int(data["previousClimbs"]),
            previousSteps: int(data["previousSteps"]),
            awardRank: positiveInt(data["awardRank"]),
            firstAscents: firstAscents,
            landmarksFinished: (data["landmarksFinished"] as? [Any] ?? []).compactMap { $0 as? String }
        )
    }

    private static func inactive(from data: [String: Any]) -> PeriodRecap.Inactive {
        PeriodRecap.Inactive(
            gapCount: max(int(data["gapCount"]) ?? 1, 1),
            lastClimbAt: date(data["lastClimbAt"]),
            suggestedClimbId: nonEmpty(data["suggestedClimbId"]),
            suggestedClimbName: nonEmpty(data["suggestedClimbName"])
        )
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = int(value), value > 0 else { return nil }
        return value
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as Int64: Int(value)
        case let value as Double: value.isFinite ? Int(value) : nil
        case let value as NSNumber: value.intValue
        default: nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        switch value {
        case let timestamp as Timestamp: timestamp.dateValue()
        case let date as Date: date
        default: nil
        }
    }
}
