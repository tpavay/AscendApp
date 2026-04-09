import Foundation

enum WorkoutImportAnalyticsEvent: TelemetryEvent {
    case importStarted(
        mode: ImportMode,
        candidateCount: Int,
        sourceMix: SourceMix
    )
    case importFinished(
        mode: ImportMode,
        candidateCount: Int,
        importedCount: Int,
        updatedCount: Int,
        failedCount: Int,
        outcome: Outcome,
        sourceMix: SourceMix
    )

    var record: TelemetryRecord {
        switch self {
        case .importStarted(let mode, let candidateCount, let sourceMix):
            return TelemetryRecord(
                name: "workout_import_started",
                parameters: [
                    "import_mode": .string(mode.rawValue),
                    "candidate_count_bucket": .string(CountBucket(candidateCount).rawValue),
                    "source_mix": .string(sourceMix.rawValue)
                ],
                destinations: [.analytics, .crashlytics]
            )

        case .importFinished(
            let mode,
            let candidateCount,
            let importedCount,
            let updatedCount,
            let failedCount,
            let outcome,
            let sourceMix
        ):
            return TelemetryRecord(
                name: "workout_import_finished",
                parameters: [
                    "import_mode": .string(mode.rawValue),
                    "candidate_count_bucket": .string(CountBucket(candidateCount).rawValue),
                    "imported_count_bucket": .string(CountBucket(importedCount).rawValue),
                    "updated_count_bucket": .string(CountBucket(updatedCount).rawValue),
                    "failed_count_bucket": .string(CountBucket(failedCount).rawValue),
                    "outcome": .string(outcome.rawValue),
                    "source_mix": .string(sourceMix.rawValue)
                ],
                destinations: [.analytics, .crashlytics]
            )
        }
    }

    static func started(mode: ImportMode, candidates: [ImportedWorkoutCandidate]) -> Self {
        .importStarted(
            mode: mode,
            candidateCount: candidates.count,
            sourceMix: SourceMix(candidates: candidates)
        )
    }

    static func finished(
        mode: ImportMode,
        candidates: [ImportedWorkoutCandidate],
        result: ImportBatchResult
    ) -> Self {
        .importFinished(
            mode: mode,
            candidateCount: candidates.count,
            importedCount: result.importedWorkouts.count,
            updatedCount: result.updatedWorkouts.count,
            failedCount: result.failedCandidateIDs.count,
            outcome: Outcome(result: result),
            sourceMix: SourceMix(candidates: candidates)
        )
    }

    static func finished(
        mode: ImportMode,
        candidate: ImportedWorkoutCandidate,
        outcome: WorkoutImportCoordinator.ImportOutcome
    ) -> Self {
        let result = ImportBatchResult(
            importedWorkouts: {
                if case .imported(let workout) = outcome {
                    return [workout]
                }
                return []
            }(),
            updatedWorkouts: {
                if case .updatedExisting(let workout) = outcome {
                    return [workout]
                }
                return []
            }(),
            failedCandidateIDs: {
                if case .failed(let candidateID) = outcome {
                    return [candidateID]
                }
                return []
            }()
        )

        return finished(
            mode: mode,
            candidates: [candidate],
            result: result
        )
    }
}

extension WorkoutImportAnalyticsEvent {
    enum ImportMode: String {
        case single
        case selected
        case all
    }

    enum Outcome: String {
        case imported
        case updatedExisting = "updated_existing"
        case partialSuccess = "partial_success"
        case mixedSuccess = "mixed_success"
        case failed

        init(result: ImportBatchResult) {
            let hasImported = result.successCount > 0
            let hasUpdated = result.updatedCount > 0
            let hasFailures = result.failedCount > 0

            switch (hasImported, hasUpdated, hasFailures) {
            case (false, false, true):
                self = .failed
            case (true, false, false):
                self = .imported
            case (false, true, false):
                self = .updatedExisting
            case (_, _, true):
                self = .partialSuccess
            case (true, true, false):
                self = .mixedSuccess
            default:
                self = .failed
            }
        }
    }

    enum CountBucket: String {
        case zero
        case one
        case twoToFive = "2_5"
        case sixToTen = "6_10"
        case elevenPlus = "11_plus"

        init(_ count: Int) {
            switch count {
            case ..<1:
                self = .zero
            case 1:
                self = .one
            case 2...5:
                self = .twoToFive
            case 6...10:
                self = .sixToTen
            default:
                self = .elevenPlus
            }
        }
    }

    enum SourceMix: String {
        case appleHealthOnly = "apple_health_only"
        case hevyOnly = "hevy_only"
        case linkedOnly = "linked_only"
        case mixed

        init(candidates: [ImportedWorkoutCandidate]) {
            let kinds = Set(candidates.map(\.kind))

            switch kinds {
            case [.appleHealth]:
                self = .appleHealthOnly
            case [.hevy]:
                self = .hevyOnly
            case [.linkedHevyAppleHealth]:
                self = .linkedOnly
            default:
                self = .mixed
            }
        }
    }
}
