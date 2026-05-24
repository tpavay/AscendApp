//
//  Workout.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import Foundation
import SwiftData

enum WorkoutSource: String, CaseIterable, Codable {
    case manual = "manual"           // User entered manually
    case appleHealth = "apple_health" // Imported from Apple Health
    case garmin = "garmin"           // Future: Garmin Connect
    case fitbit = "fitbit"           // Future: Fitbit
    case hevy = "hevy"               // Legacy import source retained for old synced workouts
    case headphoneMotion = "headphone_motion" // Live tracking from compatible headphones

    static var filterOptions: [WorkoutSource] {
        [.manual, .appleHealth, .headphoneMotion]
    }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual Entry"
        case .appleHealth:
            return "Apple Health"
        case .garmin:
            return "Garmin"
        case .fitbit:
            return "Fitbit"
        case .hevy:
            return "Imported Workout"
        case .headphoneMotion:
            return "Headphone Tracking"
        }
    }

    var isVerified: Bool {
        switch self {
        case .manual:
            return false
        case .appleHealth, .garmin, .fitbit, .hevy, .headphoneMotion:
            return true
        }
    }
}

enum WorkoutProvider: String, CaseIterable, Codable, Sendable {
    case appleHealth = "apple_health"
    case garmin = "garmin"
    case fitbit = "fitbit"
    case hevy = "hevy"

    var displayName: String {
        switch self {
        case .appleHealth:
            return "Apple Health"
        case .garmin:
            return "Garmin"
        case .fitbit:
            return "Fitbit"
        case .hevy:
            return "Imported Workout"
        }
    }

    var asWorkoutSource: WorkoutSource {
        switch self {
        case .appleHealth:
            return .appleHealth
        case .garmin:
            return .garmin
        case .fitbit:
            return .fitbit
        case .hevy:
            return .hevy
        }
    }

    init?(workoutSource: WorkoutSource) {
        switch workoutSource {
        case .manual, .headphoneMotion:
            return nil
        case .appleHealth:
            self = .appleHealth
        case .garmin:
            self = .garmin
        case .fitbit:
            self = .fitbit
        case .hevy:
            self = .hevy
        }
    }
}

enum TimingPrecision: String, CaseIterable, Codable, Sendable {
    case exact = "exact"
    case containerWindow = "container_window"
}

enum DataIntegrityLevel: String, CaseIterable, Codable {
    case verified = "verified"       // From trusted wearable sources
    case unverified = "unverified"   // Manual or questionable sources
    
    var displayName: String {
        switch self {
        case .verified:
            return "Verified"
        case .unverified:
            return "Unverified"
        }
    }
}

@Model
class Workout {
    static let defaultStepsPerFloor = 16

    var id: UUID
    var name: String
    var date: Date
    var duration: TimeInterval // Duration in seconds
    var steps: Int // Total steps climbed
    var floors: Int // Total floors climbed
    var stepsPerFloor: Int // Snapshot of conversion rate at workout creation (for historical accuracy)
    var notes: String
    var createdAt: Date
    var ownerUserId: String?
    var lastModifiedAt: Date = Date()
    var lastRemoteSyncAt: Date?
    var lastRemoteHeartRateSeriesStoragePath: String?
    var remoteSyncStatusRawValue: String = WorkoutRemoteSyncStatus.pendingUpsert.rawValue
    var lastRemoteSyncError: String?
    var avgHeartRate: Int? // Average heart rate in BPM
    var maxHeartRate: Int? // Maximum heart rate in BPM
    var caloriesBurned: Int? // Calories burned during workout
    var effortRating: Double? // Effort rating on 1-5 scale
    var heartRateData: Data? // Encoded heart rate time series data
    var averageMETs: Double? // Average METs from Apple Health

