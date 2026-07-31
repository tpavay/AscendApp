import Foundation

struct ProfileUserIdentity:
    Equatable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    let userId: String
    var unresolvedIdentity: UnresolvedUserIdentity
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
        self.unresolvedIdentity = UnresolvedUserIdentity(
            displayName: displayName,
            photoURL: photoURL
        )
        self.age = age
        self.gender = gender
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.locationCity = locationCity
        self.locationCountryCode = locationCountryCode
        self.locationRegionCode = locationRegionCode
        self.joinedAt = joinedAt
    }

    func applyingPresentationFallback(
        displayName: String,
        photoURL: URL?,
        joinedAt: Date? = nil
    ) -> ProfileUserIdentity {
        var copy = self
        copy.unresolvedIdentity = unresolvedIdentity.applyingFallback(
            displayName: displayName,
            photoURL: photoURL
        )
        if copy.joinedAt == nil {
            copy.joinedAt = joinedAt
        }
        return copy
    }

    var demographicsSnapshot: ProfileDemographicsSnapshot {
        ProfileDemographicsSnapshot(
            userId: userId,
            age: age,
            gender: gender,
            weightKg: weightKg,
            heightCm: heightCm,
            locationCity: locationCity,
            locationCountryCode: locationCountryCode,
            locationRegionCode: locationRegionCode,
            joinedAt: joinedAt
        )
    }

    var description: String {
        "<redacted profile identity>"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["identity": "<redacted>"],
            displayStyle: .struct
        )
    }
}
