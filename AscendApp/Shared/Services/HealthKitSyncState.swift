//
//  HealthKitSyncState.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit

enum AppleHealthConnectionState {
    case unavailable
    case neverConnected
    case connected
    case revoked
}

enum HealthKitSyncState {
    private static let hasRequestedAuthorizationKey = "healthKit.hasRequestedAuthorization"
    private static let hasCompletedInitialBackfillKey = "healthKit.hasCompletedInitialBackfill"
    private static let lastSuccessfulCheckAtKey = "healthKit.lastSuccessfulCheckAt"
    private static let workoutAnchorDataKey = "healthKit.workoutAnchorData"
    private static let cachedWorkoutSamplesKey = "healthKit.cachedWorkoutSamples"

    static var hasRequestedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedAuthorizationKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRequestedAuthorizationKey) }
    }

    static var hasCompletedInitialBackfill: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedInitialBackfillKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedInitialBackfillKey) }
    }

    static var lastSuccessfulCheckAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSuccessfulCheckAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSuccessfulCheckAtKey) }
    }

    static var workoutAnchorData: Data? {
        get { UserDefaults.standard.data(forKey: workoutAnchorDataKey) }
        set { UserDefaults.standard.set(newValue, forKey: workoutAnchorDataKey) }
    }

    static var cachedWorkoutSamples: [HealthKitWorkoutSample] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedWorkoutSamplesKey) else {
                return []
            }

            return (try? JSONDecoder().decode([HealthKitWorkoutSample].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: cachedWorkoutSamplesKey)
        }
    }

    static func updateCachedWorkoutSamples(
        added: [HealthKitWorkoutSample],
        deletedExternalRecordIDs: [String]
    ) {
        var samplesByID = Dictionary(uniqueKeysWithValues: cachedWorkoutSamples.map { ($0.externalRecordID, $0) })

        for sample in added {
            samplesByID[sample.externalRecordID] = sample
        }

        for externalRecordID in deletedExternalRecordIDs {
            samplesByID.removeValue(forKey: externalRecordID)
        }

        cachedWorkoutSamples = samplesByID.values.sorted { lhs, rhs in
            lhs.startDate > rhs.startDate
        }
    }

    static func archive(anchor: HKQueryAnchor?) -> Data? {
        guard let anchor else { return nil }

        return try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func unarchiveAnchor(from data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }

        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
