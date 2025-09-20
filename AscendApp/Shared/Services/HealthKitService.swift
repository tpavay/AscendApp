//
//  HealthKitService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import Foundation
import HealthKit

@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()
    
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isHealthDataAvailable = false
    
    private init() {
        self.isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorizationStatus() {
        guard isHealthDataAvailable else { return }
        
        let workoutType = HKObjectType.workoutType()
        authorizationStatus = healthStore.authorizationStatus(for: workoutType)
    }
    
    func hasPermissionToReadWorkouts() -> Bool {
        guard isHealthDataAvailable else { 
            print("❌ HealthKit data not available")
            return false 
        }
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        print("🏥 HealthKit authorization status: \(status.rawValue)")
        print("🏥 Status description: \(statusDescription(status))")
        
        // HealthKit returns .notDetermined even when user has granted access for privacy reasons
        // We should consider both .sharingAuthorized and .notDetermined as potentially having access
        let hasPermission = status == .sharingAuthorized || status == .notDetermined
        print("🏥 Has permission result: \(hasPermission)")
        return hasPermission
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
    
    func requestPermission() async -> Bool {
        guard isHealthDataAvailable else { return false }
        
        let sampleTypesToRead: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
        ]
        
        do {
            print("🏥 Requesting HealthKit permission...")
            try await healthStore.requestAuthorization(toShare: [], read: sampleTypesToRead)
            checkAuthorizationStatus()
            
            let newStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            print("🏥 New authorization status after request: \(statusDescription(newStatus))")
            
            return hasPermissionToReadWorkouts()
        } catch {
            print("❌ HealthKit permission request error: \(error)")
            return false
        }
    }
    
    // MARK: - Data Fetching
    
    func fetchStairStepperWorkouts(from startDate: Date? = nil) async -> [HKWorkout] {
        guard isHealthDataAvailable else { return [] }
        
        let workoutType = HKObjectType.workoutType()
        let stairClimbingPredicate = HKQuery.predicateForWorkouts(with: .stairClimbing)
        
        var predicates: [NSPredicate] = [stairClimbingPredicate]
        
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
                if let error = error {
                    continuation.resume(returning: [])
                    return
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
            ) { _, result, error in
                if let error = error {
                    print("Error fetching \(identifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
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
            ) { _, result, error in
                if let error = error {
                    // Code 11 means "No data available" - this is normal for workouts without heart rate data
                    if (error as NSError).code == 11 {
                        continuation.resume(returning: (nil, nil))
                    } else {
                        print("Error fetching heart rate: \(error)")
                        continuation.resume(returning: (nil, nil))
                    }
                    return
                }
                
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
            ) { _, samples, error in
                if let error = error {
                    // Code 11 means "No data available" - this is normal for workouts without heart rate data
                    if (error as NSError).code == 11 {
                        continuation.resume(returning: [])
                    } else {
                        print("Error fetching heart rate time series: \(error)")
                        continuation.resume(returning: [])
                    }
                    return
                }
                
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
    func toAscendWorkout(with metrics: WorkoutMetrics) -> Workout {
        // Detect if workout came from Apple Watch based on source device
        let deviceName = sourceRevision.source.name ?? "Unknown Device"
        let isFromAppleWatch = deviceName.contains("Apple Watch") || deviceName.contains("Watch")
        
        // Create source metadata with device info
        let sourceMetadata = """
        {
            "sourceDevice": "\(deviceName)",
            "sourceBundleIdentifier": "\(sourceRevision.source.bundleIdentifier ?? "unknown")",
            "workoutActivityType": "\(workoutActivityType.rawValue)",
            "isFromAppleWatch": \(isFromAppleWatch)
        }
        """
        
        let workout = Workout(
            name: "Stair Climbing Workout",
            date: startDate,
            duration: duration,
            steps: metrics.steps,
            floors: nil, // Not available in Apple Health stair stepper workouts
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
