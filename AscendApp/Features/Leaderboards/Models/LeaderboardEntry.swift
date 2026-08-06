import Foundation

struct LeaderboardEntry: Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let unresolvedIdentity: UnresolvedUserIdentity
    /// Standard competition rank ("1, 2, 2, 4") — tied entries share a rank.
    let rank: Int
    let value: Double
    let formattedValue: String
    let isCurrentUser: Bool
    /// Whether at least one other entry shares this rank.
    let isTied: Bool

    init(
        userId: String,
        displayName: String,
        photoURL: URL? = nil,
        rank: Int,
        value: Double,
        formattedValue: String,
        isCurrentUser: Bool = false,
        isTied: Bool = false
    ) {
        self.id = userId
        self.userId = userId
        self.unresolvedIdentity = UnresolvedUserIdentity(
            displayName: displayName,
            photoURL: photoURL
        )
        self.rank = rank
        self.value = value
        self.formattedValue = formattedValue
        self.isCurrentUser = isCurrentUser
        self.isTied = isTied
    }

    init(
        userId: String,
        unresolvedIdentity: UnresolvedUserIdentity,
        rank: Int,
        value: Double,
        formattedValue: String,
        isCurrentUser: Bool = false,
        isTied: Bool = false
    ) {
        self.id = userId
        self.userId = userId
        self.unresolvedIdentity = unresolvedIdentity
        self.rank = rank
        self.value = value
        self.formattedValue = formattedValue
        self.isCurrentUser = isCurrentUser
        self.isTied = isTied
    }

    /// A copy carrying a refreshed profile identity. Every ranking field is preserved:
    /// a profile edit must never move the climber's rank or drop their tie marker.
    /// A nil `displayName` keeps the published identity: the signed-in account
    /// has no name to offer yet, which is not the same as being renamed to one.
    func withProfile(displayName: String?, photoURL: URL?) -> LeaderboardEntry {
        LeaderboardEntry(
            userId: userId,
            unresolvedIdentity: unresolvedIdentity
                .applyingOverrides(displayName: displayName, photoURL: nil)
                .replacingPhotoURL(photoURL),
            rank: rank,
            value: value,
            formattedValue: formattedValue,
            isCurrentUser: isCurrentUser,
            isTied: isTied
        )
    }
}

struct FirestoreLeaderboardStats: Equatable, Sendable {
    let userId: String
    let unresolvedIdentity: UnresolvedUserIdentity
    let identityPolicyVersion: Int
    let identityChangedAt: Date
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
        identityPolicyVersion: Int = PublicClimberIdentity.policyVersion,
        identityChangedAt: Date = .distantPast,
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
        self.unresolvedIdentity = UnresolvedUserIdentity(
            displayName: displayName,
            photoURL: photoURL.flatMap(URL.init(string:))
        )
        self.identityPolicyVersion = identityPolicyVersion
        self.identityChangedAt = identityChangedAt
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

    init(
        userId: String,
        unresolvedIdentity: UnresolvedUserIdentity,
        identityPolicyVersion: Int = PublicClimberIdentity.policyVersion,
        identityChangedAt: Date = .distantPast,
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
        self.unresolvedIdentity = unresolvedIdentity
        self.identityPolicyVersion = identityPolicyVersion
        self.identityChangedAt = identityChangedAt
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

    func identityApplyingOverrides(
        displayName: String?,
        photoURL: String?
    ) -> UnresolvedUserIdentity {
        unresolvedIdentity.applyingOverrides(
            displayName: displayName,
            photoURL: photoURL.flatMap(URL.init(string:))
        )
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