    // Data integrity and source tracking
    var source: WorkoutSource // How this workout was created/imported
    var integrityLevel: DataIntegrityLevel // Verified vs unverified data
    var deviceModel: String? // "Apple Watch Series 9", "iPhone 15 Pro", etc.
    var sourceMetadata: String? // Additional source-specific data (JSON string)
    var healthKitUUID: String? // HealthKit workout UUID for deduplication
    var hevyWorkoutId: String? // Hevy workout ID for deduplication
    var photos: [Photo]
    var highlightedPhotoId: UUID? // ID of the photo/video to display on workout cards
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSourceLink.workout)
    var sourceLinks: [WorkoutSourceLink]
    @Relationship(deleteRule: .cascade, inverse: \WorkoutParticipation.workout)
    var participations: [WorkoutParticipation]

    // Weight equipment tracking - stored as JSON
    var weightConfigurationData: Data?

    // Heat map percentile scores - stored as JSON (snapshot at workout save time)
    var percentileScoresData: Data?
    var effortScoreValue: Double?
    var equivalentLevelValue: Int?

    // Computed property for easy access to weight configuration
    var weightConfiguration: WeightConfiguration? {
        get {
            WeightConfiguration.decode(from: weightConfigurationData)
        }
        set {
            weightConfigurationData = newValue?.encoded
        }
    }

    /// Whether this workout has any weight equipment configured
    var hasWeights: Bool {
        !(weightConfiguration?.isEmpty ?? true)
    }

    var weightLoadoutKey: WeightLoadoutKey? {
        WeightLoadoutKey(configuration: weightConfiguration)
    }

    // Computed property for easy access to percentile scores
    var percentileScores: [String: Double]? {
        get {
            guard let data = percentileScoresData else { return nil }
            return try? JSONDecoder().decode([String: Double].self, from: data)
        }
        set {
            if let newValue = newValue {
                percentileScoresData = try? JSONEncoder().encode(newValue)
            } else {
                percentileScoresData = nil
            }
        }
    }

    /// Get the stored percentile score for a specific heat map metric
    func percentileScore(for metric: HeatMapMetric) -> Double? {
        percentileScores?[metric.rawValue]
    }

    /// Set the percentile score for a specific heat map metric
    func setPercentileScore(_ score: Double, for metric: HeatMapMetric) {
        var scores = percentileScores ?? [:]
        scores[metric.rawValue] = score
        percentileScores = scores
    }

    var equivalentLevel: Int? {
        get { equivalentLevelValue }
        set { equivalentLevelValue = newValue.map(SPMMappingService.clampedLevel) }
    }

    /// Total weight used in this workout (for display)
    var totalWeightUsed: Double {
        weightConfiguration?.totalWeight ?? 0
    }

    init(name: String = "", date: Date = Date(), duration: TimeInterval, steps: Int, floors: Int, stepsPerFloor: Int = Workout.defaultStepsPerFloor, notes: String = "", avgHeartRate: Int? = nil, maxHeartRate: Int? = nil, caloriesBurned: Int? = nil, effortRating: Double? = nil, heartRateTimeSeries: [HeartRateDataPoint]? = nil, averageMETs: Double? = nil, source: WorkoutSource = .manual, deviceModel: String? = nil, sourceMetadata: String? = nil, healthKitUUID: String? = nil, hevyWorkoutId: String? = nil, photos: [Photo] = [], highlightedPhotoId: UUID? = nil, weightConfiguration: WeightConfiguration? = nil) {
        let createdAt = Date()
        self.id = UUID()
        self.name = name.isEmpty ? "Workout" : name
        self.date = date
        self.duration = duration
        self.steps = steps
        self.floors = floors
        self.stepsPerFloor = stepsPerFloor
        self.notes = notes
        self.createdAt = createdAt
        self.ownerUserId = nil
        self.lastModifiedAt = createdAt
        self.lastRemoteSyncAt = nil
        self.lastRemoteHeartRateSeriesStoragePath = nil
        self.remoteSyncStatusRawValue = WorkoutRemoteSyncStatus.pendingUpsert.rawValue
        self.lastRemoteSyncError = nil
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.caloriesBurned = caloriesBurned
        self.effortRating = effortRating
        self.heartRateData = heartRateTimeSeries?.encoded
        self.averageMETs = averageMETs
        
        // Set data integrity fields
        self.source = source
        self.integrityLevel = source.isVerified ? .verified : .unverified
        self.deviceModel = deviceModel
        self.sourceMetadata = sourceMetadata
        self.healthKitUUID = healthKitUUID
        self.hevyWorkoutId = hevyWorkoutId
        self.photos = photos
        // Default to first photo if not specified and photos exist
        self.highlightedPhotoId = highlightedPhotoId ?? photos.first?.id
        self.sourceLinks = []
        self.participations = []
        self.weightConfiguration = weightConfiguration
    }

    var remoteSyncStatus: WorkoutRemoteSyncStatus {
        get { WorkoutRemoteSyncStatus(rawValue: remoteSyncStatusRawValue) ?? .pendingUpsert }
        set { remoteSyncStatusRawValue = newValue.rawValue }
    }

    func markPendingRemoteUpsert(ownerUserId: String, modifiedAt: Date = Date()) {
        self.ownerUserId = ownerUserId
        lastModifiedAt = modifiedAt
        remoteSyncStatus = .pendingUpsert
        lastRemoteSyncError = nil
    }

    func markRemoteSyncSucceeded(
        syncedAt: Date = Date(),
        heartRateSeriesStoragePath: String?
    ) {
        lastRemoteSyncAt = syncedAt
        lastRemoteHeartRateSeriesStoragePath = heartRateSeriesStoragePath
        remoteSyncStatus = .synced
        lastRemoteSyncError = nil
    }

    func markRemoteSyncFailed(_ errorMessage: String) {
        remoteSyncStatus = .failed
        lastRemoteSyncError = errorMessage
    }

    func markRemoteSyncRejected(_ errorMessage: String) {
        remoteSyncStatus = .rejected
        lastRemoteSyncError = errorMessage
    }
    
    // Computed properties for convenience
    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        } else {
            return "\(minutes < 10 ? "0" : "")\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
        }
    }
    
    var stepsPerMinute: Double? {
        guard steps > 0, duration > 0 else { return nil }
        return Double(steps) / (duration / 60.0)
    }
    
    // Calculate total vertical climb using settings
    func totalVerticalClimb(stepHeight: Double, measurementSystem: MeasurementSystem) -> Double {
        // Convert step height to meters first
        let stepHeightInMeters = measurementSystem.convertStepHeightToMeters(stepHeight)
        
        // Calculate total climb in meters
        let totalClimbMeters = Double(steps) * stepHeightInMeters
        
        // Convert to user's preferred distance unit
        return measurementSystem.convertMetersToDistanceUnit(totalClimbMeters)
    }
    
    // Get the appropriate unit label for vertical climb display
    func verticalClimbUnit(measurementSystem: MeasurementSystem) -> String {
        return measurementSystem.distanceAbbreviation
    }
    
    // Heart rate time series computed property
    var heartRateTimeSeries: [HeartRateDataPoint] {
        guard let data = heartRateData else { return [] }
        return data.decoded ?? []
    }
    
    // Data integrity computed properties
    var isVerified: Bool {
        return integrityLevel == .verified
    }
    
    var sourceDisplayName: String {
        return source.displayName
    }
    
    var integrityDisplayName: String {
        return integrityLevel.displayName
    }

    var linkedProviders: [WorkoutProvider] {
        sourceLinks
            .map(\.provider)
            .sorted { $0.displayName < $1.displayName }
    }

    var isLiveClimbAttemptWorkout: Bool {
        source == .headphoneMotion &&
            participations.contains { $0.contextType == .climbAttempt }
    }

    func sourceLink(for provider: WorkoutProvider) -> WorkoutSourceLink? {
        sourceLinks.first { $0.provider == provider }
    }

    func hasSourceLink(provider: WorkoutProvider) -> Bool {
        sourceLink(for: provider) != nil
    }
    
    // MARK: - Metric Conversion Helpers
    
    /// Converts steps to floors using Ascend's fixed conversion rate, rounded to whole numbers.
    static func stepsToFloors(_ steps: Int, stepsPerFloor: Int = Workout.defaultStepsPerFloor) -> Int {
        guard stepsPerFloor > 0 else { return 0 }
        return Int((Double(steps) / Double(stepsPerFloor)).rounded())
    }
    
    /// Converts floors to steps using Ascend's fixed conversion rate.
    static func floorsToSteps(_ floors: Int, stepsPerFloor: Int = Workout.defaultStepsPerFloor) -> Int {
        return floors * stepsPerFloor
    }

    /// Generates a default workout name based on time of day
    static func generateDefaultName(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning Stair Stepper"
        case 12..<18: return "Afternoon Stair Stepper"
        default: return "Evening Stair Stepper"
        }
    }

    /// Recalculates floors based on current steps value
    func recalculateFloorsFromSteps() {
        stepsPerFloor = Workout.defaultStepsPerFloor
        floors = Workout.stepsToFloors(steps)
    }
    
    /// Recalculates steps based on current floors value
    func recalculateStepsFromFloors() {
        stepsPerFloor = Workout.defaultStepsPerFloor
        steps = Workout.floorsToSteps(floors)
    }
    
    // MARK: - Highlighted Photo
    
    /// Returns the highlighted photo for display on workout cards.
    /// Falls back to the first photo if no highlighted photo is set or if the highlighted photo was deleted.
    var highlightedPhoto: Photo? {
        if let highlightedId = highlightedPhotoId,
           let photo = photos.first(where: { $0.id == highlightedId }) {
            return photo
        }
        // Fallback to first photo if highlighted photo doesn't exist
        return photos.first
    }

    /// Returns workout media ordered for display with the highlighted item first.
    var orderedPhotosForDisplay: [Photo] {
        guard let highlightedId = highlightedPhotoId,
              let highlightedIndex = photos.firstIndex(where: { $0.id == highlightedId }),
              highlightedIndex != 0 else {
            return photos
        }

        var orderedPhotos = photos
        let highlightedPhoto = orderedPhotos.remove(at: highlightedIndex)
        orderedPhotos.insert(highlightedPhoto, at: 0)
        return orderedPhotos
    }
    
    /// Sets the highlighted photo ID and updates if the specified photo exists
    func setHighlightedPhoto(_ photoId: UUID) {
        guard photos.contains(where: { $0.id == photoId }) else { return }
        highlightedPhotoId = photoId
    }
    
    // MARK: - Streak Calculations
    static func calculateCurrentStreak(from workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Group workouts by date and sort them
        let workoutDates = workouts.map { calendar.startOfDay(for: $0.date) }
        let sortedWorkoutDates = Array(Set(workoutDates)).sorted(by: >)
        
        guard !sortedWorkoutDates.isEmpty else { return 0 }
        
        // Find the most recent workout date
        let mostRecentWorkout = sortedWorkoutDates[0]
        
        // Check if the streak is still active (most recent workout is today or within the last 2 days)
        let daysSinceLastWorkout = calendar.dateComponents([.day], from: mostRecentWorkout, to: today).day ?? 0
        
        // Allow up to 2 days gap (for weekends or rest days)
        if daysSinceLastWorkout > 2 {
            return 0
        }
        
        // Count consecutive days backwards from the most recent workout
        var streak = 0
        var currentDate = mostRecentWorkout
        let workoutDateSet = Set(sortedWorkoutDates)
        
        while workoutDateSet.contains(currentDate) {
            streak += 1
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        return streak
    }
    
    static func calculateWeeklyStreak(from workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        guard !workouts.isEmpty else { return 0 }

        let today = Date()
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return 0
        }

        // Collect all week starts that have at least one workout
        let weekStartsWithActivity: Set<Date> = Set(
            workouts.compactMap { workout in
                calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start
            }
        )

        guard !weekStartsWithActivity.isEmpty else { return 0 }

        // Most recent week that has a workout
        guard let mostRecentActiveWeek = weekStartsWithActivity.max() else {
            return 0
        }

        // If we've gone more than one full week without a workout, streak is broken
        if let weeksSinceMostRecent = calendar.dateComponents([.weekOfYear],
                                                              from: mostRecentActiveWeek,
                                                              to: currentWeekStart).weekOfYear,
           weeksSinceMostRecent > 1 {
            return 0
        }

        // Count consecutive weeks with activity going backwards
        var streak = 0
        var cursor = mostRecentActiveWeek

        while weekStartsWithActivity.contains(cursor) {
            streak += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                break
            }
            cursor = previousWeek
        }

        return streak
    }
    
    static func calculateLongestWeeklyStreak(from workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        guard !workouts.isEmpty else { return 0 }
        
        // Collect all week starts that have at least one workout
        let weekStartsWithActivity: Set<Date> = Set(
            workouts.compactMap { workout in
                calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start
            }
        )
        
        guard !weekStartsWithActivity.isEmpty else { return 0 }
        
        // Sort week starts ascending
        let sortedWeekStarts = weekStartsWithActivity.sorted()
        
        var longestStreak = 1
        var currentStreak = 1
        
        for i in 1..<sortedWeekStarts.count {
            let previousWeek = sortedWeekStarts[i - 1]
            let currentWeek = sortedWeekStarts[i]
            
            // Check if weeks are consecutive
            let weeksDifference = calendar.dateComponents([.weekOfYear], from: previousWeek, to: currentWeek).weekOfYear ?? 0
            
            if weeksDifference == 1 {
                // Consecutive week
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                // Gap in streak, reset
                currentStreak = 1
            }
        }
        
        return longestStreak
    }
    
    static func getWeeklyActivity(from workouts: [Workout], for date: Date = Date()) -> [Date: Bool] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        
        // Get all 7 days of the current week
        var weekDates: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                weekDates.append(calendar.startOfDay(for: day))
            }
        }
        
        // Group workouts by date
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        
        // Create dictionary mapping dates to workout completion
        var weekActivity: [Date: Bool] = [:]
        for date in weekDates {
            weekActivity[date] = workoutDates.contains(date)
        }
        
        return weekActivity
    }
}

// MARK: - Heart Rate Data Extensions
struct HeartRateDataPoint: Codable, Equatable, Sendable {
    let timestamp: Date
    let heartRate: Int
}

extension Array where Element == HeartRateDataPoint {
    var encoded: Data? {
        try? JSONEncoder().encode(self)
    }
}

extension Data {
    var decoded: [HeartRateDataPoint]? {
        try? JSONDecoder().decode([HeartRateDataPoint].self, from: self)
    }
}
