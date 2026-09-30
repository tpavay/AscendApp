import Foundation
import simd

/// Flat-shaded, textured stone for one course piece's stairs, in the piece's own frame (entry at
/// the origin, facing -Z).
///
/// Every piece of one kind shares a single mesh built from this once per scene, so a chunk slot
/// changes what it shows by swapping a mesh reference, never by building geometry mid-climb.
/// The walking surface is exactly the step path - each tread top sits at its stair's height - so
/// the athlete's feet land where the course says they do.
struct MountainChunkGeometry: Equatable, Sendable {
    enum Surface: UInt32, CaseIterable, Sendable {
        /// Treads, risers and platforms.
        case stone = 0
        /// The kerb stones along the sides.
        case kerb = 1
    }

    /// How far a stair block reaches below its tread, into the mountainside.
    static let blockDepth = 0.75
    static let chamfer = 0.022
    static let kerbWidth = MountainTerrainPatch.kerbWidth
    static let kerbHeight = 0.16
    /// Texture repeats per metre.
    static let textureScale = 0.55

    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []
    /// One surface per triangle.
    private(set) var triangleSurfaces: [UInt32] = []
    /// Stair blocks, platforms and kerb stones laid.
    private(set) var pieceCount = 0

    init(kind: MountainChunkKind) {
        let rise = MountainStairGeometry.rise
        let run = MountainStairGeometry.run
        let width = MountainStairGeometry.width

        switch kind {
        case .shortFlight, .mediumFlight, .longFlight:
            for stair in 1...kind.stepCount {
                let top = Double(stair) * rise
                let front = -Double(stair) * run + run / 2
                addStairBlock(front: front, back: front - run, top: top, seed: stair)
                for side in [-1.0, 1.0] {
                    let lift = Self.kerbHeight + (Self.jitter(stair, side, 1) - 0.5) * 0.05
                    let out = (Self.jitter(stair, side, 2) - 0.5) * 0.03
                    addBox(
                        minX: side < 0 ? -width / 2 - Self.kerbWidth - out : width / 2,
                        maxX: side < 0 ? -width / 2 : width / 2 + Self.kerbWidth + out,
                        minY: top - rise - Self.blockDepth,
                        maxY: top + lift,
                        minZ: front - run,
                        maxZ: front,
                        surface: .kerb,
                        seed: stair * 7 + (side < 0 ? 1 : 2)
                    )
                }
            }

        case .landing:
            let length = Double(kind.stepCount) * MountainStairGeometry.flatStride
            addBox(minX: -width / 2, maxX: width / 2, minY: -Self.blockDepth, maxY: 0, minZ: -run / 2 - length, maxZ: -run / 2, surface: .stone, seed: 3)
            for side in [-1.0, 1.0] {
                addKerbRun(alongX: side * (width / 2 + Self.kerbWidth / 2), fromZ: -run / 2, toZ: -run / 2 - length, seed: side < 0 ? 11 : 12)
            }

        case .leftTurn, .rightTurn:
            let farZ = -run / 2 - width
            addBox(minX: -width / 2, maxX: width / 2, minY: -Self.blockDepth, maxY: 0, minZ: farZ, maxZ: -run / 2, surface: .stone, seed: 5)
            // Kerbs on the outside of the corner; the open side leads on.
            let outside = kind == .leftTurn ? 1.0 : -1.0
            addKerbRun(alongX: outside * (width / 2 + Self.kerbWidth / 2), fromZ: -run / 2, toZ: farZ - Self.kerbWidth, seed: 21)
            addKerbRow(alongZ: farZ - Self.kerbWidth / 2, fromX: -width / 2, toX: width / 2, seed: 22)
        }
    }

    // MARK: - Pieces

    /// A stair block with a chamfered front edge, extruded across the staircase.
    private mutating func addStairBlock(front: Double, back: Double, top: Double, seed: Int) {
        let width = MountainStairGeometry.width
        let bottom = top - MountainStairGeometry.rise - Self.blockDepth
        let c = Self.chamfer
        // Cross-section in (z, y), counter-clockwise seen from +X.
        let profile: [SIMD2<Double>] = [
            SIMD2(front, bottom),
            SIMD2(front, top - c),
            SIMD2(front - c, top),
            SIMD2(back, top),
            SIMD2(back, bottom)
        ]
        let offset = Self.uvOffset(seed)

        // Faces along the profile, extruded from -X to +X.
        for index in 0..<profile.count {
            let a = profile[index], b = profile[(index + 1) % profile.count]
            let edge = b - a
            let normal = simd_normalize(SIMD3(0, -edge.x, edge.y))
            let p0 = SIMD3(-width / 2, a.y, a.x), p1 = SIMD3(width / 2, a.y, a.x)
            let p2 = SIMD3(width / 2, b.y, b.x), p3 = SIMD3(-width / 2, b.y, b.x)
            // Treads map by (x, z), risers by (x, y), so the stone never smears along a face.
            let alongV: (SIMD3<Double>) -> Double = abs(normal.y) > 0.7 ? { $0.z } : { $0.y }
            addQuad(p0, p1, p2, p3, normal: SIMD3<Float>(normal), surface: .stone) { point in
                SIMD2(point.x, alongV(point)) * Self.textureScale + offset
            }
        }

        // End caps, fanned from the profile's first corner (the profile is convex).
        for side in [-1.0, 1.0] {
            let x = side * width / 2
            let normal = SIMD3<Float>(Float(side), 0, 0)
            for index in 1..<(profile.count - 1) {
                let corners = [profile[0], profile[index], profile[index + 1]].map { SIMD3(x, $0.y, $0.x) }
                addTriangle(corners[0], corners[1], corners[2], normal: normal, surface: .stone) { point in
                    SIMD2(point.z, point.y) * Self.textureScale + offset
                }
            }
        }
        pieceCount += 1
    }

