import Foundation
import simd

/// Which material a terrain triangle takes: its region's palette, its ground cover, and how
/// far it has faded into the haze below the stairs.
struct MountainTerrainBucket: Hashable, Sendable {
    enum Surface: Int, CaseIterable, Sendable {
        case grass
        case rock
        case snow
    }

    static let hazeLevels = 4

    let regionIndex: Int
    let surface: Surface
    /// 0 beside the stairs up to `hazeLevels - 1` far down the mountainside.
    let haze: Int
}

/// A tree or boulder placed on a course piece's mountainside, in that piece's own frame.
struct MountainDecorInstance: Equatable, Sendable {
    let position: SIMD3<Float>
    let yaw: Float
    let scale: Float
    let regionIndex: Int
}

/// The mountainside around one course piece: the ground falling away from both sides of the
/// stairs, and what grows on it, in the piece's own frame (entry at the origin, facing -Z).
///
/// Built per placed piece rather than per piece kind, from noise over course space, so two
/// pieces that meet share their edge exactly and no stretch of mountain repeats another.
struct MountainTerrainPatch: Sendable {
    /// Lateral distances from the stairs' side stones at which the ground is sampled; spacing
    /// widens with distance because detail far down the slope is never seen up close.
    static let lateralSamples: [Double] = [0, 0.35, 0.9, 1.6, 2.6, 4, 6, 8.5, 12, 16.5, 22, 29, 38]
    /// Width of the stone kerb the ground meets at the side of the stairs.
    static let kerbWidth = 0.22
    static let rowSpacing = 0.6
    /// Depths below the stairs at which the ground steps to its next haze level.
    static let hazeDepths: [Double] = [6, 16, 32]

    /// Metres of ground one repeat of a detail texture covers.
    static let detailTileMetres = 3.2

    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    /// Texture coordinates from course space, so a detail texture runs unbroken across pieces.
    private(set) var uvs: [SIMD2<Float>] = []
    /// Triangle vertex indices per material bucket; every triangle owns its three vertices,
    /// so the ground is flat-shaded.
    private(set) var triangles: [MountainTerrainBucket: [UInt32]] = [:]
    private(set) var trees: [MountainDecorInstance] = []
    private(set) var rocks: [MountainDecorInstance] = []

    var triangleCount: Int { triangles.values.reduce(0) { $0 + $1.count } / 3 }

    /// Ground height beside the stairs at lateral distance `distance` from the kerb, relative to
    /// the stair treads, for a mountainside of the given steepness.
    static func profile(distance: Double, steepness: Double) -> Double {
        let d = max(distance, 0)
        if d <= 1 { return -0.28 - 0.3 * d }
        return -0.58 - steepness * 1.05 * pow(d - 1, 1.12)
    }

    init(placement: MountainChunkPlacement, regions: MountainRegionMap) {
        let context = Context(placement: placement, regions: regions)
        for strip in Self.strips(for: placement.kind, firstStep: placement.firstStep) {
            addStrip(strip, context: context)
        }
        if let corner = Self.corner(for: placement.kind, firstStep: placement.firstStep) {
            addFan(corner, context: context)
        }
    }

    // MARK: - Layout of a piece's mountainside

    /// One side of a piece: a straight kerb line with the ground falling away from it.
    struct Strip {
        let start: SIMD2<Double>
        let end: SIMD2<Double>
        /// Unit direction away from the stairs, on the ground plane.
        let outward: SIMD2<Double>
        let startHeight: Double
        let endHeight: Double
        let startSteps: Double
        let endSteps: Double
    }

    /// The outside corner of a turn platform, where two strips meet and the ground wraps round.
    struct Corner {
        let centre: SIMD2<Double>
        let fromOutward: SIMD2<Double>
        let toOutward: SIMD2<Double>
        let steps: Double
    }

