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

    static func make(world: MountainWorld, stonePixels: MountainStonePixels) -> MountainEnvironmentResources {
        let regions = world.regions.regions
        let stone = MountainStoneTexture(pixels: stonePixels)

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
                    decor.append(Self.matte(color.mixed(with: palette.haze, amount: hazeMix[haze]), roughness: surface == .snow ? 0.8 : 0.96))
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
            stairMaterials: [
                Self.stone(stone, tint: UIColor(white: 1, alpha: 1)),
                Self.stone(stone, tint: UIColor(red: 0.8, green: 0.79, blue: 0.76, alpha: 1))
            ],
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

    private static func stone(_ texture: MountainStoneTexture?, tint: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let texture {
            material.baseColor = .init(tint: tint, texture: .init(texture.color))
            material.normal = .init(texture: .init(texture.normal))
        } else {
            material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.6, blue: 0.57, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.88)
        material.metallic = .init(floatLiteral: 0)
        return material
    }
}

extension MountainColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// A procedural granite: mottled grey, speckled, with fine cracks, and a normal map from the same
/// height field so the stairs catch the light like cut stone. The pixels are pure computation and
/// are built off the main actor; only the texture upload runs on it.
struct MountainStonePixels: Sendable {
    static let size = 256

    let color: [UInt8]
    let normal: [UInt8]

    static func make() -> MountainStonePixels {
        let size = Self.size
        var height = [Double](repeating: 0, count: size * size)
        var albedo = [Double](repeating: 0, count: size * size)

        for y in 0..<size {
            for x in 0..<size {
                let u = Double(x) / Double(size), v = Double(y) / Double(size)
                let broad = tiled(u, v, cells: 4, seed: 1)
                let grain = tiled(u, v, cells: 32, seed: 2)
                let speck = MountainNoise.hash(x, y, seed: 3)
                height[y * size + x] = broad * 0.6 + grain * 0.35
                albedo[y * size + x] = 0.6 + broad * 0.09 + grain * 0.05 + (speck > 0.93 ? 0.08 : speck < 0.05 ? -0.1 : 0)
            }
        }

        // Cracks: short random walks cut into the height and darkened.
        var walker = 0
        for crack in 0..<14 {
            var px = MountainNoise.hash(crack, 1, seed: 9) * Double(size)
            var py = MountainNoise.hash(crack, 2, seed: 9) * Double(size)
            var angle = MountainNoise.hash(crack, 3, seed: 9) * 2 * .pi
            for _ in 0..<60 {
                walker += 1
                angle += (MountainNoise.hash(walker, crack, seed: 10) - 0.5) * 0.9
                px += cos(angle) * 1.3
                py += sin(angle) * 1.3
                let ix = (Int(px) % size + size) % size, iy = (Int(py) % size + size) % size
                height[iy * size + ix] -= 0.6
                albedo[iy * size + ix] -= 0.14
            }
        }

        var colorPixels = [UInt8](repeating: 255, count: size * size * 4)
        var normalPixels = [UInt8](repeating: 255, count: size * size * 4)
        let warm = SIMD3<Double>(1.0, 0.975, 0.93)
        for y in 0..<size {
            for x in 0..<size {
                let i = y * size + x
                let rgb = warm * min(max(albedo[i], 0), 1) * 255
                colorPixels[i * 4] = UInt8(min(rgb.x, 255))
                colorPixels[i * 4 + 1] = UInt8(min(rgb.y, 255))
                colorPixels[i * 4 + 2] = UInt8(min(rgb.z, 255))

                let left = height[y * size + (x + size - 1) % size], right = height[y * size + (x + 1) % size]
                let up = height[((y + size - 1) % size) * size + x], down = height[((y + 1) % size) * size + x]
                let n = simd_normalize(SIMD3<Double>((left - right) * 2.2, (up - down) * 2.2, 1))
                normalPixels[i * 4] = UInt8((n.x * 0.5 + 0.5) * 255)
                normalPixels[i * 4 + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                normalPixels[i * 4 + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        return MountainStonePixels(color: colorPixels, normal: normalPixels)
    }

    private static func tiled(_ u: Double, _ v: Double, cells: Int, seed: UInt64) -> Double {
        var sum = 0.0, amplitude = 0.5, period = cells
        for octave in 0..<3 {
            sum += amplitude * MountainNoise.periodicValue(u * Double(period), v * Double(period), period: period, seed: seed &+ UInt64(octave))
            period *= 2
            amplitude *= 0.5
        }
        return sum
    }
}

@MainActor
struct MountainStoneTexture {
    let color: TextureResource
    let normal: TextureResource

    init?(pixels: MountainStonePixels) {
        let size = MountainStonePixels.size
        guard let colorImage = cgImage(pixels.color, size: size, sRGB: true),
              let normalImage = cgImage(pixels.normal, size: size, sRGB: false),
              let color = try? TextureResource(image: colorImage, withName: "mountain-stone-color", options: .init(semantic: .color)),
              let normal = try? TextureResource(image: normalImage, withName: "mountain-stone-normal", options: .init(semantic: .normal)) else {
            return nil
        }
        self.color = color
        self.normal = normal
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
