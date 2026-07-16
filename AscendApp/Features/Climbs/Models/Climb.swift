import CoreLocation
import Foundation

struct Climb: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let city: String
    let country: String
    let continent: String
    let latitude: Double
    let longitude: Double
    let totalHeightMeters: Double
    let totalHeightFeet: Double
    let realClimbableHeightMeters: Double?
    let realClimbableHeightFeet: Double?
    let totalSteps: Int
    let realStairCount: Int?
    let calculatedFloors: Int
    let category: String
    let tier: ClimbTier
    let tags: [String]
    let funFact: String
    let sourceURL: String
    let imageSetVersion: Int
    let releaseState: ClimbReleaseState

    var isAvailable: Bool {
        releaseState.isAvailable
    }

    var isComingSoon: Bool {
        releaseState == .comingSoon
    }

    var isVisibleOnGlobe: Bool {
        releaseState.isVisibleOnGlobe
    }

    var isPublished: Bool {
        releaseState != .hidden && releaseState != .disabled
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayLocation: String {
        "\(city), \(country)"
    }

    var referenceHeightMeters: Double {
        realClimbableHeightMeters ?? totalHeightMeters
    }

    var referenceHeightFeet: Double {
        realClimbableHeightFeet ?? totalHeightFeet
    }

    var referenceStepCount: Int {
        realStairCount ?? totalSteps
    }

    var browsePreviewCameraDistance: CLLocationDistance {
        let footprint = max(
            referenceHeightMeters,
            Double(referenceStepCount) * 0.25,
            Double(calculatedFloors) * 4.5
        )

        switch category.lowercased() {
        case "mountain", "volcano", "rock", "waterfall":
            return clampedCameraDistance(footprint * 300, min: 1_100_000, max: 3_000_000)
        case "bridge", "fortress", "castle", "cathedral", "temple", "pyramid", "stadium":
            return clampedCameraDistance(footprint * 420, min: 320_000, max: 1_500_000)
        default:
            return clampedCameraDistance(footprint * 700, min: 180_000, max: 850_000)
        }
    }

    static let preview = Climb(
        id: "empire-state-building",
        name: "Empire State Building",
        city: "New York",
        country: "USA",
        continent: "North America",
        latitude: 40.7484,
        longitude: -73.9857,
        totalHeightMeters: 381,
        totalHeightFeet: 1_250,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 2_096,
        realStairCount: nil,
        calculatedFloors: 102,
        category: "skyscraper",
        tier: .gold,
        tags: ["city icon", "art deco", "observation deck"],
        funFact: "The Empire State Building opened in 1931 and held the tallest-building title for nearly 40 years.",
        sourceURL: "https://en.wikipedia.org/wiki/Empire_State_Building",
        imageSetVersion: 1,
        releaseState: .available
    )

    static let previewComingSoon = Climb(
        id: "coming-soon-preview",
        name: "Coming Soon",
        city: "Unknown",
        country: "Unknown",
        continent: "Unknown",
        latitude: 0,
        longitude: 0,
        totalHeightMeters: 100,
        totalHeightFeet: 328,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 500,
        realStairCount: nil,
        calculatedFloors: 25,
        category: "tower",
        tier: .bronze,
        tags: ["coming soon"],
        funFact: "A new First Ascent opens here soon.",
        sourceURL: "https://ascendstepper.com",
        imageSetVersion: 1,
        releaseState: .comingSoon
    )

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case city
        case country
        case continent
        case latitude
        case longitude
        case totalHeightMeters
        case totalHeightFeet
        case realClimbableHeightMeters
        case realClimbableHeightFeet
        case totalSteps
        case realStairCount
        case calculatedFloors
        case category
        case tier
        case tags
        case funFact
        case sourceURL
        case imageSetVersion
        case releaseState
        case isPublished
    }

    init(
        id: String,
        name: String,
        city: String,
        country: String,
        continent: String,
        latitude: Double,
        longitude: Double,
        totalHeightMeters: Double,
        totalHeightFeet: Double,
        realClimbableHeightMeters: Double?,
        realClimbableHeightFeet: Double?,
        totalSteps: Int,
        realStairCount: Int?,
        calculatedFloors: Int,
        category: String,
        tier: ClimbTier,
        tags: [String],
        funFact: String,
        sourceURL: String,
        imageSetVersion: Int = 1,
        releaseState: ClimbReleaseState = .available,
        isPublished: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.country = country
        self.continent = continent
        self.latitude = latitude
        self.longitude = longitude
        self.totalHeightMeters = totalHeightMeters
        self.totalHeightFeet = totalHeightFeet
        self.realClimbableHeightMeters = realClimbableHeightMeters
        self.realClimbableHeightFeet = realClimbableHeightFeet
        self.totalSteps = totalSteps
        self.realStairCount = realStairCount
        self.calculatedFloors = calculatedFloors
        self.category = category
        self.tier = tier
        self.tags = tags
        self.funFact = funFact
        self.sourceURL = sourceURL
        self.imageSetVersion = imageSetVersion
        if isPublished == false {
            self.releaseState = .hidden
        } else {
            self.releaseState = releaseState
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decode(String.self, forKey: .city)
        country = try container.decode(String.self, forKey: .country)
        continent = try container.decode(String.self, forKey: .continent)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        totalHeightMeters = try container.decode(Double.self, forKey: .totalHeightMeters)
        totalHeightFeet = try container.decode(Double.self, forKey: .totalHeightFeet)
        realClimbableHeightMeters = try container.decodeIfPresent(Double.self, forKey: .realClimbableHeightMeters)
        realClimbableHeightFeet = try container.decodeIfPresent(Double.self, forKey: .realClimbableHeightFeet)
        totalSteps = try container.decode(Int.self, forKey: .totalSteps)
        realStairCount = try container.decodeIfPresent(Int.self, forKey: .realStairCount)
        calculatedFloors = try container.decode(Int.self, forKey: .calculatedFloors)
        category = try container.decode(String.self, forKey: .category)
        tier = try container.decode(ClimbTier.self, forKey: .tier)
        tags = try container.decode([String].self, forKey: .tags)
        funFact = try container.decode(String.self, forKey: .funFact)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        imageSetVersion = try container.decodeIfPresent(Int.self, forKey: .imageSetVersion) ?? 1
        if let decodedReleaseState = try container.decodeIfPresent(ClimbReleaseState.self, forKey: .releaseState) {
            releaseState = decodedReleaseState
        } else if try container.decodeIfPresent(Bool.self, forKey: .isPublished) == false {
            releaseState = .hidden
        } else {
            releaseState = .available
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encode(continent, forKey: .continent)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(totalHeightMeters, forKey: .totalHeightMeters)
        try container.encode(totalHeightFeet, forKey: .totalHeightFeet)
        try container.encodeIfPresent(realClimbableHeightMeters, forKey: .realClimbableHeightMeters)
        try container.encodeIfPresent(realClimbableHeightFeet, forKey: .realClimbableHeightFeet)
        try container.encode(totalSteps, forKey: .totalSteps)
        try container.encodeIfPresent(realStairCount, forKey: .realStairCount)
        try container.encode(calculatedFloors, forKey: .calculatedFloors)
        try container.encode(category, forKey: .category)
        try container.encode(tier, forKey: .tier)
        try container.encode(tags, forKey: .tags)
        try container.encode(funFact, forKey: .funFact)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(imageSetVersion, forKey: .imageSetVersion)
        try container.encode(releaseState, forKey: .releaseState)
    }

    private func clampedCameraDistance(
        _ proposedDistance: Double,
        min minimumDistance: CLLocationDistance,
        max maximumDistance: CLLocationDistance
    ) -> CLLocationDistance {
        min(max(proposedDistance, minimumDistance), maximumDistance)
    }
}
