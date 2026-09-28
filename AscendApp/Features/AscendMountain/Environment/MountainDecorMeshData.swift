import Foundation
import simd

/// Where each surround material sits in the one material table every course piece shares:
/// terrain buckets first, then foliage per region, the shared trunk, and rock per region.
struct MountainDecorMaterialLayout: Equatable, Sendable {
    let regionCount: Int

    var terrainMaterialCount: Int {
        regionCount * MountainTerrainBucket.Surface.allCases.count * MountainTerrainBucket.hazeLevels
    }

    var materialCount: Int { terrainMaterialCount + regionCount + 1 + regionCount }

    func terrain(_ bucket: MountainTerrainBucket) -> Int {
        (bucket.regionIndex * MountainTerrainBucket.Surface.allCases.count + bucket.surface.rawValue) * MountainTerrainBucket.hazeLevels + bucket.haze
    }

    func foliage(region: Int) -> Int { terrainMaterialCount + region }
    var trunk: Int { terrainMaterialCount + regionCount }
    func rock(region: Int) -> Int { terrainMaterialCount + regionCount + 1 + region }
}

/// One course piece's surroundings - ground, trees and boulders - flattened into a single
/// flat-shaded triangle list with one material per face, ready to become one mesh.
struct MountainDecorMeshData: Sendable {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var indices: [UInt32] = []
    private(set) var faceMaterials: [UInt32] = []

    var triangleCount: Int { faceMaterials.count }

    init(patch: MountainTerrainPatch, layout: MountainDecorMaterialLayout) {
        for (bucket, triangleIndices) in patch.triangles.sorted(by: { layout.terrain($0.key) < layout.terrain($1.key) }) {
            let material = UInt32(layout.terrain(bucket))
            for start in stride(from: 0, to: triangleIndices.count, by: 3) {
                let a = Int(triangleIndices[start]), b = Int(triangleIndices[start + 1]), c = Int(triangleIndices[start + 2])
                append(patch.positions[a], patch.positions[b], patch.positions[c], normal: patch.normals[a], material: material)
            }
        }
        for tree in patch.trees {
            bake(.pine, instance: tree) { part in
                UInt32(part == 0 ? layout.foliage(region: tree.regionIndex) : layout.trunk)
            }
        }
        for rock in patch.rocks {
            bake(.boulder, instance: rock) { _ in UInt32(layout.rock(region: rock.regionIndex)) }
        }
    }

    private mutating func bake(_ template: MountainPropTemplate, instance: MountainDecorInstance, material: (Int) -> UInt32) {
        let rotation = simd_quatf(angle: instance.yaw, axis: SIMD3(0, 1, 0))
        func place(_ point: SIMD3<Float>) -> SIMD3<Float> {
            rotation.act(point * instance.scale) + instance.position
        }
        for triangle in template.triangles {
            let a = place(triangle.corners.0), b = place(triangle.corners.1), c = place(triangle.corners.2)
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            guard length > 1e-8 else { continue }
            append(a, b, c, normal: cross / length, material: material(triangle.part))
        }
    }

    private mutating func append(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>, material: UInt32) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [base, base + 1, base + 2])
        faceMaterials.append(material)
    }
}
