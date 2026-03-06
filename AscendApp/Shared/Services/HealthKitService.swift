//
//  HealthKitService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import Foundation
import HealthKit

@MainActor
@Observable
class HealthKitService {
    static let shared = HealthKitService()

    private let authorizationRequestedKey = "healthKitAuthorizationRequested"
    private let healthStore = HKHealthStore()

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

    var authorizationStatus: HKAuthorizationStatus = .notDetermined
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unknown
    var hasRequestedAuthorization = false
    var isHealthDataAvailable = false
    var lastPermissionErrorMessage: String?

    private init() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        hasRequestedAuthorization = UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        checkAuthorizationStatus()

        Task {
            await refreshAuthorizationRequestStatus()
        }
    }

    // MARK: - Authorization

    private func checkAuthorizationStatus() {
        guard isHealthDataAvailable else { return }

        let workoutType = HKObjectType.workoutType()
        authorizationStatus = healthStore.authorizationStatus(for: workoutType)
    }

    private func statusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .sharingDenied:
            return "sharingDenied"
        case .sharingAuthorized:
            return "sharingAuthorized"
        @unknown default:
            return "unknown"
        }
    }

    private func requestStatusDescription(_ status: HKAuthorizationRequestStatus) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .shouldRequest:
            return "shouldRequest"
        case .unnecessary:
            return "unnecessary"
        @unknown default:
            return "unknown"
        }
    }

    func refreshAuthorizationRequestStatus() async {
        guard isHealthDataAvailable else {
            authorizationRequestStatus = .unknown
            return
        }

        let status = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: [],
                read: readTypes
            ) { requestStatus, _ in
                continuation.resume(returning: requestStatus)
            }
        }

        authorizationRequestStatus = status
    }

    func hasPermissionToReadWorkouts() -> Bool {
        guard isHealthDataAvailable else {
            print("❌ HealthKit data not available")
            return false
        }

        // Apple doesn't expose a reliable read-permission status for workout/quantity reads.
        // We treat "authorization has been requested at least once" as the best available signal.
        return hasRequestedAuthorization
    }

    func requestPermission() async -> Bool {
        guard isHealthDataAvailable else {
            lastPermissionErrorMessage = "Apple Health is not available on this device."
            return false
        }

        do {
            print("🏥 Requesting HealthKit permission...")
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)

            UserDefaults.standard.set(true, forKey: authorizationRequestedKey)
            hasRequestedAuthorization = true
            lastPermissionErrorMessage = nil
            checkAuthorizationStatus()
            await refreshAuthorizationRequestStatus()

            let newStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            print("🏥 New authorization status after request: \(statusDescription(newStatus))")
            print("🏥 Authorization request status: \(requestStatusDescription(authorizationRequestStatus))")

            // If requestAuthorization succeeds, HealthKit accepted the request flow.
            // Read-level grants are determined by Health app settings and query results.
            return true
        } catch {
            let message = error.localizedDescription
            lastPermissionErrorMessage = message
            print("❌ HealthKit permission request error: \(message)")
            return false
        }
    }

    // MARK: - Data Fetching

    private func stairWorkoutPredicate() -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .stairClimbing),
            HKQuery.predicateForWorkouts(with: .stepTraining)
        ])
    }

    func fetchStairStepperWorkouts(from startDate: Date? = nil) async -> [HKWorkout] {
        guard isHealthDataAvailable else { return [] }

        let workoutType = HKObjectType.workoutType()
        var predicates: [NSPredicate] = [stairWorkoutPredicate()]

        if let startDate = startDate {
            let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
            predicates.append(datePredicate)
        }

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compoundPredicate,
                limit: 1000,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    print("❌ HealthKit workout query failed: \(error.localizedDescription)")
                }
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    /// Fetches stair-related workouts that overlap with a given time range
    /// Used for linking Apple Health data to Hevy workouts
    func fetchWorkoutsInTimeRange(start: Date, end: Date, toleranceMinutes: Int = 15) async -> [HKWorkout] {
        guard isHealthDataAvailable else { return [] }

        let workoutType = HKObjectType.workoutType()

        // Expand the search range by tolerance
        let expandedStart = Calendar.current.date(byAdding: .minute, value: -toleranceMinutes, to: start)!
        let expandedEnd = Calendar.current.date(byAdding: .minute, value: toleranceMinutes, to: end)!

        let datePredicate = HKQuery.predicateForSamples(withStart: expandedStart, end: expandedEnd, options: .strictStartDate)
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [stairWorkoutPredicate(), datePredicate])

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compoundPredicate,
                limit: 100,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    print("❌ HealthKit time-range query failed: \(error.localizedDescription)")
                }
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    func fetchWorkoutMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        var metrics = WorkoutMetrics()
        
        // Fetch steps - only if available for this workout
        if let stepCount = await fetchQuantityData(
            for: .stepCount,
            during: workout.startDate...workout.endDate
        ) {
            metrics.steps = Int(stepCount)
        }
        
        // Fetch heart rate data (both average and time-series)
        let heartRateData = await fetchHeartRateData(during: workout.startDate...workout.endDate)
        metrics.avgHeartRate = heartRateData.average
        metrics.maxHeartRate = heartRateData.maximum
        
        // Fetch time-series heart rate for charting
        metrics.heartRateTimeSeries = await fetchHeartRateTimeSeries(during: workout.startDate...workout.endDate)
        
        // Extract Average METs from workout metadata
        if let avgMetsQuantity = workout.metadata?["HKAverageMETs"] as? HKQuantity {
            let metsUnit = HKUnit.kilocalorie().unitDivided(by: HKUnit.hour().unitMultiplied(by: HKUnit.gramUnit(with: .kilo)))
            let metsValue = avgMetsQuantity.doubleValue(for: metsUnit)
            metrics.averageMETs = metsValue
        }
        
        // Get active calories using the recommended approach
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let caloriesStatistics = workout.statistics(for: activeEnergyType) {
            let totalCalories = caloriesStatistics.sumQuantity()
            metrics.caloriesBurned = Int(totalCalories?.doubleValue(for: .kilocalorie()) ?? 0)
        }
        
        // Get resting calories
        if let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
           let restingCaloriesStatistics = workout.statistics(for: basalEnergyType) {
            let restingCalories = restingCaloriesStatistics.sumQuantity()
            metrics.restingCaloriesBurned = Int(restingCalories?.doubleValue(for: .kilocalorie()) ?? 0)
        }
        
        return metrics
    }
    
    private func fetchQuantityData(for identifier: HKQuantityTypeIdentifier, during dateRange: ClosedRange<Date>) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: sum > 0 ? sum : nil)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchHeartRateData(during dateRange: ClosedRange<Date>) async -> (average: Int?, maximum: Int?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, result, _ in
                let average = result?.averageQuantity()?.doubleValue(for: unit)
                let maximum = result?.maximumQuantity()?.doubleValue(for: unit)
                
                continuation.resume(returning: (
                    average: average != nil ? Int(average!) : nil,
                    maximum: maximum != nil ? Int(maximum!) : nil
                ))
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchHeartRateTimeSeries(during dateRange: ClosedRange<Date>) async -> [HeartRateDataPoint] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let dataPoints = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateDataPoint(
                        timestamp: sample.startDate,
                        heartRate: Int(sample.quantity.doubleValue(for: unit))
                    )
                } ?? []
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
    }
}

