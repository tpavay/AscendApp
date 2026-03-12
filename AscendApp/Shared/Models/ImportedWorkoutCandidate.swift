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
        case hevy
        case linkedHevyAppleHealth
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
    let hevyWorkoutID: String?
    let hevyWorkoutTitle: String?
    let hevyWorkoutWindowStart: Date?
    let hevyWorkoutWindowEnd: Date?
    let hevyMetricValue: Int?
    let hevyMetricType: WorkoutMetric?
    let sourceSummaries: [ImportedWorkoutSourceSummary]

    var isLinkedHevyAppleHealth: Bool {
        kind == .linkedHevyAppleHealth
    }

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
            hevyWorkoutID: nil,
            hevyWorkoutTitle: nil,
            hevyWorkoutWindowStart: nil,
            hevyWorkoutWindowEnd: nil,
            hevyMetricValue: nil,
            hevyMetricType: nil,
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

    static func hevy(
        workoutID: String,
        workoutTitle: String,
        startDate: Date,
        endDate: Date?,
        duration: TimeInterval,
        metricValue: Int,
        metricType: WorkoutMetric,
        matchingAppleHealthSample: HealthKitWorkoutSample?,
        existingWorkoutID: UUID? = nil
    ) -> ImportedWorkoutCandidate {
        let hevyDuration = duration > 0 ? duration : max(0, (endDate ?? startDate).timeIntervalSince(startDate))
        let effectiveEndDate = endDate ?? startDate.addingTimeInterval(hevyDuration)

        let sourceSummaries = hevySourceSummaries(
            workoutID: workoutID,
            matchingAppleHealthSample: matchingAppleHealthSample
        )

        return ImportedWorkoutCandidate(
            id: "hevy_\(workoutID)",
            kind: matchingAppleHealthSample == nil ? .hevy : .linkedHevyAppleHealth,
            primaryProvider: .hevy,
            sourceProviders: matchingAppleHealthSample == nil ? [.hevy] : [.hevy, .appleHealth],
            startDate: matchingAppleHealthSample?.startDate ?? startDate,
            duration: hevyDuration,
            displayName: workoutTitle.isEmpty ? Workout.generateDefaultName(for: startDate) : workoutTitle,
            sourceDisplayName: hevySourceDisplayName(matchingAppleHealthSample: matchingAppleHealthSample),
            timingPrecision: matchingAppleHealthSample == nil ? .containerWindow : .exact,
            existingWorkoutID: existingWorkoutID,
            appleHealthSample: matchingAppleHealthSample,
            hevyWorkoutID: workoutID,
            hevyWorkoutTitle: workoutTitle,
            hevyWorkoutWindowStart: startDate,
            hevyWorkoutWindowEnd: effectiveEndDate,
            hevyMetricValue: metricValue,
            hevyMetricType: metricType,
            sourceSummaries: sourceSummaries
        )
    }

    private static func hevySourceSummaries(
        workoutID: String,
        matchingAppleHealthSample: HealthKitWorkoutSample?
    ) -> [ImportedWorkoutSourceSummary] {
        var summaries = [
            ImportedWorkoutSourceSummary(
                provider: .hevy,
                externalRecordID: workoutID,
                displayName: "Hevy",
                sourceName: "Hevy",
                timingPrecision: .containerWindow
            )
        ]

        if let sample = matchingAppleHealthSample {
            summaries.append(
                ImportedWorkoutSourceSummary(
                    provider: .appleHealth,
                    externalRecordID: sample.externalRecordID,
                    displayName: sample.displaySourceName,
                    sourceName: sample.sourceName,
                    timingPrecision: .exact
                )
            )
        }

        return summaries
    }

    private static func hevySourceDisplayName(matchingAppleHealthSample: HealthKitWorkoutSample?) -> String {
        guard let sample = matchingAppleHealthSample else {
            return "Hevy"
        }

        return "Hevy + \(sample.displaySourceName)"
    }
}
