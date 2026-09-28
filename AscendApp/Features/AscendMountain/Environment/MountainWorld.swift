import Foundation

/// A physical marker standing on the staircase at a step count - a stone gate the climber walks
/// through - so progress is read off the mountain rather than a card over it.
struct MountainMarker: Decodable, Equatable, Sendable {
    let id: String
    /// The stair the climber stands on when their count reaches this number.
    let step: Int
    let title: String
    let subtitle: String?
}

/// Everything about Ascend Mountain that is content rather than code: its regions and markers,
/// loaded from the bundled `ascend-mountain-world.json`, so changing either never needs a build
/// that re-derives the staircase.
struct MountainWorld: Sendable {
    enum LoadError: Error, Equatable {
        case missingResource
    }

    static let resourceName = "ascend-mountain-world"

    let regions: MountainRegionMap
    /// Ordered by step.
    let markers: [MountainMarker]

    init(regions: MountainRegionMap, markers: [MountainMarker]) {
        self.regions = regions
        self.markers = markers.sorted { $0.step < $1.step }
    }

    init(data: Data) throws {
        struct File: Decodable {
            let regions: [MountainRegion]
            let markers: [MountainMarker]?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(regions: try MountainRegionMap(regions: file.regions), markers: file.markers ?? [])
    }

    static func bundled(in bundle: Bundle = .main) throws -> MountainWorld {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try MountainWorld(data: Data(contentsOf: url))
    }

    /// Markers close enough to the climber to stand in the world now: a little way behind, so a
    /// gate just walked through does not vanish from under the camera, and far enough ahead to be
    /// seen coming.
    func markers(near steps: Double, behind: Double = 12, ahead: Double = 160) -> [MountainMarker] {
        markers.filter { Double($0.step) >= steps - behind && Double($0.step) <= steps + ahead }
    }
}