    static func strips(for kind: MountainChunkKind, firstStep: Int) -> [Strip] {
        let run = MountainStairGeometry.run
        let width = MountainStairGeometry.width
        let edge = width / 2 + kerbWidth
        let first = Double(firstStep)
        let steps = Double(kind.stepCount)

        switch kind {
        case .shortFlight, .mediumFlight, .longFlight, .landing:
            let length = kind.isFlight ? steps * run : steps * MountainStairGeometry.flatStride
            let top = kind.isFlight ? steps * MountainStairGeometry.rise : 0
            return [-1.0, 1.0].map { side in
                Strip(
                    start: SIMD2(side * edge, -run / 2),
                    end: SIMD2(side * edge, -run / 2 - length),
                    outward: SIMD2(side, 0),
                    startHeight: 0,
                    endHeight: top,
                    startSteps: first,
                    endSteps: first + steps
                )
            }

        case .leftTurn, .rightTurn:
            // The outside of the turn: the wall continuing the entry flight, then the far wall
            // continuing into the exit flight. The inside corner belongs to the two flights.
            let side: Double = kind == .leftTurn ? 1 : -1
            let nearZ = -run / 2
            let farZ = -run / 2 - width
            let middle = first + steps / 2
            return [
                Strip(
                    start: SIMD2(side * edge, nearZ),
                    end: SIMD2(side * edge, farZ),
                    outward: SIMD2(side, 0),
                    startHeight: 0,
                    endHeight: 0,
                    startSteps: first,
                    endSteps: middle
                ),
                Strip(
                    start: SIMD2(side * width / 2, farZ - kerbWidth),
                    end: SIMD2(-side * width / 2, farZ - kerbWidth),
                    outward: SIMD2(0, -1),
                    startHeight: 0,
                    endHeight: 0,
                    startSteps: middle,
                    endSteps: first + steps
                )
            ]
        }
    }

    static func corner(for kind: MountainChunkKind, firstStep: Int) -> Corner? {
        guard kind.isTurn else { return nil }
        let side: Double = kind == .leftTurn ? 1 : -1
        let farZ = -MountainStairGeometry.run / 2 - MountainStairGeometry.width
        return Corner(
            centre: SIMD2(side * MountainStairGeometry.width / 2, farZ),
            fromOutward: SIMD2(side, 0),
            toOutward: SIMD2(0, -1),
            steps: Double(firstStep) + Double(kind.stepCount) / 2
        )
    }

    // MARK: - Heights

    private struct Context {
        let placement: MountainChunkPlacement
        let regions: MountainRegionMap

        func world(_ local: SIMD2<Double>) -> SIMD2<Double> {
            let rotated = placement.entry.rotate(SIMD3(local.x, 0, local.y))
            return SIMD2(placement.entry.position.x + rotated.x, placement.entry.position.z + rotated.z)
        }

        func steepness(atSteps steps: Double) -> Double {
            regions.blended({ $0.terrain.steepness }, atSteps: steps)
        }

        /// Ground height in the piece's frame at a point `distance` metres from the kerb.
        func height(local: SIMD2<Double>, baseHeight: Double, distance: Double, steps: Double) -> Double {
            let world = world(local)
            let broad = MountainNoise.fbm(world.x * 0.045, world.y * 0.045, octaves: 4, seed: 11)
            let fine = MountainNoise.fbm(world.x * 0.32, world.y * 0.32, octaves: 2, seed: 29)
            let broadAmount = smoothstep(1.2, 7, distance) * 5.5
            let fineAmount = smoothstep(0.2, 1.4, distance) * 0.35
            return baseHeight + MountainTerrainPatch.profile(distance: distance, steepness: steepness(atSteps: steps))
                + broad * broadAmount + fine * fineAmount
        }
    }

    // MARK: - Building

