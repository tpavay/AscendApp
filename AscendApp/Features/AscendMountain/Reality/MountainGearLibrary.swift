import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Makes the seasonal items athletes carry, once each: a mesh per item and a material per paint,
/// shared by every climber carrying it. An item is a few thousand triangles with no skeleton of
/// its own, so a crowded climb spends almost nothing on them.
@MainActor
final class MountainGearLibrary {
    static let shared = MountainGearLibrary()

    /// One item ready to place, and its size, which decides where the hands hold it.
    struct Prepared {
        let mesh: MeshResource
        let materials: [any RealityKit.Material]
        /// From its resting point up to its top, and half its width, in metres.
        let height: Double
        let halfWidth: Double
        /// The candlelight a carved item casts, if it glows.
        let glow: MountainColor?
    }

    private var prepared: [AthleteGear: Prepared] = [:]
    private var loads: [AthleteGear: Task<Void, Never>] = [:]
    private var failed: Set<AthleteGear> = []
    private var materials: [MountainGearModel.Paint: any RealityKit.Material] = [:]

    /// The item ready to place, or nil while it is still being made; a later frame finds it.
    func ready(_ gear: AthleteGear) -> Prepared? {
        if let made = prepared[gear] { return made }
        if loads[gear] == nil, !failed.contains(gear) {
            Task { _ = await prepare(gear) }
        }
        return nil
    }

    /// The item, waiting for it to be made.
    func prepare(_ gear: AthleteGear) async -> Prepared? {
        if let made = prepared[gear] { return made }
        if let loading = loads[gear] {
            await loading.value
            return prepared[gear]
        }
        let load = Task {
            if let made = await make(gear) {
                prepared[gear] = made
            } else {
                failed.insert(gear)
            }
        }
        loads[gear] = load
        await load.value
        loads[gear] = nil
        return prepared[gear]
    }

    private func make(_ gear: AthleteGear) async -> Prepared? {
        let model = MountainGearModel.model(for: gear)
        var descriptors: [MeshDescriptor] = []
        var partMaterials: [any RealityKit.Material] = []
        for (index, part) in model.parts.enumerated() {
            var descriptor = MeshDescriptor(name: "\(gear.rawValue)-\(index)")
            descriptor.positions = MeshBuffers.Positions(part.geometry.positions)
            descriptor.normals = MeshBuffers.Normals(part.geometry.normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(part.geometry.uvs)
            descriptor.primitives = .triangles(part.geometry.indices)
            descriptor.materials = .allFaces(UInt32(index))
            descriptors.append(descriptor)
            partMaterials.append(await material(for: part.paint))
        }
        guard let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
        let positions = model.parts.flatMap(\.geometry.positions)
        let halfWidth = positions.map { max(abs($0.x), abs($0.z)) }.max() ?? 0
        return Prepared(mesh: mesh, materials: partMaterials, height: Double(model.height), halfWidth: Double(halfWidth), glow: model.glow)
    }

    // MARK: - Materials

    private func material(for paint: MountainGearModel.Paint) async -> any RealityKit.Material {
        if let made = materials[paint] { return made }
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: 0)
        switch paint {
        case .color(let color, let roughness):
            material.baseColor = .init(tint: color.uiColor)
            material.roughness = .init(floatLiteral: roughness)
        case .metal(let color, let roughness):
            material.baseColor = .init(tint: color.uiColor)
            material.roughness = .init(floatLiteral: roughness)
            material.metallic = .init(floatLiteral: 1)
        case .pumpkin(let skin):
            material.roughness = .init(floatLiteral: skin == .midnight ? 0.4 : 0.55)
            if let texture = await Self.texture(MountainGearArt.pumpkinSkin(skin)) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            } else {
                material.baseColor = .init(tint: skin.palette.body.uiColor)
            }
        case .carvedGlow(let skin):
            var glow = UnlitMaterial(applyPostProcessToneMap: false)
            if let texture = await Self.texture(MountainGearArt.pumpkinGlow(skin)) {
                glow.color = .init(tint: .white, texture: .init(texture))
            }
            glow.blending = .transparent(opacity: .init(floatLiteral: 1))
            materials[paint] = glow
            return glow
        case .ghostSheet:
            material.roughness = .init(floatLiteral: 0.92)
            material.baseColor = .init(tint: MountainGearModel.sheetWhite.uiColor)
            if let texture = await Self.texture(MountainGearArt.ghostSheet()) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
            // A faint sheen of its own, so the sheet still reads white on a dark stretch.
            material.emissiveColor = .init(color: UIColor(white: 0.16, alpha: 1))
        case .candyCornBands:
            material.roughness = .init(floatLiteral: 0.45)
            if let texture = await Self.texture(MountainGearArt.candyCornBands()) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
        case .wrapper:
            material.roughness = .init(floatLiteral: 0.35)
            if let texture = await Self.texture(MountainGearArt.wrapper()) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
        case .gourdStripes:
            material.roughness = .init(floatLiteral: 0.5)
            if let texture = await Self.texture(MountainGearArt.gourdStripes()) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
        }
        materials[paint] = material
        return material
    }

    private static func texture(_ image: CGImage?) async -> TextureResource? {
        guard let image else { return nil }
        return try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }
}

