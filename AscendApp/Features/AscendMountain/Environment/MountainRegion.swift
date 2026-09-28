import Foundation

/// A portion of Ascend Mountain, selected by step count.
///
/// Regions are data, not code (captain, 2026-09-28): how many there are, where each starts, what
/// they are called and how they look are all undecided, so nothing here names or themes one.
/// Ids are placeholders (`region_01`, ...) until those product decisions land, and the bundled
/// `ascend-mountain-world.json` holds provisional values only. The climb itself never ends:
/// the last region has no `endStep`.
struct MountainRegion: Decodable, Equatable, Sendable {
    let id: String
    let startStep: Int
    /// Where the next region begins; `nil` for the open-ended last one.
    let endStep: Int?
    let environment: MountainEnvironmentProfile
}

/// How a region looks. Only visual configuration lives here - the staircase, the step model and
/// the course are identical in every region.
struct MountainEnvironmentProfile: Decodable, Equatable, Sendable {
    struct Terrain: Decodable, Equatable, Sendable {
        /// How steeply the mountainside falls away from the stairs.
        let steepness: Double
        /// Chance that a mountainside cell beside the stairs grows a tree.
        let treeDensity: Double
        let rockDensity: Double
        /// Share of open ground covered in snow rather than grass, 0 to 1.
        let snowCover: Double
    }

    struct Palette: Decodable, Equatable, Sendable {
        let grass: MountainColor
        let rock: MountainColor
        let snow: MountainColor
        /// What distance and depth fade toward.
        let haze: MountainColor
        let foliage: MountainColor
    }

    struct Sky: Decodable, Equatable, Sendable {
        let zenith: MountainColor
        let horizon: MountainColor
        let sun: MountainColor
        let sunIntensity: Double
    }

    enum Clouds: String, Decodable, Sendable {
        case none
        /// Cloud banks drifting at the climber's height.
        case around
        /// A sea of cloud below the climber.
        case below
        /// Inside the cloud layer: the sea of cloud lies level with the climber and mist drifts
        /// across the stairs.
        case through
    }

    let terrain: Terrain
    let palette: Palette
    let sky: Sky
    let clouds: Clouds
}

/// An sRGB colour stored as `#RRGGBB` in region data, kept free of UIKit so region logic stays
/// testable.
struct MountainColor: Decodable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let color = MountainColor(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a #RRGGBB colour: \(hex)"))
        }
        self = color
    }

    func mixed(with other: MountainColor, amount: Double) -> MountainColor {
        let t = min(max(amount, 0), 1)
        return MountainColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

/// The ordered regions of one mountain, and the only place a step count is turned into one.
struct MountainRegionMap: Sendable {
    enum LoadError: Error, Equatable {
        case empty
        case firstRegionDoesNotStartAtZero
        case notContiguous(String)
    }

    /// Steps over which a region's numbers and colours ease into the next region's, so neither the
    /// mountainside's shape nor its colour steps at a boundary.
    static let transitionSteps = 250.0

    let regions: [MountainRegion]

    init(regions: [MountainRegion]) throws {
        guard let first = regions.first else { throw LoadError.empty }
        guard first.startStep == 0 else { throw LoadError.firstRegionDoesNotStartAtZero }
        for (region, next) in zip(regions, regions.dropFirst()) where region.endStep != next.startStep || next.startStep <= region.startStep {
            throw LoadError.notContiguous(region.id)
        }
        guard regions.last?.endStep == nil else { throw LoadError.notContiguous(regions[regions.count - 1].id) }
        self.regions = regions
    }


    func index(atSteps steps: Double) -> Int {
        let clamped = steps.isFinite ? max(steps, 0) : 0
        return regions.lastIndex { Double($0.startStep) <= clamped } ?? 0
    }

    func region(atSteps steps: Double) -> MountainRegion {
        regions[index(atSteps: steps)]
    }

    /// A numeric environment value at `steps`, eased into the next region over the
    /// `transitionSteps` before it begins.
    func blended(_ value: (MountainEnvironmentProfile) -> Double, atSteps steps: Double) -> Double {
        let (current, next, t) = transition(atSteps: steps)
        return value(current.environment) + (value(next.environment) - value(current.environment)) * t
    }

    func blendedColor(_ value: (MountainEnvironmentProfile) -> MountainColor, atSteps steps: Double) -> MountainColor {
        let (current, next, t) = transition(atSteps: steps)
        return value(current.environment).mixed(with: value(next.environment), amount: t)
    }

    private func transition(atSteps steps: Double) -> (MountainRegion, MountainRegion, Double) {
        let index = index(atSteps: steps)
        let current = regions[index]
        guard index + 1 < regions.count else { return (current, current, 0) }
        let next = regions[index + 1]
        let intoTransition = steps - (Double(next.startStep) - Self.transitionSteps)
        guard intoTransition > 0 else { return (current, next, 0) }
        let t = min(intoTransition / Self.transitionSteps, 1)
        return (current, next, t * t * (3 - 2 * t))
    }
}
