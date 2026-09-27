import CoreGraphics
import RealityKit
import UIKit

/// The shared meshes, materials and sky every Ascend Mountain scene draws with, built once per
/// scene. Chunk slots and athlete parts reference these rather than owning copies (spec 24).
@MainActor
struct MountainSceneResources {
    let chunkMeshes: [MountainChunkKind: MeshResource]
    let chunkMaterials: [any RealityKit.Material]
    let skybox: EnvironmentResource?

    static func make() throws -> MountainSceneResources {
        var meshes: [MountainChunkKind: MeshResource] = [:]
        for kind in MountainChunkKind.allCases {
            meshes[kind] = try chunkMesh(for: kind)
        }

        return MountainSceneResources(
            chunkMeshes: meshes,
            chunkMaterials: MountainChunkGeometry.Surface.allCases.map(material(for:)),
            skybox: MountainSkyGradient.image().flatMap { try? EnvironmentResource(equirectangular: $0) }
        )
    }

    private static func chunkMesh(for kind: MountainChunkKind) throws -> MeshResource {
        let geometry = MountainChunkGeometry(kind: kind)
        var descriptor = MeshDescriptor(name: "mountain-chunk-\(kind.rawValue)")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        descriptor.materials = .perFace(geometry.triangleSurfaces)
        return try MeshResource.generate(from: [descriptor])
    }

    private static func material(for surface: MountainChunkGeometry.Surface) -> any RealityKit.Material {
        let color: UIColor
        switch surface {
        case .stone:
            color = UIColor(red: 0.58, green: 0.6, blue: 0.63, alpha: 1)
        case .nosing:
            color = UIColor(red: 0.3, green: 0.32, blue: 0.35, alpha: 1)
        case .curb:
            color = UIColor(red: 0.46, green: 0.48, blue: 0.51, alpha: 1)
        }
        return SimpleMaterial(color: color, roughness: 0.92, isMetallic: false)
    }
}

/// A procedural equirectangular sky: deep blue overhead, pale at the horizon, grey haze below.
/// Used as both the backdrop and the image-based light, so the prototype needs no image asset.
enum MountainSkyGradient {
    static func image(width: Int = 512, height: Int = 256) -> CGImage? {
        let zenith = SIMD3<Double>(0.16, 0.33, 0.6)
        let horizon = SIMD3<Double>(0.78, 0.85, 0.91)
        let haze = SIMD3<Double>(0.58, 0.63, 0.68)
        let ground = SIMD3<Double>(0.3, 0.33, 0.36)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            // Row 0 is straight up, the middle row is the horizon, the last row straight down.
            let elevation = 1 - 2 * (Double(row) + 0.5) / Double(height)
            let color: SIMD3<Double>
            if elevation >= 0 {
                let t = pow(elevation, 0.55)
                color = horizon + (zenith - horizon) * t
            } else {
                let t = min(-elevation * 3, 1)
                color = horizon + (haze - horizon) * t + (ground - haze) * max(-elevation - 0.33, 0) * 1.5
            }
            let clamped = simd_clamp(color, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
            for column in 0..<width {
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(clamped.x)
                pixels[offset + 1] = UInt8(clamped.y)
                pixels[offset + 2] = UInt8(clamped.z)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