/// The painted surfaces of the seasonal items, drawn in Core Graphics the first time an item is
/// carried. Drawn with y up, the way a lathe's texture v runs up the shape, and u once round with
/// the item's front at the middle.
enum MountainGearArt {
    private static func faceShapes(_ face: MountainGearModel.PumpkinSkin.Face, width: CGFloat, height: CGFloat) -> [CGPath] {
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * width, y: v * height) }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { point($0.0, $0.1) })
            path.closeSubpath()
            return path
        }
        switch face {
        case .classic:
            var shapes: [CGPath] = []
            for side in [-1.0, 1.0] as [CGFloat] {
                let cx = 0.5 + side * 0.058
                shapes.append(polygon([(cx - 0.034, 0.585), (cx + 0.034, 0.585), (cx + side * 0.012, 0.7)]))
            }
            shapes.append(polygon([(0.484, 0.5), (0.516, 0.5), (0.5, 0.555)]))
            // The upper lip with two teeth hanging down, then a grin with one tooth standing up.
            shapes.append(polygon([(0.405, 0.44), (0.44, 0.415), (0.455, 0.415), (0.462, 0.385), (0.478, 0.385), (0.485, 0.41),
                                   (0.515, 0.41), (0.522, 0.385), (0.538, 0.385), (0.545, 0.415), (0.56, 0.415), (0.595, 0.44),
                                   (0.565, 0.35), (0.52, 0.325), (0.512, 0.35), (0.496, 0.35), (0.49, 0.322), (0.44, 0.34)]))
            return shapes
        case .hollow:
            return [
                CGPath(ellipseIn: CGRect(origin: point(0.428, 0.56), size: CGSize(width: 0.05 * width, height: 0.15 * height)), transform: nil),
                CGPath(ellipseIn: CGRect(origin: point(0.522, 0.56), size: CGSize(width: 0.05 * width, height: 0.15 * height)), transform: nil),
                CGPath(ellipseIn: CGRect(origin: point(0.479, 0.33), size: CGSize(width: 0.042 * width, height: 0.15 * height)), transform: nil)
            ]
        case .grin:
            var shapes: [CGPath] = []
            for side in [-1.0, 1.0] as [CGFloat] {
                let cx = 0.5 + side * 0.06
                shapes.append(polygon([(cx - side * 0.04, 0.6), (cx + side * 0.04, 0.66), (cx + side * 0.028, 0.57)]))
            }
            // A wide crescent: the top lip runs straight with square teeth hanging from it, the
            // bottom lip is a smooth arc well below them, so the outline never crosses itself.
            var grin: [(CGFloat, CGFloat)] = [(0.39, 0.49)]
            for tooth in 0..<4 {
                let u = 0.445 + CGFloat(tooth) * 0.03
                grin += [(u, 0.47), (u, 0.43), (u + 0.016, 0.43), (u + 0.016, 0.47)]
            }
            grin += [(0.61, 0.49)]
            for step in 1..<12 {
                let t = CGFloat(step) / 12
                grin.append((0.61 - 0.22 * t, 0.49 - 0.15 * sin(t * .pi)))
            }
            shapes.append(polygon(grin))
            return shapes
        }
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func cgColor(_ color: MountainColor, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }

    static func pumpkinSkin(_ skin: MountainGearModel.PumpkinSkin) -> CGImage? {
        let width = 512, height = 256
        guard let context = context(width: width, height: height) else { return nil }
        let palette = skin.palette
        // Each lobe is lit across its width; the creases and both poles are darker.
        for x in 0..<width {
            let lobe = (Double(x) / Double(width) * 8).truncatingRemainder(dividingBy: 1)
            let swell = sin(lobe * .pi)
            let color = palette.crease.mixed(with: palette.body, amount: min(swell * 2.2, 1))
                .mixed(with: palette.highlight, amount: max(swell - 0.7, 0) * 1.6)
            context.setFillColor(cgColor(color))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let shade = [cgColor(palette.crease, alpha: 0.85), cgColor(palette.crease, alpha: 0), cgColor(palette.crease, alpha: 0), cgColor(palette.crease, alpha: 0.9)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: shade, locations: [0, 0.25, 0.75, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        if let face = skin.face {
            context.setFillColor(CGColor(srgbRed: 0.12, green: 0.05, blue: 0.0, alpha: 1))
            for shape in faceShapes(face, width: CGFloat(width), height: CGFloat(height)) {
                context.addPath(shape)
                context.fillPath()
            }
        }
        return context.makeImage()
    }

    /// Candlelight through the carved face, clear everywhere else.
    static func pumpkinGlow(_ skin: MountainGearModel.PumpkinSkin) -> CGImage? {
        guard let glow = skin.glow, let face = skin.face else { return nil }
        let width = 512, height = 256
        guard let context = context(width: width, height: height) else { return nil }
        context.setFillColor(cgColor(glow))
        for shape in faceShapes(face, width: CGFloat(width), height: CGFloat(height)) {
            context.addPath(shape)
            context.fillPath()
        }
        return context.makeImage()
    }

    /// White cloth, a little darker in its folds, with two eye holes cut at the front of the head.
    static func ghostSheet() -> CGImage? {
        let width = 512, height = 512
        guard let context = context(width: width, height: height) else { return nil }
        for x in 0..<width {
            let fold = 0.5 + 0.5 * sin(Double(x) / Double(width) * 2 * .pi * 10)
            let shade = 0.9 + 0.08 * fold
            context.setFillColor(CGColor(srgbRed: shade, green: shade, blue: shade * 0.98, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        // The sheet's texture runs top to bottom, so the eyes sit near v = 0.15, at the face.
        for u in [0.468, 0.532] {
            context.fillEllipse(in: CGRect(x: (u - 0.018) * Double(width), y: 0.12 * Double(height), width: 0.036 * Double(width), height: 0.06 * Double(height)))
        }
        return context.makeImage()
    }

    /// Yellow at the base, orange through the middle, white at the tip, as v runs up a lathe.
    static func candyCornBands() -> CGImage? {
        let width = 16, height = 256
        guard let context = context(width: width, height: height) else { return nil }
        for (start, end, color) in [
            (0.0, 0.47, CGColor(srgbRed: 0.98, green: 0.76, blue: 0.1, alpha: 1)),
            (0.47, 0.8, CGColor(srgbRed: 0.97, green: 0.47, blue: 0.07, alpha: 1)),
            (0.8, 1.0, CGColor(srgbRed: 0.99, green: 0.97, blue: 0.92, alpha: 1))
        ] {
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: start * Double(height), width: Double(width), height: (end - start) * Double(height)))
        }
        return context.makeImage()
    }

    /// Deep purple with a lime band, the wrapper on a chocolate bar.
    static func wrapper() -> CGImage? {
        let size = 128
        guard let context = context(width: size, height: size) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.33, green: 0.15, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(srgbRed: 0.53, green: 0.83, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: size * 2 / 5, width: size, height: size / 5))
        return context.makeImage()
    }

    /// Dark green stripes down a golden gourd.
    static func gourdStripes() -> CGImage? {
        let width = 256, height = 64
        guard let context = context(width: width, height: height) else { return nil }
        let gold = MountainColor(hex: "#E2B33A")!, green = MountainColor(hex: "#2F5A24")!
        for x in 0..<width {
            let stripe = (Double(x) / Double(width) * 8).truncatingRemainder(dividingBy: 1)
            let amount = stripe < 0.3 ? 1 - stripe / 0.3 * 0.3 : (stripe > 0.85 ? 0.6 : 0)
            context.setFillColor(cgColor(gold.mixed(with: green, amount: amount)))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()
    }
}
