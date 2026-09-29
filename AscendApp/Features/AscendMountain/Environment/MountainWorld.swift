import Foundation

/// A physical marker standing at a step count, so progress is read off the mountain rather than a
/// card over it: a gate the climber walks through for a big milestone, a trail post beside the
/// stairs for a small one.
struct MountainMarker: Decodable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case gate
        case post
        /// A line painted across one stair - a mark of the climber's own, like the step count of
        /// their best, rather than a milestone of the mountain.
        case line
    }

    let id: String
    /// The stair the climber stands on when their count reaches this number.
    let step: Int
    let kind: Kind
    /// Which look this marker wears, so every milestone can have its own. A design this build does
    /// not know falls back to its kind's standard look rather than failing the world.
    let design: String?
    let title: String
    let subtitle: String?

    init(id: String, step: Int, kind: Kind = .gate, design: String? = nil, title: String, subtitle: String?) {
        self.id = id
        self.step = step
        self.kind = kind
        self.design = design
        self.title = title
        self.subtitle = subtitle
    }

    private enum CodingKeys: String, CodingKey {
        case id, step, kind, design, title, subtitle
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            step: try container.decode(Int.self, forKey: .step),
            kind: try container.decodeIfPresent(String.self, forKey: .kind).flatMap(Kind.init(rawValue:)) ?? .gate,
            design: try container.decodeIfPresent(String.self, forKey: .design),
            title: try container.decode(String.self, forKey: .title),
            subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle)
        )
    }
}

/// Markers that repeat forever - a trail post every hundred steps - described once as a rule, so an
/// endless climb needs no endless list. A step that already has its own marker keeps it.
struct MountainMarkerSeries: Decodable, Equatable, Sendable {
    let id: String
    let every: Int
    let kind: MountainMarker.Kind
    let design: String?
    let subtitle: String?

    init(id: String, every: Int, kind: MountainMarker.Kind = .post, design: String? = nil, subtitle: String?) {
        self.id = id
        self.every = every
        self.kind = kind
        self.design = design
        self.subtitle = subtitle
    }

    private enum CodingKeys: String, CodingKey {
        case id, every, kind, design, subtitle
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            every: max(1, try container.decode(Int.self, forKey: .every)),
            kind: try container.decodeIfPresent(String.self, forKey: .kind).flatMap(MountainMarker.Kind.init(rawValue:)) ?? .post,
            design: try container.decodeIfPresent(String.self, forKey: .design),
            subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle)
        )
    }

    func marker(at step: Int) -> MountainMarker {
        MountainMarker(id: "\(id)_\(step)", step: step, kind: kind, design: design, title: step.formatted(), subtitle: subtitle)
    }
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
    let markerSeries: [MountainMarkerSeries]

    init(regions: MountainRegionMap, markers: [MountainMarker], markerSeries: [MountainMarkerSeries] = []) {
        self.regions = regions
        self.markers = markers.sorted { $0.step < $1.step }
        self.markerSeries = markerSeries
    }

    init(data: Data) throws {
        struct File: Decodable {
            let regions: [MountainRegion]
            let markers: [MountainMarker]?
            let markerSeries: [MountainMarkerSeries]?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(regions: try MountainRegionMap(regions: file.regions), markers: file.markers ?? [], markerSeries: file.markerSeries ?? [])
    }

    static func bundled(in bundle: Bundle = .main) throws -> MountainWorld {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try MountainWorld(data: Data(contentsOf: url))
    }

    /// Markers close enough to the climber to stand in the world now, ordered by step: a little way
    /// behind, so a marker just passed does not vanish from under the camera, and far enough ahead
    /// to be seen coming.
    /// How far behind and ahead of the climber a marker is stood up.
    static let markersBehind = 12.0
    static let markersAhead = 160.0

    func markers(near steps: Double, behind: Double = markersBehind, ahead: Double = markersAhead) -> [MountainMarker] {
        let low = steps - behind
        let high = steps + ahead
        let own = markers.filter { Double($0.step) >= low && Double($0.step) <= high }
        var taken = Set(own.map(\.step))
        var repeated: [MountainMarker] = []
        for series in markerSeries {
            let first = max(1, Int((low / Double(series.every)).rounded(.up)))
            let last = Int((high / Double(series.every)).rounded(.down))
            guard first <= last else { continue }
            for multiple in first...last where taken.insert(multiple * series.every).inserted {
                repeated.append(series.marker(at: multiple * series.every))
            }
        }
        return (own + repeated).sorted { $0.step < $1.step }
    }
}
