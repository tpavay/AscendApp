import CoreLocation
import Foundation

/// How far the camera is from the globe, in the bands the map labels differently.
///
/// Names sit beside markers from country zoom in; the imagery itself gains streets
/// and place labels as MapKit's hybrid style descends. Clustering does not read the
/// band: markers gather only where they would overlap on screen (`ClimbMapClustering`).
enum ClimbMapZoomBand: Int, CaseIterable, Comparable, Sendable {
    case world
    case continent
    case country
    case city

    /// The camera distance, in metres, above which the band begins.
    static let continentCeiling: CLLocationDistance = 9_000_000
    static let countryCeiling: CLLocationDistance = 3_500_000
    static let cityCeiling: CLLocationDistance = 1_200_000

    init(cameraDistance: CLLocationDistance) {
        if cameraDistance > Self.continentCeiling {
            self = .world
        } else if cameraDistance > Self.countryCeiling {
            self = .continent
        } else if cameraDistance > Self.cityCeiling {
            self = .country
        } else {
            self = .city
        }
    }

    /// Climb names sit beside their markers from country zoom in.
    var showsNames: Bool {
        self >= .country
    }

    static func < (lhs: ClimbMapZoomBand, rhs: ClimbMapZoomBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
