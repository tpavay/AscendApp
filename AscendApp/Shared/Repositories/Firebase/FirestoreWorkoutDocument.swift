import Foundation

struct FirestoreWorkoutDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let userId: String
    let schemaVersion: Int
    let name: String
    let startedAt: Date
    let durationSeconds: Double
    let steps: Int
    let floors: Int
    let stepsPerFloor: Int
    let notes: String
    let source: String
    let integrityLevel: String
    let createdAt: Date
    let updatedAt: Date
    let avgHeartRateBpm: Int?
    let maxHeartRateBpm: Int?
    let caloriesBurned: Int?
    let effortRating: Double?
    let averageMETs: Double?
    let deviceModel: String?
    let sourceMetadata: String?
    let healthKitUUID: String?
    let hevyWorkoutId: String?
    let media: [FirestoreWorkoutMediaItem]?
    let highlightedMediaId: String?
    let weightConfiguration: FirestoreWorkoutWeightConfiguration?
    let heartRateSeries: FirestoreWorkoutHeartRateSeriesReference?

    init(
        userId: String,
        schemaVersion: Int = FirestoreWorkoutDocument.currentSchemaVersion,
        name: String,
        startedAt: Date,
        durationSeconds: Double,
        steps: Int,
        floors: Int,
        stepsPerFloor: Int,
        notes: String,
        source: String,
        integrityLevel: String,
        createdAt: Date,
        updatedAt: Date,
        avgHeartRateBpm: Int? = nil,
        maxHeartRateBpm: Int? = nil,
        caloriesBurned: Int? = nil,
        effortRating: Double? = nil,
        averageMETs: Double? = nil,
        deviceModel: String? = nil,
        sourceMetadata: String? = nil,
        healthKitUUID: String? = nil,
        hevyWorkoutId: String? = nil,
        media: [FirestoreWorkoutMediaItem]? = nil,
        highlightedMediaId: String? = nil,
        weightConfiguration: FirestoreWorkoutWeightConfiguration? = nil,
        heartRateSeries: FirestoreWorkoutHeartRateSeriesReference? = nil
    ) {
        self.userId = userId
        self.schemaVersion = schemaVersion
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.floors = floors
        self.stepsPerFloor = stepsPerFloor
        self.notes = notes
        self.source = source
        self.integrityLevel = integrityLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.avgHeartRateBpm = avgHeartRateBpm
        self.maxHeartRateBpm = maxHeartRateBpm
        self.caloriesBurned = caloriesBurned
        self.effortRating = effortRating
        self.averageMETs = averageMETs
        self.deviceModel = deviceModel
        self.sourceMetadata = sourceMetadata
        self.healthKitUUID = healthKitUUID
        self.hevyWorkoutId = hevyWorkoutId
        self.media = media
        self.highlightedMediaId = highlightedMediaId
        self.weightConfiguration = weightConfiguration
        self.heartRateSeries = heartRateSeries
    }
}
