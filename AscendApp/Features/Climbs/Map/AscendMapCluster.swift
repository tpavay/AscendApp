import CoreLocation
import Foundation

/// Several landmarks whose markers would overlap on screen, drawn as one "N climbs"
/// pill. Tapping it flies the camera to the region where its members separate.
struct AscendMapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let landmarks: [AscendMapLandmark]

    var count: Int {
        landmarks.count
    }

    /// The highest tier inside the cluster, which colors the bubble so a count still
    /// says what kind of climbs it hides.
    var leadingTier: ClimbTier {
        landmarks.map(\.climb.tier).max() ?? .common
    }

    /// Whether the viewer has already claimed every climb inside.
    var isFullyCompleted: Bool {
        landmarks.allSatisfy { $0.state == .completed }
    }
}