struct WorkoutMetrics {
    var steps: Int?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var caloriesBurned: Int? // Active calories
    var restingCaloriesBurned: Int? // Resting/basal calories
    var heartRateTimeSeries: [HeartRateDataPoint] = []
    var averageMETs: Double? // Average METs from workout metadata
}

extension HKWorkout {
    func toAscendWorkout(with metrics: WorkoutMetrics, stepsPerFloor: Int) -> Workout {
        // Detect if workout came from Apple Watch based on source device
        let deviceName = sourceRevision.source.name
        let isFromAppleWatch = deviceName.contains("Apple Watch") || deviceName.contains("Watch")
        
        // Create source metadata with device info
        let sourceMetadata = """
        {
            "sourceDevice": "\(deviceName)",
            "sourceBundleIdentifier": "\(sourceRevision.source.bundleIdentifier)",
            "workoutActivityType": "\(workoutActivityType.rawValue)",
            "isFromAppleWatch": \(isFromAppleWatch)
        }
        """
        
        // Calculate both steps and floors - Apple Health provides steps only
        let steps = metrics.steps ?? 0
        let floors = Workout.stepsToFloors(steps, stepsPerFloor: stepsPerFloor)
        
        let workout = Workout(
            name: Workout.generateDefaultName(for: startDate),
            date: startDate,
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            avgHeartRate: metrics.avgHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            caloriesBurned: metrics.caloriesBurned,
            heartRateTimeSeries: metrics.heartRateTimeSeries,
            averageMETs: metrics.averageMETs,
            source: .appleHealth,
            deviceModel: deviceName,
            sourceMetadata: sourceMetadata,
            healthKitUUID: uuid.uuidString
        )
        return workout
    }
}