    /// Kerb stones of uneven length laid along a side of a platform.
    private mutating func addKerbRun(alongX x: Double, fromZ: Double, toZ: Double, seed: Int) {
        var z = fromZ
        var stone = 0
        while z > toZ + 0.01 {
            let length = min(0.45 + Self.jitter(seed, Double(stone), 3) * 0.35, z - toZ)
            let lift = Self.kerbHeight + (Self.jitter(seed, Double(stone), 4) - 0.5) * 0.05
            addBox(
                minX: x - Self.kerbWidth / 2, maxX: x + Self.kerbWidth / 2,
                minY: -Self.blockDepth, maxY: lift,
                minZ: z - length, maxZ: z,
                surface: .kerb, seed: seed * 31 + stone
            )
            z -= length
            stone += 1
        }
    }

    private mutating func addKerbRow(alongZ z: Double, fromX: Double, toX: Double, seed: Int) {
        var x = fromX
        var stone = 0
        while x < toX - 0.01 {
            let length = min(0.45 + Self.jitter(seed, Double(stone), 3) * 0.35, toX - x)
            let lift = Self.kerbHeight + (Self.jitter(seed, Double(stone), 4) - 0.5) * 0.05
            addBox(
                minX: x, maxX: x + length,
                minY: -Self.blockDepth, maxY: lift,
                minZ: z - Self.kerbWidth / 2, maxZ: z + Self.kerbWidth / 2,
                surface: .kerb, seed: seed * 31 + stone
            )
            x += length
            stone += 1
        }
    }

    private mutating func addBox(
        minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double,
        surface: Surface, seed: Int
    ) {
        let offset = Self.uvOffset(seed)
        let s = Self.textureScale
        let faces: [(SIMD3<Double>, [SIMD3<Double>], (SIMD3<Double>) -> SIMD2<Double>)] = [
            (SIMD3(0, 1, 0), [SIMD3(minX, maxY, maxZ), SIMD3(maxX, maxY, maxZ), SIMD3(maxX, maxY, minZ), SIMD3(minX, maxY, minZ)], { SIMD2($0.x, $0.z) }),
            (SIMD3(0, 0, 1), [SIMD3(minX, minY, maxZ), SIMD3(maxX, minY, maxZ), SIMD3(maxX, maxY, maxZ), SIMD3(minX, maxY, maxZ)], { SIMD2($0.x, $0.y) }),
            (SIMD3(0, 0, -1), [SIMD3(maxX, minY, minZ), SIMD3(minX, minY, minZ), SIMD3(minX, maxY, minZ), SIMD3(maxX, maxY, minZ)], { SIMD2($0.x, $0.y) }),
            (SIMD3(1, 0, 0), [SIMD3(maxX, minY, maxZ), SIMD3(maxX, minY, minZ), SIMD3(maxX, maxY, minZ), SIMD3(maxX, maxY, maxZ)], { SIMD2($0.z, $0.y) }),
            (SIMD3(-1, 0, 0), [SIMD3(minX, minY, minZ), SIMD3(minX, minY, maxZ), SIMD3(minX, maxY, maxZ), SIMD3(minX, maxY, minZ)], { SIMD2($0.z, $0.y) })
        ]
        for (normal, corners, mapping) in faces {
            addQuad(corners[0], corners[1], corners[2], corners[3], normal: SIMD3<Float>(normal), surface: surface) { point in
                mapping(point) * s + offset
            }
        }
        pieceCount += 1
    }

    // MARK: - Primitives

    /// Adds a quad wound counter-clockwise as given, seen from the side `normal` points to.
    private mutating func addQuad(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ d: SIMD3<Double>,
        normal: SIMD3<Float>, surface: Surface, uv: (SIMD3<Double>) -> SIMD2<Double>
    ) {
        addTriangle(a, b, c, normal: normal, surface: surface, uv: uv)
        addTriangle(a, c, d, normal: normal, surface: surface, uv: uv)
    }

    private mutating func addTriangle(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>,
        normal: SIMD3<Float>, surface: Surface, uv: (SIMD3<Double>) -> SIMD2<Double>
    ) {
        // Keep every face's winding consistent with its normal, whatever order it was given in.
        let wound = SIMD3<Float>(simd_cross(b - a, c - a))
        let corners = simd_dot(wound, normal) >= 0 ? [a, b, c] : [a, c, b]
        let base = UInt32(positions.count)
        for corner in corners {
            positions.append(SIMD3<Float>(corner))
            normals.append(normal)
            uvs.append(SIMD2<Float>(uv(corner)))
        }
        indices.append(contentsOf: [base, base + 1, base + 2])
        triangleSurfaces.append(surface.rawValue)
    }

    private static func jitter(_ a: Int, _ b: Double, _ salt: Int) -> Double {
        MountainNoise.hash(a &* 131 &+ salt, Int(b * 7) &+ salt &* 17, seed: 41)
    }

    /// A different patch of the stone texture for every block, so neighbouring stairs never
    /// share a grain.
    private static func uvOffset(_ seed: Int) -> SIMD2<Double> {
        SIMD2(MountainNoise.hash(seed, 1, seed: 43), MountainNoise.hash(seed, 2, seed: 43)) * 8
    }
}
