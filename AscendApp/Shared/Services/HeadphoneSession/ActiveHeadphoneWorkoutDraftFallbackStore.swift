import Foundation
import SwiftData

/// Everything an `ActiveHeadphoneWorkoutDraft` row holds, as one value that can be written to a
/// file without SwiftData.
///
/// This is the shape the fallback file carries and the shape the next launch reads back. It is a
/// copy of the row, not a reference to it, so it can be encoded on a phone whose store has just
/// refused a save.
struct ActiveHeadphoneWorkoutDraftSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: String
    var kindRawValue: String
    var statusRawValue: String
    var createdAt: Date
    var startedAt: Date
    var lastCheckpointAt: Date
    var title: String
    var subtitle: String
    var workoutName: String
    var steps: Int
    var durationSeconds: TimeInterval
    var sampleCount: Int
    var targetStepCount: Int?
    var targetDurationSeconds: TimeInterval?
    var climbId: String?
    var justClimbGoalKindRawValue: String?
    var justClimbDurationMinutes: Int?
    var justClimbStepCount: Int?
    var routineId: UUID?
    var routineSourceRawValue: String?
    var routineTemplateId: String?
    var routineDifficulty: Int?
    var routineIntervalCount: Int?
    var routineSkippedIntervalCount: Int?
    var routineWeightConfigurationData: Data?
    var splitCurveData: Data?
    var trackingIntegrityData: Data?
    var stepCorrectionsData: Data?
    var heartRateData: Data?
    var heartRateSampleCount: Int?
    var checkpointDiagnosticsData: Data?

    @MainActor
    init(_ draft: ActiveHeadphoneWorkoutDraft) {
        id = draft.id
        sessionID = draft.sessionID
        kindRawValue = draft.kindRawValue
        statusRawValue = draft.statusRawValue
        createdAt = draft.createdAt
        startedAt = draft.startedAt
        lastCheckpointAt = draft.lastCheckpointAt
        title = draft.title
        subtitle = draft.subtitle
        workoutName = draft.workoutName
        steps = draft.steps
        durationSeconds = draft.durationSeconds
        sampleCount = draft.sampleCount
        targetStepCount = draft.targetStepCount
        targetDurationSeconds = draft.targetDurationSeconds
        climbId = draft.climbId
        justClimbGoalKindRawValue = draft.justClimbGoalKindRawValue
        justClimbDurationMinutes = draft.justClimbDurationMinutes
        justClimbStepCount = draft.justClimbStepCount
        routineId = draft.routineId
        routineSourceRawValue = draft.routineSourceRawValue
        routineTemplateId = draft.routineTemplateId
        routineDifficulty = draft.routineDifficulty
        routineIntervalCount = draft.routineIntervalCount
        routineSkippedIntervalCount = draft.routineSkippedIntervalCount
        routineWeightConfigurationData = draft.routineWeightConfigurationData
        splitCurveData = draft.splitCurveData
        trackingIntegrityData = draft.trackingIntegrityData
        stepCorrectionsData = draft.stepCorrectionsData
        heartRateData = draft.heartRateData
        heartRateSampleCount = draft.heartRateSampleCount
        checkpointDiagnosticsData = draft.checkpointDiagnosticsData
    }

    /// Writes every field onto an existing row. The row's identity is left alone.
    @MainActor
    func apply(to draft: ActiveHeadphoneWorkoutDraft) {
        draft.sessionID = sessionID
        draft.kindRawValue = kindRawValue
        draft.statusRawValue = statusRawValue
        draft.createdAt = createdAt
        draft.startedAt = startedAt
        draft.lastCheckpointAt = lastCheckpointAt
        draft.title = title
        draft.subtitle = subtitle
        draft.workoutName = workoutName
        draft.steps = steps
        draft.durationSeconds = durationSeconds
        draft.sampleCount = sampleCount
        draft.targetStepCount = targetStepCount
        draft.targetDurationSeconds = targetDurationSeconds
        draft.climbId = climbId
        draft.justClimbGoalKindRawValue = justClimbGoalKindRawValue
        draft.justClimbDurationMinutes = justClimbDurationMinutes
        draft.justClimbStepCount = justClimbStepCount
        draft.routineId = routineId
        draft.routineSourceRawValue = routineSourceRawValue
        draft.routineTemplateId = routineTemplateId
        draft.routineDifficulty = routineDifficulty
        draft.routineIntervalCount = routineIntervalCount
        draft.routineSkippedIntervalCount = routineSkippedIntervalCount
        draft.routineWeightConfigurationData = routineWeightConfigurationData
        draft.splitCurveData = splitCurveData
        draft.trackingIntegrityData = trackingIntegrityData
        draft.stepCorrectionsData = stepCorrectionsData
        draft.heartRateData = heartRateData
        draft.heartRateSampleCount = heartRateSampleCount
        draft.checkpointDiagnosticsData = checkpointDiagnosticsData
    }

    /// A fresh row carrying these values, for a launch whose store never received the draft.
    @MainActor
    func makeDraft() -> ActiveHeadphoneWorkoutDraft {
        let draft = ActiveHeadphoneWorkoutDraft(
            id: id,
            sessionID: sessionID,
            kind: ActiveHeadphoneWorkoutDraftKind(rawValue: kindRawValue) ?? .justClimb,
            startedAt: startedAt,
            title: title,
            subtitle: subtitle,
            workoutName: workoutName,
            targetStepCount: targetStepCount,
            targetDurationSeconds: targetDurationSeconds
        )
        apply(to: draft)
        return draft
    }
}

