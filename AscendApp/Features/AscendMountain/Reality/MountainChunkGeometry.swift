import Foundation
import simd

/// Flat-shaded triangle data for one course piece, built from axis-aligned boxes in the
/// piece's own frame (entry at the origin, facing -Z).
///
/// Every piece of one kind shares a single mesh built from this once per scene, so a chunk slot
/// changes what it shows by swapping a mesh reference, never by building geometry mid-climb.
struct MountainChunkGeometry: Equatable, Sendable {
    enum Surface: UInt32, CaseIterable, Sendable {
        /// Treads, risers and slabs.
        case stone = 0
        /// The front edge of each tread, so every stair reads as its own step as it passes.
        case nosing = 1
        /// The low walls along the sides.
        case curb = 2
    }

    static let slabThickness = 0.28
    static let curbWidth = 0.12
    static let curbHeight = 0.22
    static let nosingDepth = 0.035

    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var indices: [UInt32] = []
    /// One surface per triangle.
    private(set) var triangleSurfaces: [UInt32] = []
    private(set) var boxCount = 0

    init(kind: MountainChunkKind) {
        let rise = MountainStairGeometry.rise
        let run = MountainStairGeometry.run
        let width = MountainStairGeometry.width
        let curbOffset = width / 2 + Self.curbWidth / 2

        switch kind {
        case .shortFlight, .mediumFlight, .longFlight:
            for stair in 1...kind.stepCount {
                let top = Double(stair) * rise
                let centreZ = -Double(stair) * run
                let blockHeight = rise + Self.slabThickness
                addBox(
                    centre: SIMD3(0, top - blockHeight / 2, centreZ),
                    size: SIMD3(width, blockHeight, run),
                    surface: .stone
                )
                addBox(
                    centre: SIMD3(0, top + 0.001 - 0.006, centreZ + run / 2 - Self.nosingDepth / 2),
                    size: SIMD3(width + 0.002, 0.012, Self.nosingDepth),
                    surface: .nosing
                )
                for side in [-1.0, 1.0] {
                    let curbHeight = blockHeight + Self.curbHeight
                    addBox(
                        centre: SIMD3(side * curbOffset, top + Self.curbHeight - curbHeight / 2, centreZ),
                        size: SIMD3(Self.curbWidth, curbHeight, run),
                        surface: .curb
                    )
                }
            }

        case .landing:
            let length = Double(kind.stepCount) * MountainStairGeometry.flatStride
            let centreZ = -run / 2 - length / 2
            addBox(
                centre: SIMD3(0, -Self.slabThickness / 2, centreZ),
                size: SIMD3(width, Self.slabThickness, length),
                surface: .stone
            )
            for side in [-1.0, 1.0] {
                addCurb(centreX: side * curbOffset, centreZ: centreZ, sizeX: Self.curbWidth, sizeZ: length)
            }

        case .leftTurn, .rightTurn:
            let centreZ = -run / 2 - width / 2
            addBox(
                centre: SIMD3(0, -Self.slabThickness / 2, centreZ),
                size: SIMD3(width, Self.slabThickness, width),
                surface: .stone
            )
            // Walls on the far edge and the outside of the corner; the open side leads on.
            let outsideX = kind == .leftTurn ? curbOffset : -curbOffset
            addCurb(centreX: outsideX, centreZ: centreZ, sizeX: Self.curbWidth, sizeZ: width + 2 * Self.curbWidth)
            addCurb(
                centreX: 0,
                centreZ: centreZ - width / 2 - Self.curbWidth / 2,
                sizeX: width,
                sizeZ: Self.curbWidth
            )
        }
    }

    private mutating func addCurb(centreX: Double, centreZ: Double, sizeX: Double, sizeZ: Double) {
        let height = Self.slabThickness + Self.curbHeight
        addBox(
            centre: SIMD3(centreX, Self.curbHeight - height / 2, centreZ),
            size: SIMD3(sizeX, height, sizeZ),
            surface: .curb
        )
    }

    /// Adds a box as six outward-facing quads, counter-clockwise seen from outside.
    private mutating func addBox(centre: SIMD3<Double>, size: SIMD3<Double>, surface: Surface) {
        let half = SIMD3<Float>(size / 2)
        let centre = SIMD3<Float>(centre)
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 0, -half.z), SIMD3(0, half.y, 0)),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, half.z), SIMD3(0, half.y, 0)),
            (SIMD3(0, 1, 0), SIMD3(half.x, 0, 0), SIMD3(0, 0, -half.z)),
            (SIMD3(0, -1, 0), SIMD3(half.x, 0, 0), SIMD3(0, 0, half.z)),
            (SIMD3(0, 0, 1), SIMD3(half.x, 0, 0), SIMD3(0, half.y, 0)),
            (SIMD3(0, 0, -1), SIMD3(-half.x, 0, 0), SIMD3(0, half.y, 0))
        ]

        for face in faces {
            let faceCentre = centre + face.normal * abs(simd_dot(face.normal, half))
            let base = UInt32(positions.count)
            positions.append(faceCentre - face.u - face.v)
            positions.append(faceCentre + face.u - face.v)
            positions.append(faceCentre + face.u + face.v)
            positions.append(faceCentre - face.u + face.v)
            normals.append(contentsOf: repeatElement(face.normal, count: 4))
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            triangleSurfaces.append(contentsOf: [surface.rawValue, surface.rawValue])
        }
        boxCount += 1
    }
}
