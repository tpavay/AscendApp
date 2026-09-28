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

    /// Two rings of mountain range around the horizon: ridged crests that wrap seamlessly all the
    /// way round, rock up to a shoulder and snow above it on the high crests. The nearer ring is
    /// lower; the farther one stands taller behind it. Material 0 is rock, 1 is snow.
    static func mountainRanges(seed: UInt64 = 5) -> MountainMeshData {
        var mesh = MountainMeshData()
        let segments = 180
        let layers: [(distance: Float, depth: Float, height: Float, period: Int, salt: UInt64)] = [
            (560, 150, 240, 9, 1),
            (930, 210, 430, 7, 2)
        ]
        for layer in layers {
            var crest: [SIMD3<Float>] = [], shoulder: [SIMD3<Float>] = [], base: [SIMD3<Float>] = [], heights: [Float] = []
            for i in 0..<segments {
                let t = Double(i) / Double(segments) * Double(layer.period)
                var ridged = 0.0, amplitude = 0.6, frequency = 1
                for octave in 0..<4 {
                    let n = MountainNoise.periodicValue(Double(frequency) * t, 3.7 + Double(octave), period: layer.period * frequency, seed: seed &+ layer.salt &+ UInt64(octave))
                    ridged += amplitude * (1 - abs(n))
                    frequency *= 2
                    amplitude *= 0.5
                }
                let height = layer.height * Float(0.38 + 0.9 * pow(min(ridged / 1.05, 1), 1.6))
                let angle = Float(i) / Float(segments) * 2 * .pi
                let out = SIMD3<Float>(sin(angle), 0, -cos(angle))
                let wobble = Float(MountainNoise.periodicValue(t * 3, 9.1, period: layer.period * 3, seed: seed &+ 40)) * 40
                crest.append(out * (layer.distance + wobble) + SIMD3(0, height, 0))
                shoulder.append(out * (layer.distance + wobble - layer.depth * 0.42) + SIMD3(0, height * 0.58, 0))
                base.append(out * (layer.distance - layer.depth) + SIMD3(0, -40, 0))
                heights.append(height)
            }
            for i in 0..<segments {
                let j = (i + 1) % segments
                let inward = -simd_normalize(SIMD3(crest[i].x, 0, crest[i].z)) + SIMD3(0, 0.35, 0)
                mesh.addFlat(base[i], base[j], shoulder[j], material: 0, facing: inward)
                mesh.addFlat(base[i], shoulder[j], shoulder[i], material: 0, facing: inward)
                let snow: UInt32 = (heights[i] + heights[j]) / 2 > layer.height * 0.42 ? 1 : 0
                mesh.addFlat(shoulder[i], shoulder[j], crest[j], material: snow, facing: inward + SIMD3(0, 0.3, 0))
                mesh.addFlat(shoulder[i], crest[j], crest[i], material: snow, facing: inward + SIMD3(0, 0.3, 0))
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
