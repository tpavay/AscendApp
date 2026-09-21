import CoreGraphics
import MapKit
import CoreLocation
import Foundation

/// Groups landmarks whose markers would overlap on screen into one cluster.
///
/// Overlap-driven, not altitude-driven, by the captain's rule: a group collapses
/// into one "N climbs" pill only while its dots would sit on top of each other at
/// the current camera, and dissolves into the individual markers the moment they
/// separate. A lone landmark is its own dot at every zoom. Pure over screen points,
/// so the renderer supplies the projection and this stays testable.
enum ClimbMapClustering {
    /// How close two marker centres may be, in points, before they read as one.
    /// A marker is `ClimbMarkerView.size` wide, so this is "touching or closer".
    static let overlapDistance: CGFloat = 26

    struct Layer: Equatable {
        /// Landmarks drawn as their own marker.
        let pins: [AscendMapLandmark]
        /// Landmarks folded into "N climbs" pills.
        let clusters: [AscendMapCluster]

        static let empty = Layer(pins: [], clusters: [])

        static func == (lhs: Layer, rhs: Layer) -> Bool {
            lhs.pins.map(\.id) == rhs.pins.map(\.id) &&
                lhs.pins.map(\.state) == rhs.pins.map(\.state) &&
                lhs.pins.map(\.isHighlighted) == rhs.pins.map(\.isHighlighted) &&
                lhs.pins.map(\.completedClimberCount) == rhs.pins.map(\.completedClimberCount) &&
                lhs.clusters.map(\.id) == rhs.clusters.map(\.id) &&
                lhs.clusters.map { $0.landmarks.map(\.id) } == rhs.clusters.map { $0.landmarks.map(\.id) }
        }
    }

    /// Groups `landmarks` by their projected `points`. A landmark with no point (off
    /// the visible hemisphere, or not yet projected) is drawn as a marker on its own.
    /// The highlighted landmark never joins a cluster, so the climb a card is open
    /// for cannot hide inside a count.
    static func layer(
        for landmarks: [AscendMapLandmark],
        points: [String: CGPoint],
        overlapDistance: CGFloat = overlapDistance
    ) -> Layer {
        let projected = landmarks.filter { points[$0.id] != nil && !$0.isHighlighted }
        let unprojected = landmarks.filter { points[$0.id] == nil || $0.isHighlighted }

        // Union-find over every pair closer than the overlap distance.
        var parent = Array(0..<projected.count)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var walker = index
            while parent[walker] != root {
                let next = parent[walker]
                parent[walker] = root
                walker = next
            }
            return root
        }
        let threshold = overlapDistance * overlapDistance
        for lhs in projected.indices {
            guard let lhsPoint = points[projected[lhs].id] else { continue }
            for rhs in (lhs + 1)..<projected.count {
                guard let rhsPoint = points[projected[rhs].id] else { continue }
                let dx = lhsPoint.x - rhsPoint.x
                let dy = lhsPoint.y - rhsPoint.y
                if dx * dx + dy * dy <= threshold {
                    let lhsRoot = find(lhs)
                    let rhsRoot = find(rhs)
                    if lhsRoot != rhsRoot { parent[rhsRoot] = lhsRoot }
                }
            }
        }

        var groups: [Int: [AscendMapLandmark]] = [:]
        var order: [Int] = []
        for index in projected.indices {
            let root = find(index)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(projected[index])
        }

        var pins = unprojected
        var clusters: [AscendMapCluster] = []
        for root in order {
            let members = groups[root] ?? []
            if members.count == 1, let only = members.first {
                pins.append(only)
            } else {
                clusters.append(AscendMapCluster(
                    id: members.map(\.id).sorted().joined(separator: "+"),
                    coordinate: centroid(of: members),
                    landmarks: members
                ))
            }
        }
        return Layer(pins: pins, clusters: clusters)
    }

    /// The region that shows every member of a cluster with room to separate: the
    /// members' bounds padded to half again, never tighter than a city block so two
    /// towers on one street still get a frame rather than a point.
    static func region(showing cluster: AscendMapCluster) -> MKCoordinateRegion {
        let latitudes = cluster.landmarks.map(\.climb.latitude)
        let longitudes = cluster.landmarks.map(\.climb.longitude)
        let minLatitude = latitudes.min() ?? cluster.coordinate.latitude
        let maxLatitude = latitudes.max() ?? cluster.coordinate.latitude
        let minLongitude = longitudes.min() ?? cluster.coordinate.longitude
        let maxLongitude = longitudes.max() ?? cluster.coordinate.longitude
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.6, 0.02)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.6, 0.02)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private static func centroid(of landmarks: [AscendMapLandmark]) -> CLLocationCoordinate2D {
        let count = Double(max(landmarks.count, 1))
        let latitude = landmarks.reduce(0.0) { $0 + $1.climb.latitude } / count
        let longitude = landmarks.reduce(0.0) { $0 + $1.climb.longitude } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