    private mutating func addStrip(_ strip: Strip, context: Context) {
        let length = simd_distance(strip.start, strip.end)
        let rows = max(Int((length / Self.rowSpacing).rounded(.up)), 1)
        var grid: [[SIMD3<Double>]] = []
        var gridSteps: [Double] = []
        var gridBase: [Double] = []

        for row in 0...rows {
            let t = Double(row) / Double(rows)
            let edge = strip.start + (strip.end - strip.start) * t
            let base = strip.startHeight + (strip.endHeight - strip.startHeight) * t
            let steps = strip.startSteps + (strip.endSteps - strip.startSteps) * t
            gridSteps.append(steps)
            gridBase.append(base)
            grid.append(Self.lateralSamples.map { distance in
                let local = edge + strip.outward * distance
                let y = context.height(local: local, baseHeight: base, distance: distance, steps: steps)
                return SIMD3(local.x, y, local.y)
            })
        }

        // A strip whose outward direction is to the left of its run needs its quads wound the
        // other way round to face up.
        let along = strip.end - strip.start
        let flips = along.x * strip.outward.y - along.y * strip.outward.x > 0

        for row in 0..<rows {
            for column in 0..<(Self.lateralSamples.count - 1) {
                let a = grid[row][column], b = grid[row + 1][column]
                let c = grid[row + 1][column + 1], d = grid[row][column + 1]
                let steps = (gridSteps[row] + gridSteps[row + 1]) / 2
                let base = (gridBase[row] + gridBase[row + 1]) / 2
                addQuad(a, b, c, d, flipped: flips, steps: steps, baseHeight: base, context: context)
            }
        }

        scatter(along: grid, steps: gridSteps, context: context)
    }

    private mutating func addFan(_ corner: Corner, context: Context) {
        let segments = 5
        let start = atan2(corner.fromOutward.y, corner.fromOutward.x)
        var end = atan2(corner.toOutward.y, corner.toOutward.x)
        if abs(end - start) > .pi { end += end < start ? 2 * .pi : -2 * .pi }

        var grid: [[SIMD3<Double>]] = []
        for segment in 0...segments {
            let angle = start + (end - start) * Double(segment) / Double(segments)
            let direction = SIMD2(cos(angle), sin(angle))
            grid.append(Self.lateralSamples.map { distance in
                let local = corner.centre + direction * (Self.kerbWidth + distance)
                let y = context.height(local: local, baseHeight: 0, distance: distance, steps: corner.steps)
                return SIMD3(local.x, y, local.y)
            })
        }

        let flips = (end - start) > 0
        for segment in 0..<segments {
            for column in 0..<(Self.lateralSamples.count - 1) {
                addQuad(
                    grid[segment][column], grid[segment + 1][column],
                    grid[segment + 1][column + 1], grid[segment][column + 1],
                    flipped: flips, steps: corner.steps, baseHeight: 0, context: context
                )
            }
        }
    }

    /// A cell of ground takes one look for both of its triangles. The cells far down the slope
    /// are long slivers, and judged triangle by triangle the two halves of one cell fell either
    /// side of the rock line, so the edge of the snow ran in long teeth - plain to see from the
    /// risen camera over a gate.
    private mutating func addQuad(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ d: SIMD3<Double>,
        flipped: Bool, steps: Double, baseHeight: Double, context: Context
    ) {
        let halves = flipped ? [(a, c, b), (a, d, c)] : [(a, b, c), (a, c, d)]
        let up = halves.reduce(SIMD3<Double>.zero) { sum, half in
            let normal = simd_cross(half.1 - half.0, half.2 - half.0)
            return sum + (normal.y < 0 ? -normal : normal)
        }
        guard simd_length(up) > 1e-9 else { return }
        let bucket = Self.bucket(centre: (a + b + c + d) / 4, normal: simd_normalize(up), steps: steps, baseHeight: baseHeight, context: context)
        for half in halves {
            addTriangle(half.0, half.1, half.2, bucket: bucket, context: context)
        }
    }

    private static func bucket(
        centre: SIMD3<Double>, normal: SIMD3<Double>, steps: Double, baseHeight: Double, context: Context
    ) -> MountainTerrainBucket {
        let depth = baseHeight - centre.y
        let haze = Self.hazeDepths.lastIndex { depth >= $0 }.map { $0 + 1 } ?? 0
        let world = context.world(SIMD2(centre.x, centre.z))
        let dither = MountainNoise.value(world.x * 0.05, world.y * 0.05, seed: 71) * 120
        let regionIndex = context.regions.index(atSteps: steps + dither)
        let region = context.regions.regions[regionIndex]
        let speckle = MountainNoise.value(world.x * 0.4, world.y * 0.4, seed: 5)

        let surface: MountainTerrainBucket.Surface
        if normal.y < 0.62 + speckle * 0.08 {
            surface = .rock
        } else if (speckle + 1) / 2 < region.environment.terrain.snowCover {
            surface = .snow
        } else {
            surface = .grass
        }
        return MountainTerrainBucket(regionIndex: regionIndex, surface: surface, haze: haze)
    }

