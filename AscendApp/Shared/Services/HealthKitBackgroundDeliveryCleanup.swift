//
//  HealthKitBackgroundDeliveryCleanup.swift
//  AscendApp
//

import Foundation
import HealthKit

/// Retires the workout background-delivery registration Ascend made while it still imported
/// workouts.
///
/// The observer query that serviced it is gone, but the registration is HealthKit's, not the
/// app's: it survives the upgrade and keeps iOS waking Ascend every time a workout is written, for
/// a feature that no longer exists. Deleting the code that created it does not withdraw it - only
/// asking HealthKit does.
///
/// It runs exactly once per install. HealthKit does not guarantee this completion handler ever
/// fires, so the flag is set on dispatch rather than on success: retrying every launch forever is
/// a worse outcome than one device keeping a stale registration because the single request failed.
@MainActor
final class HealthKitBackgroundDeliveryCleanup {
    static let shared = HealthKitBackgroundDeliveryCleanup()

    private static let didRetireImportBackgroundDeliveryKey = "healthKit.didRetireImportBackgroundDelivery"

    private let defaults: UserDefaults
    /// HealthKit drops an in-flight request whose store has been released.
    private var healthStore: HKHealthStore?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func retireImportBackgroundDeliveryIfNeeded() {
        guard !defaults.bool(forKey: Self.didRetireImportBackgroundDeliveryKey) else { return }
        defaults.set(true, forKey: Self.didRetireImportBackgroundDeliveryKey)

        guard HKHealthStore.isHealthDataAvailable() else { return }

        let healthStore = HKHealthStore()
        self.healthStore = healthStore
        healthStore.disableAllBackgroundDelivery { [weak self] _, _ in
            Task { @MainActor in
                self?.healthStore = nil
            }
        }
    }
}
