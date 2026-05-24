//
//  ImportedWorkoutCandidate.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation

struct HealthKitWorkoutSample: Codable, Hashable, Identifiable {
    let externalRecordID: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let sourceName: String
    let sourceBundleIdentifier: String
    let deviceModel: String?

    var id: String { externalRecordID }

    var displaySourceName: String {
        sourceName.isEmpty ? "Apple Health" : sourceName
    }
}

struct ImportedWorkoutSourceSummary: Hashable, Identifiable {
    let provider: WorkoutProvider
    let externalRecordID: String
    let displayName: String
    let sourceName: String?
    let timingPrecision: TimingPrecision

    var id: String {
        "\(provider.rawValue)_\(externalRecordID)"
    }
}

struct ImportedWorkoutCandidate: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case appleHealth
    }

    let id: String
    let kind: Kind
    let primaryProvider: WorkoutProvider
    let sourceProviders: [WorkoutProvider]
    let startDate: Date
    let duration: TimeInterval
    let displayName: String
    let sourceDisplayName: String
    let timingPrecision: TimingPrecision
    let existingWorkoutID: UUID?
    let appleHealthSample: HealthKitWorkoutSample?
    let sourceSummaries: [ImportedWorkoutSourceSummary]

    static func appleHealth(sample: HealthKitWorkoutSample) -> ImportedWorkoutCandidate {
        let sourceName = sample.displaySourceName

        return ImportedWorkoutCandidate(
            id: "ah_\(sample.externalRecordID)",
            kind: .appleHealth,
            primaryProvider: .appleHealth,
            sourceProviders: [.appleHealth],
            startDate: sample.startDate,
            duration: sample.duration,
            displayName: Workout.generateDefaultName(for: sample.startDate),
            sourceDisplayName: sourceName,
            timingPrecision: .exact,
            existingWorkoutID: nil,
            appleHealthSample: sample,
            sourceSummaries: [
                ImportedWorkoutSourceSummary(
                    provider: .appleHealth,
                    externalRecordID: sample.externalRecordID,
                    displayName: sourceName,
                    sourceName: sample.sourceName,
                    timingPrecision: .exact
                )
            ]
        )
    }
}
