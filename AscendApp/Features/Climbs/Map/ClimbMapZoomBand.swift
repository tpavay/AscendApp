import CoreLocation
import Foundation

/// How far the camera is from the globe, in the four bands the map reads differently.
///
/// The pin layer changes with the band and with nothing finer: pins gather into counts
/// at world zoom and split on the way in, names appear below country zoom, and the
/// map trades imagery for street detail at city zoom. Deriving from a band rather
/// than the raw distance keeps the annotation set stable through a pinch - it changes
/// once per crossing, not once per frame.
///
/// The thresholds started from the design prototype's altitudes (1.4, 0.62 and 0.24
/// globe radii, roughly 8,900, 3,950 and 1,530 km) and were rounded to where MapKit's
/// own imagery reads as world, continent, country and city.
enum ClimbMapZoomBand: Int, CaseIterable, Comparable, Sendable {
    case world
    case continent
    case country
    case city

    /// The camera distance, in metres, above which the band begins.
    static let continentCeiling: CLLocationDistance = 9_000_000
    static let countryCeiling: CLLocationDistance = 3_500_000
    static let cityCeiling: CLLocationDistance = 1_200_000

    /// Where Home opens: inside the continent band, centred on Today's Climb.
    static let homeEntryCameraDistance: CLLocationDistance = 5_500_000

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

    /// Pins gather into counted clusters only at world zoom.
    var clustersPins: Bool {
        self == .world
    }

    /// Climb names sit beside their pins from country zoom in.
    var showsNames: Bool {
        self >= .country
    }

    /// Streets and place labels join the imagery at city zoom.
    var showsStreets: Bool {
        self == .city
    }

    /// The distance a tap on a cluster flies the camera to: the next band in, at a
    /// height where its members have room to split apart.
    var clusterFocusDistance: CLLocationDistance {
        switch self {
        case .world:
            return Self.homeEntryCameraDistance
        case .continent:
            return 2_500_000
        case .country, .city:
            return 800_000
        }
    }

    /// The width of one clustering cell in degrees of latitude and longitude. Fixed per
    /// band so panning never regroups pins; only crossing a band does.
    var clusterCellDegrees: Double {
        switch self {
        case .world:
            return 30
        case .continent, .country, .city:
            return 0
        }
    }

    static func < (lhs: ClimbMapZoomBand, rhs: ClimbMapZoomBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
