import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Shared materials and meshes for Ascend Mountain's surroundings, built once per scene from the
/// region data. Course pieces bake their own mountainside (`MountainTerrainPatch`) against the one
/// material table here, so a piece never allocates a material mid-climb (spec 24).
@MainActor
struct MountainEnvironmentResources {
    /// How far each haze level has faded toward the region's haze colour.
    static let hazeMix: [Double] = [0, 0.3, 0.55, 0.78]

    let world: MountainWorld
    let stairMaterials: [any RealityKit.Material]
    /// Every material a baked course-piece surround can reference, laid out by `layout`.
    let decorMaterials: [any RealityKit.Material]
    let layout: MountainDecorMaterialLayout
    let skybox: EnvironmentResource?

    /// Haze levels close enough for ground detail to read; farther ground stays flat colour.
    static let detailedHazeLevels = 0...1

    static func make(
        world: MountainWorld,
        stone: MountainScannedMaterial?,
        kerb: MountainScannedMaterial?,
        ground: [MountainTerrainBucket.Surface: MountainScannedMaterial] = [:]
    ) -> MountainEnvironmentResources {
        let regions = world.regions.regions

        var decor: [any RealityKit.Material] = []
        for region in regions {
            let palette = region.environment.palette
            for surface in MountainTerrainBucket.Surface.allCases {
                let color: MountainColor
                switch surface {
                case .grass: color = palette.grass
                case .rock: color = palette.rock
                case .snow: color = palette.snow
                }
                for haze in 0..<MountainTerrainBucket.hazeLevels {
                    let tint = color.mixed(with: palette.haze, amount: hazeMix[haze])
                    if detailedHazeLevels.contains(haze), let detail = ground[surface] {
                        decor.append(Self.detailed(tint, detail))
                    } else {
                        decor.append(Self.matte(tint, roughness: surface == .snow ? 0.8 : 0.96))
                    }
                }
            }
        }
        for region in regions {
            decor.append(Self.matte(region.environment.palette.foliage, roughness: 0.9))
        }
        decor.append(Self.matte(MountainColor(red: 0.33, green: 0.24, blue: 0.18), roughness: 1))
        for region in regions {
            decor.append(Self.matte(region.environment.palette.rock.mixed(with: MountainColor(red: 1, green: 1, blue: 1), amount: 0.04), roughness: 0.95))
        }

        return MountainEnvironmentResources(
            world: world,
            stairMaterials: [Self.scanned(stone), Self.scanned(kerb)],
            decorMaterials: decor,
            layout: MountainDecorMaterialLayout(regionCount: regions.count),
            skybox: MountainSkyImage.image(for: regions[0].environment.sky, haze: regions[0].environment.palette.haze)
                .flatMap { try? EnvironmentResource(equirectangular: $0) }
        )
    }

    private static func matte(_ color: MountainColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.uiColor)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    /// Ground in the area's own colour with a scanned grey detail pressed into it.
    private static func detailed(_ tint: MountainColor, _ detail: MountainScannedMaterial) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint.uiColor, texture: .init(detail.color))
        material.normal = .init(texture: .init(detail.normal))
        material.roughness = .init(texture: .init(detail.roughness))
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    private static func scanned(_ scan: MountainScannedMaterial?) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let scan {
            material.baseColor = .init(tint: .white, texture: .init(scan.color))
            material.normal = .init(texture: .init(scan.normal))
            material.roughness = .init(texture: .init(scan.roughness))
        } else {
            material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.6, blue: 0.57, alpha: 1))
            material.roughness = .init(floatLiteral: 0.88)
        }
        material.metallic = .init(floatLiteral: 0)
        return material
    }
}

extension MountainColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// A photoscanned surface bundled with the app (`scripts/mountain-art/fetch-mountain-textures.sh`,
/// CC0 from Poly Haven): colour with its ambient occlusion baked in, a normal map and roughness.
@MainActor
struct MountainScannedMaterial {
    let color: TextureResource
    let normal: TextureResource
    let roughness: TextureResource

    static func load(_ name: String, bundle: Bundle = .main) async throws -> MountainScannedMaterial {
        func texture(_ suffix: String, _ semantic: TextureResource.Semantic) async throws -> TextureResource {
            guard let url = bundle.url(forResource: name + suffix, withExtension: "jpg") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name + suffix + ".jpg"])
            }
            return try await TextureResource(contentsOf: url, options: .init(semantic: semantic))
        }
        return MountainScannedMaterial(
            color: try await texture("", .color),
            normal: try await texture("-normal", .normal),
            roughness: try await texture("-roughness", .raw)
        )
    }
}

/// An equirectangular sky: the zenith colour overhead easing to the horizon, a soft sun glow, and
/// the region's haze below the horizon.
enum MountainSkyImage {
    static let sunDirection = simd_normalize(SIMD3<Double>(0.42, 0.52, 0.74))

    static func image(for sky: MountainEnvironmentProfile.Sky, haze: MountainColor, width: Int = 256, height: Int = 128) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let zenith = SIMD3(sky.zenith.red, sky.zenith.green, sky.zenith.blue)
        let horizon = SIMD3(sky.horizon.red, sky.horizon.green, sky.horizon.blue)
        let below = SIMD3(haze.red, haze.green, haze.blue)
        let sun = SIMD3(sky.sun.red, sky.sun.green, sky.sun.blue)

        for row in 0..<height {
            let elevation = .pi / 2 - (Double(row) + 0.5) / Double(height) * .pi
            for column in 0..<width {
                let azimuth = (Double(column) + 0.5) / Double(width) * 2 * .pi
                let direction = SIMD3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
                var color: SIMD3<Double>
                if elevation >= 0 {
                    color = horizon + (zenith - horizon) * pow(sin(elevation), 0.5)
                } else {
                    color = horizon + (below - horizon) * min(-sin(elevation) * 4, 1)
                }
                let facing = max(simd_dot(direction, sunDirection), 0)
                color += sun * (pow(facing, 64) * 0.9 + pow(facing, 6) * 0.18)
                let clamped = simd_clamp(color, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(clamped.x)
                pixels[offset + 1] = UInt8(clamped.y)
                pixels[offset + 2] = UInt8(clamped.z)
            }
        }
        return cgImage(pixels, size: width, height: height, sRGB: true)
    }
}

private func cgImage(_ pixels: [UInt8], size: Int, height: Int? = nil, sRGB: Bool) -> CGImage? {
    let rows = height ?? size
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    let space = sRGB ? CGColorSpace(name: CGColorSpace.sRGB) : CGColorSpace(name: CGColorSpace.linearSRGB)
    return CGImage(
        width: size,
        height: rows,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: size * 4,
        space: space ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
}
