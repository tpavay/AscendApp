import Foundation

struct LeaderboardProfileSnapshot: Equatable, Sendable {
    let userId: String
    let age: Int?
    let weightKg: Double?
    let locationCity: String?
    let locationCountry: String?
    let locationRegion: String?

    init(
        userId: String,
        age: Int? = nil,
        weightKg: Double? = nil,
        locationCity: String? = nil,
        locationCountry: String? = nil,
        locationRegion: String? = nil
    ) {
        self.userId = userId
        self.age = age
        self.weightKg = weightKg
        self.locationCity = Self.normalizedProfileText(locationCity)
        self.locationCountry = Self.normalizedCountryCode(locationCountry)
        self.locationRegion = Self.normalizedProfileText(locationRegion)
    }

    init(userId: String, userData: UserDisplayNameData) {
        self.init(
            userId: userId,
            age: userData.age,
            weightKg: userData.weightKg,
            locationCity: userData.locationCity,
            locationCountry: userData.locationCountry,
            locationRegion: userData.locationRegion
        )
    }

    private static func normalizedProfileText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum LeaderboardAgeGroup: String, CaseIterable, Identifiable, Sendable {
    case age13To17 = "13_17"
    case age18To24 = "18_24"
    case age25To29 = "25_29"
    case age30To34 = "30_34"
    case age35To39 = "35_39"
    case age40To44 = "40_44"
    case age45To49 = "45_49"
    case age50To54 = "50_54"
    case age55To59 = "55_59"
    case age60To64 = "60_64"
    case age65Plus = "65_plus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .age13To17: return "13-17"
        case .age18To24: return "18-24"
        case .age25To29: return "25-29"
        case .age30To34: return "30-34"
        case .age35To39: return "35-39"
        case .age40To44: return "40-44"
        case .age45To49: return "45-49"
        case .age50To54: return "50-54"
        case .age55To59: return "55-59"
        case .age60To64: return "60-64"
        case .age65Plus: return "65+"
        }
    }

    func contains(age: Int?) -> Bool {
        guard let age else { return false }

        switch self {
        case .age13To17: return (13...17).contains(age)
        case .age18To24: return (18...24).contains(age)
        case .age25To29: return (25...29).contains(age)
        case .age30To34: return (30...34).contains(age)
        case .age35To39: return (35...39).contains(age)
        case .age40To44: return (40...44).contains(age)
        case .age45To49: return (45...49).contains(age)
        case .age50To54: return (50...54).contains(age)
        case .age55To59: return (55...59).contains(age)
        case .age60To64: return (60...64).contains(age)
        case .age65Plus: return age >= 65
        }
    }
}

enum LeaderboardBodyWeightFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pounds200Plus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All weights"
        case .pounds200Plus: return "200+ lb"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .all: return "Weight"
        case .pounds200Plus: return "200+ lb"
        }
    }

    func contains(weightKg: Double?) -> Bool {
        switch self {
        case .all:
            return true
        case .pounds200Plus:
            guard let weightKg else { return false }
            let thresholdKg = MeasurementSystem.imperial.convertWeight(200, to: .metric)
            return weightKg >= thresholdKg
        }
    }
}

enum LeaderboardLocationFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case currentCity
    case currentRegion
    case currentCountry

    var id: String { rawValue }

    var shortDisplayName: String {
        switch self {
        case .all: return "Location"
        case .currentCity: return "City"
        case .currentRegion: return "Region"
        case .currentCountry: return "Country"
        }
    }

    func displayName(currentUserProfile: LeaderboardProfileSnapshot?) -> String {
        switch self {
        case .all:
            return "All locations"
        case .currentCity:
            return currentUserProfile?.locationCity ?? "My city"
        case .currentRegion:
            return currentUserProfile?.locationRegion ?? "My region"
        case .currentCountry:
            return currentUserProfile?.locationCountry ?? "My country"
        }
    }

    func isAvailable(currentUserProfile: LeaderboardProfileSnapshot?) -> Bool {
        guard let currentUserProfile else { return self == .all }

        switch self {
        case .all:
            return true
        case .currentCity:
            return currentUserProfile.locationCity?.isEmpty == false &&
                currentUserProfile.locationCountry?.isEmpty == false
        case .currentRegion:
            return currentUserProfile.locationRegion?.isEmpty == false &&
                currentUserProfile.locationCountry?.isEmpty == false
        case .currentCountry:
            return currentUserProfile.locationCountry?.isEmpty == false
        }
    }

    func contains(
        stats: FirestoreLeaderboardStats,
        currentUserProfile: LeaderboardProfileSnapshot?
    ) -> Bool {
        guard self != .all else { return true }
        guard let currentUserProfile else { return false }

        switch self {
        case .all:
            return true
        case .currentCity:
            return normalized(stats.locationCountry) == normalized(currentUserProfile.locationCountry) &&
                normalized(stats.locationCity) == normalized(currentUserProfile.locationCity)
        case .currentRegion:
            return normalized(stats.locationCountry) == normalized(currentUserProfile.locationCountry) &&
                normalized(stats.locationRegion) == normalized(currentUserProfile.locationRegion)
        case .currentCountry:
            return normalized(stats.locationCountry) == normalized(currentUserProfile.locationCountry)
        }
    }

    private func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? ""
    }
}
