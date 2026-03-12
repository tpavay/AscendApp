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
    var hasCompletedInitialBackfill: Bool { get }
    var authorizationRequestStatus: HKAuthorizationRequestStatus { get }
    var lastPermissionErrorMessage: String? { get }
    var connectionState: AppleHealthConnectionState { get }
    func refreshAuthorizationRequestStatus() async
    func requestAuthorization() async -> Bool
}

@MainActor
@Observable
final class HealthKitAuthorizationClient: HealthKitAuthorizationControlling {
    static let shared = HealthKitAuthorizationClient()

    private let healthStore: HKHealthStore

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let restingEnergy = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) {
            types.insert(restingEnergy)
        }

        return types
    }

    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unknown
    var lastPermissionErrorMessage: String?
    var isHealthDataAvailable: Bool

    var hasRequestedAuthorization: Bool {
        HealthKitSyncState.hasRequestedAuthorization
    }

    var hasCompletedInitialBackfill: Bool {
        HealthKitSyncState.hasCompletedInitialBackfill
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
            return
        }

        let status = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { requestStatus, _ in
                continuation.resume(returning: requestStatus)
            }
        }

        authorizationRequestStatus = status
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
