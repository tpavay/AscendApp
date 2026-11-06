//
//  HealthKitAuthorizationClient.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit
import Observation

@MainActor
protocol HealthKitAuthorizationControlling: AnyObject {
    var isHealthDataAvailable: Bool { get }
    var hasRequestedAuthorization: Bool { get }
    var authorizationRequestStatus: HKAuthorizationRequestStatus { get }
    var lastPermissionErrorMessage: String? { get }
    var connectionState: AppleHealthConnectionState { get }
    /// Whether Ascend can read Health workouts, a wider ask than the heart rate and calories
    /// enrichment needs. A climber connected before import returned answers `neverConnected` here
    /// until they are shown the sheet for the workout types, while `connectionState` - which
    /// enrichment runs on - stays `connected`.
    var importConnectionState: AppleHealthConnectionState { get }
    func refreshAuthorizationRequestStatus() async
    func requestAuthorization() async -> Bool
}

extension HealthKitAuthorizationControlling {
    var importConnectionState: AppleHealthConnectionState { connectionState }
}

@MainActor
@Observable
final class HealthKitAuthorizationClient: HealthKitAuthorizationControlling {
    static let shared = HealthKitAuthorizationClient()

    private let healthStore: HKHealthStore

    /// What enrichment writes back onto a climb Ascend recorded: heart rate becomes the series and
    /// its average and maximum, active energy becomes calories.
    ///
    /// Its own set, apart from `readTypes`, because enrichment's connection state is judged
    /// against exactly this. Judged against the wider import set, every climber who connected
    /// before import returned would read as `revoked` and their heart rate would stop arriving
    /// until they were shown a sheet for types enrichment never reads.
    var enrichmentReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }

        return types
    }

    /// Everything Ascend asks Health for. Ascend requests `toShare: []` and never writes.
    ///
    /// The stair workouts import reads (`workoutType()`), the steps, heart rate and active energy
    /// on a workout's own statistics. Apple Health import returned in 1.3.0;
    /// before it, only the enrichment pair was requested. A type requested but never read is a
    /// permission the climber cannot meaningfully refuse (#353), so this list and the
    /// `NSHealthShareUsageDescription` sentence that prints above the sheet change together.
    ///
    /// Not private so the contract can be pinned by a test: the Health permission sheet is the one
    /// place a climber ever sees this set.
    var readTypes: Set<HKObjectType> {
        var types = enrichmentReadTypes
        types.insert(HKObjectType.workoutType())

        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }

        return types
    }

    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unknown
    /// The request status for the full read set. `shouldRequest` means at least one type has never
    /// been put in front of the climber.
    var importAuthorizationRequestStatus: HKAuthorizationRequestStatus = .unknown
    var lastPermissionErrorMessage: String?
    var isHealthDataAvailable: Bool

    var hasRequestedAuthorization: Bool {
        HealthKitSyncState.hasRequestedAuthorization
    }

    var connectionState: AppleHealthConnectionState {
        guard isHealthDataAvailable else { return .unavailable }
        guard hasRequestedAuthorization else { return .neverConnected }

        switch authorizationRequestStatus {
        case .shouldRequest:
            return .revoked
        case .unnecessary, .unknown:
            return .connected
        @unknown default:
            return .connected
        }
    }

    var importConnectionState: AppleHealthConnectionState {
        guard isHealthDataAvailable else { return .unavailable }
        guard hasRequestedAuthorization else { return .neverConnected }

        // Apple never says whether a read was granted, only whether the climber has been asked.
        // Not yet asked for the workout types is, to the climber, not connected to import - and
        // so is "not heard yet": a pass run before the answer arrives would read Health with no
        // permission, find nothing, and move the anchor past workouts it never saw.
        switch importAuthorizationRequestStatus {
        case .unnecessary:
            return .connected
        case .shouldRequest, .unknown:
            return .neverConnected
        @unknown default:
            return .neverConnected
        }
    }

    private init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        self.isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()

        Task {
            await refreshAuthorizationRequestStatus()
        }
    }

    func refreshAuthorizationRequestStatus() async {
        guard isHealthDataAvailable else {
            authorizationRequestStatus = .unknown
            importAuthorizationRequestStatus = .unknown
            return
        }

        authorizationRequestStatus = await requestStatus(for: enrichmentReadTypes)
        importAuthorizationRequestStatus = await requestStatus(for: readTypes)
    }

    private func requestStatus(for types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: types) { requestStatus, _ in
                continuation.resume(returning: requestStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else {
            lastPermissionErrorMessage = "Apple Health is not available on this device."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            HealthKitSyncState.hasRequestedAuthorization = true
            lastPermissionErrorMessage = nil
            await refreshAuthorizationRequestStatus()
            return true
        } catch {
            lastPermissionErrorMessage = error.localizedDescription
            return false
        }
    }
}
