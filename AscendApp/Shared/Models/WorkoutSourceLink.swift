//
//  WorkoutSourceLink.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import SwiftData

@Model
final class WorkoutSourceLink {
    var id: UUID
    private var providerRawValue: String
    var externalRecordID: String
    var providerWindowStart: Date
    var providerWindowEnd: Date
    private var timingPrecisionRawValue: String
    var linkedAt: Date
    var importedAt: Date
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var deviceModel: String?
    var metadataJSON: String?
    var workout: Workout?

    var provider: WorkoutProvider {
        get { WorkoutProvider(rawValue: providerRawValue) ?? .appleHealth }
        set { providerRawValue = newValue.rawValue }
    }

    var timingPrecision: TimingPrecision {
        get { TimingPrecision(rawValue: timingPrecisionRawValue) ?? .exact }
        set { timingPrecisionRawValue = newValue.rawValue }
    }

    init(
        provider: WorkoutProvider,
        externalRecordID: String,
        providerWindowStart: Date,
        providerWindowEnd: Date,
        timingPrecision: TimingPrecision,
        linkedAt: Date = Date(),
        importedAt: Date = Date(),
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        deviceModel: String? = nil,
        metadataJSON: String? = nil,
        workout: Workout? = nil
    ) {
        self.id = UUID()
        self.providerRawValue = provider.rawValue
        self.externalRecordID = externalRecordID
        self.providerWindowStart = providerWindowStart
        self.providerWindowEnd = providerWindowEnd
        self.timingPrecisionRawValue = timingPrecision.rawValue
        self.linkedAt = linkedAt
        self.importedAt = importedAt
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.deviceModel = deviceModel
        self.metadataJSON = metadataJSON
        self.workout = workout
    }
}
