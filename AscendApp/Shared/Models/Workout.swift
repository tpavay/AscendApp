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
    // Placeholders for integrations that were never built. No build has ever set either, and both
    // are now refused on the way out: `WorkoutRemoteSyncMapper.supportedSourceRawValues` throws
    // `unsupportedSource`, and `isValidWorkoutSource` in `firestore.rules` denies the write. They
    // stay declared only because removing a case changes the persisted shape - see
    // `ascend-data-migration`. Reviving either means adding it back to both of those first.
    case garmin = "garmin"
    case fitbit = "fitbit"
    case hevy = "hevy"               // Legacy import source retained for old synced workouts
    case headphoneMotion = "headphone_motion" // Live tracking from compatible headphones

    /// Only sources Ascend can still produce. The other cases stay readable so stored rows from
    /// before manual logging and Apple Health import were removed keep rendering everywhere, but
    /// offering them as filters advertises features that are gone.
    static var filterOptions: [WorkoutSource] {
        [.headphoneMotion]
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
    var lastRemoteHeartRateSeriesReferenceData: Data?
    var heartRateRestoreStatusRawValue: String = WorkoutHeartRateRestoreStatus.notNeeded.rawValue
    var heartRateRestoreErrorCode: String?
    var remoteSyncStatusRawValue: String = WorkoutRemoteSyncStatus.pendingUpsert.rawValue
    var lastRemoteSyncError: String?
    var avgHeartRate: Int? // Average heart rate in BPM
    var maxHeartRate: Int? // Maximum heart rate in BPM
    var caloriesBurned: Int? // Calories burned during workout
    var effortRating: Double? // Effort rating on 1-5 scale
    var heartRateData: Data? // Encoded heart rate time series data
    var averageMETs: Double? // Average METs from Apple Health

    // Data integrity and source tracking
    //
    // Stored as its raw value, like every other enum on this model. A Codable enum cannot appear
    // in a `#Predicate` - SwiftData rejects it with `unsupportedPredicate` - which forced source
    // filtering to happen by scanning the whole store (ASCEND-IOS-1K).
    var sourceRawValue: String = WorkoutSource.manual.rawValue
    var integrityLevel: DataIntegrityLevel // Verified vs unverified data

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }
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

    init(name: String = "", date: Date = Date(), duration: TimeInterval, steps: Int, floors: Int, stepsPerFloor: Int = Workout.defaultStepsPerFloor, notes: String = "", avgHeartRate: Int? = nil, maxHeartRate: Int? = nil, caloriesBurned: Int? = nil, effortRating: Double? = nil, heartRateTimeSeries: [HeartRateDataPoint]? = nil, averageMETs: Double? = nil, source: WorkoutSource, deviceModel: String? = nil, sourceMetadata: String? = nil, healthKitUUID: String? = nil, hevyWorkoutId: String? = nil, photos: [Photo] = [], highlightedPhotoId: UUID? = nil, weightConfiguration: WeightConfiguration? = nil) {
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
        self.lastRemoteHeartRateSeriesReferenceData = nil
        self.remoteSyncStatusRawValue = WorkoutRemoteSyncStatus.pendingUpsert.rawValue
        self.lastRemoteSyncError = nil
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.caloriesBurned = caloriesBurned
        self.effortRating = effortRating
        self.heartRateData = heartRateTimeSeries?.encoded
        self.averageMETs = averageMETs
        
        // Set data integrity fields
        self.sourceRawValue = source.rawValue
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

    /// Whether this climb's current payload is in the cloud.
    ///
    /// The one question the sync surface is allowed to ask. Gating on the retry machinery instead -
    /// `== .rejected`, or a view-local in-flight flag - is what made the warning vanish the instant
    /// a climber tapped retry, and vanish again when that retry was refused. `pendingUpsert`,
    /// `failed` and `rejected` are all "not in the cloud", so none of them can unmount it.
    ///
    /// Computed, so it adds no column and needs no migration.
    var isSyncedToCloud: Bool {
        remoteSyncStatus == .synced
    }

    func markPendingRemoteUpsert(ownerUserId: String, modifiedAt: Date = Date()) {
        self.ownerUserId = ownerUserId
        lastModifiedAt = modifiedAt
        remoteSyncStatus = .pendingUpsert
        lastRemoteSyncError = nil
    }

    func markRemoteSyncSucceeded(
        syncedAt: Date = Date(),
        heartRateSeries: FirestoreWorkoutHeartRateSeriesReference?
    ) {
        lastRemoteSyncAt = syncedAt
        lastRemoteHeartRateSeriesReference = heartRateSeries
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

    var heartRateRestoreStatus: WorkoutHeartRateRestoreStatus {
        get {
            WorkoutHeartRateRestoreStatus(rawValue: heartRateRestoreStatusRawValue) ?? .notNeeded
        }
        set {
            heartRateRestoreStatusRawValue = newValue.rawValue
        }
    }

    var lastHeartRateSidecarFailure: WorkoutHeartRateSidecarError? {
        heartRateRestoreErrorCode.flatMap(WorkoutHeartRateSidecarError.init(rawValue:))
    }

    /// The last heart-rate sidecar reference this device saw on the remote workout envelope. Cached
    /// in full (not just its path) so a local upsert can carry a still-unrestored sidecar forward
    /// instead of orphaning it.
    var lastRemoteHeartRateSeriesReference: FirestoreWorkoutHeartRateSeriesReference? {
        get {
            guard let lastRemoteHeartRateSeriesReferenceData else { return nil }
            return try? JSONDecoder().decode(
                FirestoreWorkoutHeartRateSeriesReference.self,
                from: lastRemoteHeartRateSeriesReferenceData
            )
        }
        set {
            lastRemoteHeartRateSeriesStoragePath = newValue?.storagePath
            lastRemoteHeartRateSeriesReferenceData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
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

    var isInAppSensorWorkout: Bool {
        switch source {
        case .headphoneMotion:
            return true
        case .manual, .appleHealth, .garmin, .fitbit, .hevy:
            return false
        }
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
