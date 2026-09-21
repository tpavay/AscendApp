import CoreLocation
import Foundation

/// Groups landmarks into clusters on a fixed latitude and longitude grid.
///
/// Pure, so the thresholds are unit-testable: which band clusters, how large a cell
/// is, and that a cell holding one landmark stays a pin rather than a count of one.
enum ClimbMapClustering {
    struct Layer: Equatable {
        /// Landmarks drawn as their own pin.
        let pins: [AscendMapLandmark]
        /// Landmarks folded into counted bubbles.
        let clusters: [AscendMapCluster]

        static func == (lhs: Layer, rhs: Layer) -> Bool {
            lhs.pins.map(\.id) == rhs.pins.map(\.id) &&
                lhs.clusters.map(\.id) == rhs.clusters.map(\.id) &&
                lhs.clusters.map(\.count) == rhs.clusters.map(\.count)
        }
    }

    static func layer(
        for landmarks: [AscendMapLandmark],
        band: ClimbMapZoomBand
    ) -> Layer {
        guard band.clustersPins, band.clusterCellDegrees > 0 else {
            return Layer(pins: landmarks, clusters: [])
        }

        var cells: [String: [AscendMapLandmark]] = [:]
        var cellOrder: [String] = []
        for landmark in landmarks {
            let key = cellKey(for: landmark.climb.coordinate, cellDegrees: band.clusterCellDegrees)
            if cells[key] == nil {
                cellOrder.append(key)
            }
            cells[key, default: []].append(landmark)
        }

        var pins: [AscendMapLandmark] = []
        var clusters: [AscendMapCluster] = []
        for key in cellOrder {
            let members = cells[key] ?? []
            if members.count == 1, let only = members.first {
                pins.append(only)
            } else {
                clusters.append(AscendMapCluster(
                    id: key,
                    coordinate: centroid(of: members),
                    landmarks: members
                ))
            }
        }
        return Layer(pins: pins, clusters: clusters)
    }

    /// The grid cell a coordinate falls in, as a stable string key.
    static func cellKey(for coordinate: CLLocationCoordinate2D, cellDegrees: Double) -> String {
        let row = Int((coordinate.latitude + 90).rounded(.down) / cellDegrees)
        let column = Int((coordinate.longitude + 180).rounded(.down) / cellDegrees)
        return "\(row):\(column)"
    }

    private static func centroid(of landmarks: [AscendMapLandmark]) -> CLLocationCoordinate2D {
        let count = Double(max(landmarks.count, 1))
        let latitude = landmarks.reduce(0.0) { $0 + $1.climb.latitude } / count
        let longitude = landmarks.reduce(0.0) { $0 + $1.climb.longitude } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
