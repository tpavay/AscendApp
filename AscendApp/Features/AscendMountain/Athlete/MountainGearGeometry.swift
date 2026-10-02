import Foundation
import simd

/// A seasonal item's triangles, built from a few primitive shapes in code rather than shipped as
/// a model file: a surface of revolution covers a pumpkin, a hat, a pie and a drumstick, and a
/// tube along a path covers a handle and a scarf. Smooth-shaded, in metres, ready to become one
/// mesh part per material.
struct MountainGearGeometry: Sendable {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }

    init() {}

    /// Joins another shape's triangles onto this one.
    mutating func append(_ other: MountainGearGeometry) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }

    /// Moves every vertex by a rigid transform: rotate, then translate.
    func transformed(rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), translation: SIMD3<Float> = .zero) -> MountainGearGeometry {
        var moved = self
        moved.positions = positions.map { rotation.act($0) + translation }
        moved.normals = normals.map { rotation.act($0) }
        return moved
    }

    /// Only the triangles whose texture coordinates centre inside `keep`, for a decal that
    /// covers part of a shape exactly.
    func keepingTriangles(where keep: (SIMD2<Float>) -> Bool) -> MountainGearGeometry {
        var kept = self
        kept.indices = []
        for start in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[start]), b = Int(indices[start + 1]), c = Int(indices[start + 2])
            if keep((uvs[a] + uvs[b] + uvs[c]) / 3) {
                kept.indices += [indices[start], indices[start + 1], indices[start + 2]]
            }
        }
        return kept
    }

    /// The same shape seen from both sides: a second copy facing inward, for cloth whose inside
    /// shows.
    func doubleSided() -> MountainGearGeometry {
        var inside = self
        inside.normals = normals.map { -$0 }
        var flipped: [UInt32] = []
        flipped.reserveCapacity(indices.count)
        for start in stride(from: 0, to: indices.count, by: 3) {
            flipped += [indices[start], indices[start + 2], indices[start + 1]]
        }
        inside.indices = flipped
        var both = self
        both.append(inside)
        return both
    }

    /// The same shape, larger or smaller about the origin.
    func scaled(by factor: Float) -> MountainGearGeometry {
        var scaled = self
        scaled.positions = positions.map { $0 * factor }
        return scaled
    }

    /// Bends every vertex with `deform` and recomputes the shading to match.
    func deformed(_ deform: (SIMD3<Float>) -> SIMD3<Float>) -> MountainGearGeometry {
        var bent = self
        bent.positions = positions.map(deform)
        bent.recomputeNormals()
        return bent
    }

    // MARK: - Shapes

    /// A surface of revolution about +Y. `profile` runs bottom to top as (radius, height); `ribs`
    /// scales the radius by angle, for a pumpkin's lobes. Texture u goes once round, with the
    /// middle of the texture facing +Z (the athlete's front); v runs up the profile.
    static func lathe(
        profile: [SIMD2<Float>],
        segments: Int = 32,
        ribs: (@Sendable (Float) -> Float)? = nil
    ) -> MountainGearGeometry {
        var shape = MountainGearGeometry()
        guard profile.count >= 2, segments >= 3 else { return shape }
        var lengths: [Float] = [0]
        for i in 1..<profile.count {
            lengths.append(lengths[i - 1] + simd_distance(profile[i - 1], profile[i]))
        }
        let total = max(lengths.last ?? 1, 1e-6)
        let columns = segments + 1
        for i in 0...segments {
            // The seam sits behind the athlete, so the front of the texture is unbroken.
            let angle = -Float.pi + 2 * .pi * Float(i) / Float(segments)
            let scale = ribs?(angle) ?? 1
            for (j, point) in profile.enumerated() {
                let radius = point.x * scale
                shape.positions.append(SIMD3(radius * sin(angle), point.y, radius * cos(angle)))
                shape.uvs.append(SIMD2(Float(i) / Float(segments), lengths[j] / total))
            }
        }
        let rows = profile.count
        for i in 0..<segments {
            for j in 0..<(rows - 1) {
                let a = UInt32(i * rows + j), b = UInt32(((i + 1) % columns) * rows + j)
                shape.indices += [a, b, a + 1, b, b + 1, a + 1]
            }
        }
        shape.recomputeNormals(weldingSeamOf: rows, columns: columns)
        return shape
    }

    /// A round tube of `radius` along `path`, open at both ends unless `closed` joins the last
    /// point back to the first; `taper` scales the radius at each point. Texture u runs along the
    /// path, v round the tube.
    static func tube(
        path: [SIMD3<Float>],
        radius: Float,
        taper: [Float]? = nil,
        sides: Int = 10,
        closed: Bool = false,
        flatten: Float = 1
    ) -> MountainGearGeometry {
        var shape = MountainGearGeometry()
        guard path.count >= 2 else { return shape }
        let count = path.count
        var reference = SIMD3<Float>(0, 1, 0)
        var lengths: [Float] = [0]
        for i in 1..<count { lengths.append(lengths[i - 1] + simd_distance(path[i - 1], path[i])) }
        let total = max(lengths.last ?? 1, 1e-6)
        for (i, point) in path.enumerated() {
            let previous = path[closed ? (i - 1 + count) % count : max(i - 1, 0)]
            let next = path[closed ? (i + 1) % count : min(i + 1, count - 1)]
            let tangent = simd_normalize(next - previous)
            if abs(simd_dot(reference, tangent)) > 0.95 { reference = SIMD3(1, 0, 0) }
            let side = simd_normalize(simd_cross(tangent, reference))
            let up = simd_cross(side, tangent)
            reference = up
            for k in 0...sides {
                let angle = 2 * Float.pi * Float(k) / Float(sides)
                let offset = side * cos(angle) + up * sin(angle) * flatten
                shape.positions.append(point + offset * radius * (taper?[i] ?? 1))
                shape.normals.append(simd_normalize(side * cos(angle) + up * sin(angle) / max(flatten, 0.05)))
                shape.uvs.append(SIMD2(lengths[i] / total, Float(k) / Float(sides)))
            }
        }
        let ring = sides + 1
        let spans = closed ? count : count - 1
        for i in 0..<spans {
            let next = (i + 1) % count
            for k in 0..<sides {
                let a = UInt32(i * ring + k), b = UInt32(next * ring + k)
                shape.indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        return shape
    }

    /// An axis-aligned box centred on the origin, flat-shaded.
    static func box(size: SIMD3<Float>) -> MountainGearGeometry {
        var shape = MountainGearGeometry()
        let h = size / 2
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)),
            (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0))
        ]
        for face in faces {
            let base = UInt32(shape.positions.count)
            let centre = face.normal * h
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                shape.positions.append(centre + face.u * h * su + face.v * h * sv)
                shape.normals.append(face.normal)
                shape.uvs.append(SIMD2((su + 1) / 2, (sv + 1) / 2))
            }
            shape.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return shape
    }

    /// A UV sphere, for a knob or a bead.
    static func sphere(radius: Float, segments: Int = 16) -> MountainGearGeometry {
        let rings = max(segments / 2, 3)
        let profile = (0...rings).map { j -> SIMD2<Float> in
            let phi = Float.pi * Float(j) / Float(rings)
            return SIMD2(sin(phi) * radius, -cos(phi) * radius)
        }
        return lathe(profile: profile, segments: segments)
    }

    // MARK: - Shading

    /// Area-weighted vertex normals from the triangles. A lathe's seam column is a copy of its
    /// first, so the two are averaged and the join does not show.
    private mutating func recomputeNormals(weldingSeamOf rows: Int? = nil, columns: Int? = nil) {
        var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for start in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[start]), b = Int(indices[start + 1]), c = Int(indices[start + 2])
            let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            accumulated[a] += normal
            accumulated[b] += normal
            accumulated[c] += normal
        }
        if let rows, let columns, columns > 1 {
            let last = (columns - 1) * rows
            for j in 0..<rows {
                let sum = accumulated[j] + accumulated[last + j]
                accumulated[j] = sum
                accumulated[last + j] = sum
            }
        }
        normals = accumulated.enumerated().map { index, normal in
            let length = simd_length(normal)
            if length > 1e-9 { return normal / length }
            // A pole: point straight along the axis it sits on.
            return positions[index].y >= 0 ? SIMD3(0, 1, 0) : SIMD3(0, -1, 0)
        }
    }
}
