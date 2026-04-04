import CoreLocation
import Foundation

struct Climb: Codable, Identifiable, Hashable {
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
    let multiSession: Bool
    let funFact: String
    let sourceURL: String
    let imageSetVersion: Int
    let isPublished: Bool

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

    var isSingleSession: Bool {
        !multiSession
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
        multiSession: false,
        funFact: "The Empire State Building opened in 1931 and held the tallest-building title for nearly 40 years.",
        sourceURL: "https://en.wikipedia.org/wiki/Empire_State_Building",
        imageSetVersion: 1,
        isPublished: true
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
        case multiSession
        case funFact
        case sourceURL
        case imageSetVersion
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
        multiSession: Bool,
        funFact: String,
        sourceURL: String,
        imageSetVersion: Int = 1,
        isPublished: Bool = true
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
        self.multiSession = multiSession
        self.funFact = funFact
        self.sourceURL = sourceURL
        self.imageSetVersion = imageSetVersion
        self.isPublished = isPublished
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
        multiSession = try container.decode(Bool.self, forKey: .multiSession)
        funFact = try container.decode(String.self, forKey: .funFact)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        imageSetVersion = try container.decodeIfPresent(Int.self, forKey: .imageSetVersion) ?? 1
        isPublished = try container.decodeIfPresent(Bool.self, forKey: .isPublished) ?? true
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
        try container.encode(multiSession, forKey: .multiSession)
        try container.encode(funFact, forKey: .funFact)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(imageSetVersion, forKey: .imageSetVersion)
        try container.encode(isPublished, forKey: .isPublished)
    }
}
