import Foundation
import simd

/// Triangle geometry with one material slot per face, for the far scenery built once per scene.
struct MountainMeshData: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    var faceMaterials: [UInt32] = []

    /// Appends a flat-shaded triangle, wound to face `outward` when given.
    mutating func addFlat(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: UInt32, facing outward: SIMD3<Float>? = nil) {
        var corners = (a, b, c)
        var normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 1e-8 else { return }
        normal /= length
        if let outward, simd_dot(normal, outward) < 0 {
            corners = (a, c, b)
            normal = -normal
        }
        let base = UInt32(positions.count)
        positions.append(contentsOf: [corners.0, corners.1, corners.2])
        normals.append(contentsOf: [normal, normal, normal])
        uvs.append(contentsOf: [.zero, .zero, .zero])
        indices.append(contentsOf: [base, base + 1, base + 2])
        faceMaterials.append(material)
    }
}

/// The scenery beyond the course: sky dome, distant peaks, the valley floor and clouds. All of it
/// travels with the camera, so it reads as infinitely far away and never runs out.
enum MountainFarGeometry {
    /// An inward-facing sphere mapped for an equirectangular image whose top row is straight up.
    static func skyDome(radius: Float, segments: Int = 48, rings: Int = 24) -> MountainMeshData {
        var mesh = MountainMeshData()
        for ring in 0...rings {
            let v = Float(ring) / Float(rings)
            let elevation = Float.pi / 2 - v * .pi
            for segment in 0...segments {
                let u = Float(segment) / Float(segments)
                let azimuth = u * 2 * .pi
                let direction = SIMD3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
                mesh.positions.append(direction * radius)
                mesh.normals.append(-direction)
                mesh.uvs.append(SIMD2(u, 1 - v))
            }
        }
        let stride = UInt32(segments + 1)
        for ring in 0..<UInt32(rings) {
            for segment in 0..<UInt32(segments) {
                let a = ring * stride + segment, b = a + 1, c = a + stride, d = c + 1
                // Wound to be seen from inside.
                mesh.indices.append(contentsOf: [a, b, c, b, d, c])
                mesh.faceMaterials.append(contentsOf: [0, 0])
            }
        }
        return mesh
    }

    /// A ring of snow-capped peaks around the origin. Material 0 is rock, 1 is snow.
    static func peakRing(count: Int = 26, seed: UInt64 = 5) -> MountainMeshData {
        var mesh = MountainMeshData()
        for peak in 0..<count {
            let r = { (salt: Int) in Float(MountainNoise.hash(peak, salt, seed: seed)) }
            let angle = Float(peak) / Float(count) * 2 * .pi + (r(1) - 0.5) * 0.3
            let distance = 520 + r(2) * 420
            let height = 150 + r(3) * 260
            let radius = height * (0.9 + r(4) * 0.7)
            let centre = SIMD3<Float>(sin(angle) * distance, 0, -cos(angle) * distance)
            let sides = 7 + Int(r(5) * 4)
            let apex = centre + SIMD3(r(6) * 30 - 15, height, r(7) * 30 - 15)
            let snowLine: Float = 0.55 + r(8) * 0.12

            // Two rings of jagged points: the base and a shoulder at the snow line.
            var base: [SIMD3<Float>] = [], shoulder: [SIMD3<Float>] = []
            for side in 0..<sides {
                let a = Float(side) / Float(sides) * 2 * .pi
                let wobble = 0.75 + Float(MountainNoise.hash(peak * 31 + side, 9, seed: seed)) * 0.5
                let outward = SIMD3<Float>(cos(a), 0, sin(a))
                base.append(centre + outward * radius * wobble)
                shoulder.append(centre + (apex - centre) * snowLine + outward * radius * wobble * (1 - snowLine) * 0.9)
            }
            for side in 0..<sides {
                let next = (side + 1) % sides
                let out = simd_normalize(SIMD3(base[side].x - centre.x, 0.4, base[side].z - centre.z))
                mesh.addFlat(base[side], base[next], shoulder[next], material: 0, facing: out)
                mesh.addFlat(base[side], shoulder[next], shoulder[side], material: 0, facing: out)
                mesh.addFlat(shoulder[side], shoulder[next], apex, material: 1, facing: out + SIMD3(0, 0.6, 0))
            }
        }
        return mesh
    }

    static func disc(radius: Float, segments: Int = 48) -> MountainMeshData {
        var mesh = MountainMeshData()
        for segment in 0..<segments {
            let a0 = Float(segment) / Float(segments) * 2 * .pi
            let a1 = Float(segment + 1) / Float(segments) * 2 * .pi
            mesh.addFlat(.zero, SIMD3(cos(a0) * radius, 0, sin(a0) * radius), SIMD3(cos(a1) * radius, 0, sin(a1) * radius), material: 0, facing: SIMD3(0, 1, 0))
        }
        return mesh
    }

    /// Low-poly cloud puffs scattered in an annulus, flattened on top of each other.
    static func clouds(count: Int, innerRadius: Float, outerRadius: Float, heightSpread: Float, puffSize: ClosedRange<Float>, seed: UInt64) -> MountainMeshData {
        var mesh = MountainMeshData()
        let sphere = lowPolySphere()
        for cloud in 0..<count {
            let r = { (salt: Int) in Float(MountainNoise.hash(cloud, salt, seed: seed)) }
            let angle = r(1) * 2 * .pi
            let distance = innerRadius + (outerRadius - innerRadius) * sqrt(r(2))
            let centre = SIMD3<Float>(sin(angle) * distance, (r(3) - 0.5) * heightSpread, -cos(angle) * distance)
            let size = puffSize.lowerBound + (puffSize.upperBound - puffSize.lowerBound) * r(4)
            for puff in 0..<4 {
                let p = { (salt: Int) in Float(MountainNoise.hash(cloud * 7 + puff, salt, seed: seed &+ 1)) }
                let offset = SIMD3((p(1) - 0.5) * size * 2.2, (p(2) - 0.3) * size * 0.35, (p(3) - 0.5) * size * 1.4)
                let scale = SIMD3(size * (0.6 + p(4) * 0.6), size * (0.35 + p(5) * 0.25), size * (0.6 + p(6) * 0.5))
                for (a, b, c) in sphere {
                    mesh.addFlat(centre + offset + a * scale, centre + offset + b * scale, centre + offset + c * scale, material: 0, facing: a + b + c)
                }
            }
        }
        return mesh
    }

    private static func lowPolySphere() -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        let x = SIMD3<Float>(1, 0, 0), y = SIMD3<Float>(0, 1, 0), z = SIMD3<Float>(0, 0, 1)
        let octahedron = [(y, z, x), (y, x, -z), (y, -z, -x), (y, -x, z), (-y, x, z), (-y, -z, x), (-y, -x, -z), (-y, z, -x)]
        var faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for (a, b, c) in octahedron {
            let ab = simd_normalize(a + b), bc = simd_normalize(b + c), ca = simd_normalize(c + a)
            faces.append(contentsOf: [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)])
        }
        return faces
    }
}
