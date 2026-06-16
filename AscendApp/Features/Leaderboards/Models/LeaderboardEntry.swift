import Foundation

struct LeaderboardEntry: Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let displayName: String
    let photoURL: URL?
    let rank: Int
    let value: Double
    let formattedValue: String
    let isCurrentUser: Bool

    init(
        userId: String,
        displayName: String,
        photoURL: URL? = nil,
        rank: Int,
        value: Double,
        formattedValue: String,
        isCurrentUser: Bool = false
    ) {
        self.id = userId
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.rank = rank
        self.value = value
        self.formattedValue = formattedValue
        self.isCurrentUser = isCurrentUser
    }
}

struct FirestoreLeaderboardStats: Codable, Equatable, Sendable {
    let userId: String
    let displayName: String
    let photoURL: String?
    let timeFrame: String
    let schemaVersion: Int
    let periodKey: String
    let periodStartAt: Date
    let totalSteps: Int
    let totalFloors: Int
    let totalWorkouts: Int
    let totalDuration: Double
    let stepsPerMinute: Double
    let lastUpdated: Date
    let age: Int?
    let weightKg: Double?
    let locationCity: String?
    let locationCountry: String?
    let locationRegion: String?

    init(
        userId: String,
        displayName: String,
        photoURL: String? = nil,
        timeFrame: String,
        schemaVersion: Int,
        periodKey: String,
        periodStartAt: Date,
        totalSteps: Int,
        totalFloors: Int,
        totalWorkouts: Int,
        totalDuration: Double,
        stepsPerMinute: Double,
        lastUpdated: Date,
        age: Int? = nil,
        weightKg: Double? = nil,
        locationCity: String? = nil,
        locationCountry: String? = nil,
        locationRegion: String? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.timeFrame = timeFrame
        self.schemaVersion = schemaVersion
        self.periodKey = periodKey
        self.periodStartAt = periodStartAt
        self.totalSteps = totalSteps
        self.totalFloors = totalFloors
        self.totalWorkouts = totalWorkouts
        self.totalDuration = totalDuration
        self.stepsPerMinute = stepsPerMinute
        self.lastUpdated = lastUpdated
        self.age = age
        self.weightKg = weightKg
        self.locationCity = locationCity
        self.locationCountry = locationCountry
        self.locationRegion = locationRegion
    }

    func value(for metric: LeaderboardMetric) -> Double {
        switch metric {
        case .climb:
            return Double(totalSteps)
        case .workouts:
            return Double(totalWorkouts)
        case .duration:
            return totalDuration
        case .pace:
            return stepsPerMinute
        }
    }
}
