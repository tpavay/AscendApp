import Foundation

struct ProfileUserIdentity: Equatable {
    let userId: String
    var displayName: String
    var photoURL: URL?
    var age: Int?
    var gender: ProfileGender?
    var weightKg: Double?
    var heightCm: Double?
    var locationCity: String?
    var locationCountryCode: String?
    var locationRegionCode: String?
    var joinedAt: Date?

    init(
        userId: String,
        displayName: String,
        photoURL: URL? = nil,
        age: Int? = nil,
        gender: ProfileGender? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        locationCity: String? = nil,
        locationCountryCode: String? = nil,
        locationRegionCode: String? = nil,
        joinedAt: Date? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.age = age
        self.gender = gender
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.locationCity = locationCity
        self.locationCountryCode = locationCountryCode
        self.locationRegionCode = locationRegionCode
        self.joinedAt = joinedAt
    }
}
