import Foundation
import simd

/// Flat-shaded source geometry for the reusable props, as plain triangles so a course piece can
/// bake many of them into its one mesh.
struct MountainPropTemplate: Sendable {
    struct Triangle: Sendable {
        let corners: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        /// Which of the prop's materials the triangle takes (a pine's foliage or its trunk).
        let part: Int
    }

    let triangles: [Triangle]

    /// A low-poly pine, about 3.5 m tall at scale 1: a trunk and three stacked cones.
    static let pine: MountainPropTemplate = {
        var triangles: [Triangle] = []
        func cone(radius: Float, height: Float, base: Float, sides: Int, part: Int, twist: Float) {
            let apex = SIMD3<Float>(0, base + height, 0)
            for side in 0..<sides {
                let a0 = twist + Float(side) / Float(sides) * 2 * .pi
                let a1 = twist + Float(side + 1) / Float(sides) * 2 * .pi
                let p0 = SIMD3<Float>(cos(a0) * radius, base, sin(a0) * radius)
                let p1 = SIMD3<Float>(cos(a1) * radius, base, sin(a1) * radius)
                triangles.append(Triangle(corners: (p0, apex, p1), part: part))
                triangles.append(Triangle(corners: (p0, p1, SIMD3(0, base, 0)), part: part))
            }
        }
        cone(radius: 0.13, height: 1.1, base: 0, sides: 5, part: 1, twist: 0)
        cone(radius: 0.95, height: 1.9, base: 0.7, sides: 7, part: 0, twist: 0.2)
        cone(radius: 0.75, height: 1.6, base: 1.45, sides: 7, part: 0, twist: 0.6)
        cone(radius: 0.52, height: 1.3, base: 2.15, sides: 7, part: 0, twist: 0.9)
        return MountainPropTemplate(triangles: triangles)
    }()

    /// A lumpy boulder about a metre across at scale 1, half sunk in the ground.
    static let boulder: MountainPropTemplate = {
        // An octahedron split once toward a sphere, then squashed and roughened.
        var faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        let x = SIMD3<Float>(1, 0, 0), y = SIMD3<Float>(0, 1, 0), z = SIMD3<Float>(0, 0, 1)
        let octahedron = [(y, z, x), (y, x, -z), (y, -z, -x), (y, -x, z), (-y, x, z), (-y, -z, x), (-y, -x, -z), (-y, z, -x)]
        for (a, b, c) in octahedron {
            let ab = simd_normalize(a + b), bc = simd_normalize(b + c), ca = simd_normalize(c + a)
            faces.append(contentsOf: [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)])
        }
        func shape(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let bump = Float(MountainNoise.value(Double(p.x * 2.1), Double(p.z * 2.1 + p.y), seed: 17)) * 0.18
            let r = 0.5 + bump
            return SIMD3(p.x * r * 1.1, p.y * r * 0.62 + 0.12, p.z * r)
        }
        return MountainPropTemplate(triangles: faces.map { Triangle(corners: (shape($0.0), shape($0.1), shape($0.2)), part: 0) })
    }()
}