    private mutating func addTriangle(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>,
        bucket: MountainTerrainBucket, context: Context
    ) {
        var normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 1e-9 else { return }
        normal /= length
        if normal.y < 0 {
            // Never draw a face upside down, whatever the corner geometry did.
            return addTriangle(a, c, b, bucket: bucket, context: context)
        }

        let base = UInt32(positions.count)
        let n = SIMD3<Float>(normal)
        positions.append(contentsOf: [SIMD3<Float>(a), SIMD3<Float>(b), SIMD3<Float>(c)])
        normals.append(contentsOf: [n, n, n])
        for corner in [a, b, c] {
            // Wrapped well inside Float precision however far up the mountain the piece is.
            let point = context.world(SIMD2(corner.x, corner.z)) / Self.detailTileMetres
            uvs.append(SIMD2<Float>(Float(point.x.truncatingRemainder(dividingBy: 512)), Float(point.y.truncatingRemainder(dividingBy: 512))))
        }
        triangles[bucket, default: []].append(contentsOf: [base, base + 1, base + 2])
    }

    /// Trees and boulders on the strip's cells, decided by noise over course space so the same
    /// spot always grows the same thing.
    private mutating func scatter(along grid: [[SIMD3<Double>]], steps: [Double], context: Context) {
        for row in 0..<(grid.count - 1) {
            let rowSteps = steps[row]
            let regionIndex = context.regions.index(atSteps: rowSteps)
            let treeDensity = context.regions.blended({ $0.terrain.treeDensity }, atSteps: rowSteps)
            let rockDensity = context.regions.blended({ $0.terrain.rockDensity }, atSteps: rowSteps)

            for column in 1..<(grid[row].count - 2) {
                let distance = Self.lateralSamples[column]
                let a = grid[row][column], b = grid[row + 1][column + 1]
                let world = context.world(SIMD2((a.x + b.x) / 2, (a.z + b.z) / 2))
                let cellX = Int((world.x / 1.7).rounded(.down)), cellZ = Int((world.y / 1.7).rounded(.down))
                let roll = MountainNoise.hash(cellX, cellZ, seed: 3)
                let jitter = SIMD2(MountainNoise.hash(cellX, cellZ, seed: 4), MountainNoise.hash(cellX, cellZ, seed: 6))
                let point = SIMD3(a.x + (b.x - a.x) * jitter.x, 0, a.z + (b.z - a.z) * jitter.y)
                let slope = abs(b.y - a.y) / max(simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z)), 0.01)
                let y = a.y + (b.y - a.y) * (jitter.x + jitter.y) / 2
                let yaw = Float(MountainNoise.hash(cellX, cellZ, seed: 8) * 2 * .pi)
                let size = MountainNoise.hash(cellX, cellZ, seed: 9)

                // Full-size trees keep clear of the stairs, where they would stand taller than the
                // camera and hide the climb; close in, the same pine grows as a shrub.
                let shrub = distance < 6
                if distance >= 1.6, distance <= 22, slope < 1.4, roll < treeDensity * (shrub ? 0.55 : 1) {
                    trees.append(MountainDecorInstance(
                        position: SIMD3<Float>(Float(point.x), Float(y - 0.2), Float(point.z)),
                        yaw: yaw,
                        scale: Float(shrub ? 0.28 + size * 0.22 : 0.6 + size * 0.55),
                        regionIndex: regionIndex
                    ))
                } else if roll > 1 - rockDensity {
                    let near = distance < 2
                    rocks.append(MountainDecorInstance(
                        position: SIMD3<Float>(Float(point.x), Float(y - 0.1), Float(point.z)),
                        yaw: yaw,
                        scale: Float(near ? 0.18 + size * 0.25 : 0.35 + size * 1.3),
                        regionIndex: regionIndex
                    ))
                }
            }
        }
    }
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