/// Where a checkpoint goes when SwiftData will not take it.
///
/// A `modelContext.save()` that throws used to be swallowed with a Debug-only log, so a phone with
/// no free storage kept counting in memory while the draft on disk stayed frozen at its last good
/// write - and the recovery screen then offered the climber that stale number as the truth. Every
/// failed save now lands here as one atomic JSON file beside the store, and the next launch folds
/// the file back into the row before anybody reads the draft. Atomic writes mean a kill mid-write
/// leaves the previous file intact rather than a truncated one.
struct ActiveHeadphoneWorkoutDraftFallbackStore: Sendable {
    static let directoryName = "ActiveHeadphoneWorkoutDrafts"

    let directoryURL: URL

    init(directoryURL: URL = URL.applicationSupportDirectory.appending(path: Self.directoryName)) {
        self.directoryURL = directoryURL
    }

    func fileURL(for draftID: UUID) -> URL {
        directoryURL.appending(path: "\(draftID.uuidString).json")
    }

    func write(_ snapshot: ActiveHeadphoneWorkoutDraftSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL(for: snapshot.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func read(draftID: UUID) throws -> ActiveHeadphoneWorkoutDraftSnapshot? {
        let url = fileURL(for: draftID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ActiveHeadphoneWorkoutDraftSnapshot.self, from: Data(contentsOf: url))
    }

    func readAll() -> [ActiveHeadphoneWorkoutDraftSnapshot] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                try? JSONDecoder().decode(ActiveHeadphoneWorkoutDraftSnapshot.self, from: Data(contentsOf: url))
            }
            .sorted { $0.lastCheckpointAt > $1.lastCheckpointAt }
    }

    func remove(draftID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: draftID))
    }

    /// Every fallback file, for the account-deletion sweep: a draft that outlived the store would
    /// be the next account's climb on the next launch (#348).
    func removeAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// Folds every fallback file into the store: a file newer than its row overwrites the row, a
    /// file with no row becomes one, and a file that is older than its row is simply stale. A file
    /// is removed only once the store has accepted what it held, so a store that is still refusing
    /// writes leaves the file for the next launch.
    @MainActor
    func reconcile(
        into modelContext: ModelContext,
        diagnostics: AppDiagnosticsRecorder = .shared
    ) -> Int {
        var reconciled = 0

        for snapshot in readAll() {
            let draftID = snapshot.id
            let descriptor = FetchDescriptor<ActiveHeadphoneWorkoutDraft>(
                predicate: #Predicate { $0.id == draftID }
            )
            let existing = try? modelContext.fetch(descriptor).first

            if let existing, existing.lastCheckpointAt >= snapshot.lastCheckpointAt {
                remove(draftID: draftID)
                continue
            }

            if let existing {
                snapshot.apply(to: existing)
            } else {
                modelContext.insert(snapshot.makeDraft())
            }

            do {
                try modelContext.save()
                remove(draftID: draftID)
                reconciled += 1
                diagnostics.record(
                    "active_headphone_draft_fallback_restored",
                    level: .warning,
                    details: [
                        "draft_id": draftID.uuidString,
                        "steps": String(snapshot.steps),
                        "duration_seconds": String(Int(snapshot.durationSeconds.rounded(.down))),
                        "had_row": existing == nil ? "false" : "true"
                    ]
                )
            } catch {
                modelContext.rollback()
                diagnostics.record(
                    "active_headphone_draft_fallback_restore_failed",
                    level: .error,
                    details: ["draft_id": draftID.uuidString, "error": error.localizedDescription]
                )
            }
        }

        return reconciled
    }
}
