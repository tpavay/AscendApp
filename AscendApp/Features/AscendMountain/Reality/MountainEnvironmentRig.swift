import Foundation
import RealityKit
import UIKit

/// The far scenery and the markers: sky, distant peaks, valley floor, clouds, and the gates and
/// trail posts standing on the staircase. Everything here follows the camera or the course; nothing
/// decides anything about the climb.
@MainActor
final class MountainEnvironmentRig {
    static let skyRadius: Float = 1_400

    let root = Entity()
    private let resources: MountainEnvironmentResources
    private let sky: ModelEntity
    private let peaks: ModelEntity
    private let floor: ModelEntity
    private let cloudSea: ModelEntity
    private let cloudBanks: ModelEntity
    private let mist: ModelEntity
    private let veil: ModelEntity
    private var markerEntities: [String: Entity] = [:]
    private var appliedSkyKey: [Int]?
    private var seaDepth: Float = 400

    init(resources: MountainEnvironmentResources) throws {
        self.resources = resources
        sky = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.skyDome(radius: Self.skyRadius)), materials: [UnlitMaterial()])
        peaks = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.mountainRanges()), materials: [UnlitMaterial(), UnlitMaterial()])
        floor = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.disc(radius: 2_400)), materials: [UnlitMaterial()])
        cloudSea = ModelEntity(
            mesh: try MountainMeshResource.make(MountainFarGeometry.clouds(count: 260, innerRadius: 40, outerRadius: 1_100, heightSpread: 14, puffSize: 18...46, seed: 3)),
            materials: [Self.cloudMaterial()]
        )
        cloudBanks = ModelEntity(
            mesh: try MountainMeshResource.make(MountainFarGeometry.clouds(count: 34, innerRadius: 90, outerRadius: 420, heightSpread: 50, puffSize: 10...26, seed: 4)),
            materials: [Self.cloudMaterial()]
        )
        // Close puffs, starting just past the climber so they never veil them, translucent so the
        // stairs fade into them rather than vanish.
        mist = ModelEntity(
            mesh: try MountainMeshResource.make(MountainFarGeometry.clouds(count: 240, innerRadius: 6.8, outerRadius: 50, heightSpread: 14, puffSize: 2.2...5.5, seed: 5)),
            materials: [Self.cloudMaterial()]
        )
        mist.components.set(OpacityComponent(opacity: 0.5))
        veil = ModelEntity(mesh: .generatePlane(width: Self.veilWidth, height: Self.veilHeight), materials: [Self.veilMaterial()])
        veil.position = [0, 0, -Self.veilDistance]
        veil.components.set(OpacityComponent(opacity: 0))
        veil.isEnabled = false
        cloudSea.isEnabled = false
        cloudBanks.isEnabled = false
        mist.isEnabled = false
        for entity in [sky, peaks, floor, cloudSea, cloudBanks, mist] {
            root.addChild(entity)
        }
    }

    /// Places the far scenery around the camera and restyles it for the climber's height.
    /// - Parameters:
    ///   - camera: the camera's render-space position.
    ///   - climberY: the athlete's render-space height.
    ///   - steps: the climber's visual step count, which picks the region blend.
    ///   - altitude: metres climbed, which sinks the distant peaks as the climber rises past them.
    func update(camera: SIMD3<Float>, climberY: Float, steps: Double, altitude: Double, deltaTime: Double) {
        let regions = resources.world.regions
        sky.position = camera
        let sink = Float(160 + altitude * 0.42)
        peaks.position = SIMD3(camera.x, climberY - sink, camera.z)
        floor.position = SIMD3(camera.x, climberY - Float(230 + altitude * 0.3), camera.z)

        let region = regions.region(atSteps: steps)
        let seaTarget: Float = switch region.environment.clouds {
        case .below: 48
        case .through: 5
        case .none, .around: 400
        }
        seaDepth += (seaTarget - seaDepth) * Float(min(deltaTime / 6, 1))
        cloudSea.isEnabled = seaDepth < 380
        cloudSea.position = SIMD3(camera.x, climberY - seaDepth, camera.z)
        cloudBanks.isEnabled = region.environment.clouds == .around || region.environment.clouds == .through
        cloudBanks.position = SIMD3(camera.x, climberY + 6, camera.z)
        mist.isEnabled = region.environment.clouds == .through
        mist.position = SIMD3(camera.x, climberY + 1, camera.z)
        let insideCloud = Float(regions.blended({ $0.clouds == .through ? 1 : 0 }, atSteps: steps))
        veil.isEnabled = insideCloud > 0.01
        veil.components.set(OpacityComponent(opacity: insideCloud))
        floor.isEnabled = seaDepth > 120

        restyle(steps: steps)
    }

    /// Recolours the sky and far scenery for the blended region colours, only when they moved
    /// enough to see: a few times across a region boundary, never per frame.
    private func restyle(steps: Double) {
        let regions = resources.world.regions
        let zenith = regions.blendedColor({ $0.sky.zenith }, atSteps: steps)
        let horizon = regions.blendedColor({ $0.sky.horizon }, atSteps: steps)
        let haze = regions.blendedColor({ $0.palette.haze }, atSteps: steps)
        let sun = regions.blendedColor({ $0.sky.sun }, atSteps: steps)
        let key = [zenith, horizon, haze].flatMap(Self.quantized)
        guard key != appliedSkyKey else { return }
        appliedSkyKey = key

        let blendedSky = MountainEnvironmentProfile.Sky(zenith: zenith, horizon: horizon, sun: sun, sunIntensity: 0)
        if let image = MountainSkyImage.image(for: blendedSky, haze: haze),
           let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) {
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            material.color = .init(tint: .white, texture: .init(texture))
            sky.model?.materials = [material]
        }

        let rock = regions.blendedColor({ $0.palette.rock }, atSteps: steps)
        let snow = regions.blendedColor({ $0.palette.snow }, atSteps: steps)
        peaks.model?.materials = [
            Self.matte(rock.mixed(with: haze, amount: 0.62)),
            Self.matte(snow.mixed(with: haze, amount: 0.3))
        ]
        let grass = regions.blendedColor({ $0.palette.grass }, atSteps: steps)
        floor.model?.materials = [Self.flat(grass.mixed(with: haze, amount: 0.8))]
    }

    // MARK: - Cloud veil

    /// RealityKit has no fog, and inside a cloud the stairs have to fade away a few steps ahead.
    /// The camera looks up the staircase, so the far stairs fill the top of the screen: a white
    /// veil hung just in front of the lens, dense at the top and clear before it reaches the
    /// climber, reads as cloud without a per-material fog pass.
    func attachVeil(to camera: Entity) {
        camera.addChild(veil)
    }

    private static let veilDistance: Float = 0.3
    /// The camera's 60 degree vertical view is 0.35 m tall at the veil's distance; the plane
    /// overhangs it, and is wide enough for any screen shape.
    private static let veilHeight: Float = 0.4
    private static let veilWidth: Float = 0.9

    private static func veilMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        let width = 4
        let rows = 256
        let visibleHeight = 2 * veilDistance * tan(Float.pi / 6)
        let hidden = (veilHeight - visibleHeight) / 2
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        for row in 0..<rows {
            // Where this row lands on screen, 0 at the top edge.
            let screen = ((Float(row) + 0.5) / Float(rows) * veilHeight - hidden) / visibleHeight
            let t = min(max((screen - 0.04) / 0.36, 0), 1)
            let alpha = 0.92 * (1 - t * t * (3 - 2 * t))
            for column in 0..<width {
                let offset = (row * width + column) * 4
                // Premultiplied: a near-white cloud colour scaled by its own coverage.
                pixels[offset] = UInt8(alpha * 0.96 * 255)
                pixels[offset + 1] = UInt8(alpha * 0.97 * 255)
                pixels[offset + 2] = UInt8(alpha * 0.98 * 255)
                pixels[offset + 3] = UInt8(alpha * 255)
            }
        }
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let image = CGImage(
               width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
               space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
           ),
           let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
        }
        return material
    }

    // MARK: - Markers

    /// Stands each marker at its stair, building it the first time it is near and letting it go
    /// once it is behind, so a climb of any length holds only the few markers in view.
    func place(markers: [MountainMarkerFrame]) {
        let live = Set(markers.map(\.marker.id))
        for (id, entity) in markerEntities where !live.contains(id) {
            entity.removeFromParent()
            markerEntities[id] = nil
        }
        for frame in markers {
            let entity = markerEntities[frame.marker.id] ?? makeMarker(frame.marker)
            entity.position = frame.renderPosition
            entity.orientation = simd_quatf(angle: frame.heading, axis: [0, 1, 0])
        }
    }

    private func makeMarker(_ marker: MountainMarker) -> Entity {
        let entity: Entity
        switch marker.kind {
        case .gate:
            entity = makeGate(for: marker, proportions: marker.design == "gate_grand" ? .grand : .standard)
        case .post:
            entity = makePost(for: marker)
        }
        markerEntities[marker.id] = entity
        root.addChild(entity)
        return entity
    }

    private struct GateProportions {
        static let standard = GateProportions(pillarWidth: 0.46, pillarHeight: 3.3, lintelHeight: 0.5, crown: false, plaqueWidth: 1.9)
        static let grand = GateProportions(pillarWidth: 0.62, pillarHeight: 3.5, lintelHeight: 0.64, crown: true, plaqueWidth: 2.4)

        let pillarWidth: Float
        let pillarHeight: Float
        let lintelHeight: Float
        /// A second, narrower block stacked on the lintel.
        let crown: Bool
        let plaqueWidth: Float
    }

    /// A stone gate spanning the staircase, its number on the lintel facing the approaching climber.
    private func makeGate(for marker: MountainMarker, proportions: GateProportions) -> Entity {
        let gate = Entity()
        let stone = resources.stairMaterials[0]
        let span = Float(MountainStairGeometry.width / 2 + MountainChunkGeometry.kerbWidth) + 0.28 + (proportions.pillarWidth - 0.46) / 2
        // Pillars reach a metre below the tread so they stand in the ground on any slope.
        let pillarBottom: Float = -1
        let pillarTop = proportions.pillarHeight - 1
        let pillar = MeshResource.generateBox(size: [proportions.pillarWidth, pillarTop - pillarBottom, proportions.pillarWidth], cornerRadius: 0.04)
        for side: Float in [-1, 1] {
            let entity = ModelEntity(mesh: pillar, materials: [stone])
            entity.position = [side * span, (pillarTop + pillarBottom) / 2, 0]
            gate.addChild(entity)
            let capWidth = proportions.pillarWidth + 0.14
            let cap = ModelEntity(mesh: .generateBox(size: [capWidth, 0.18, capWidth], cornerRadius: 0.03), materials: [stone])
            cap.position = [side * span, pillarTop + 0.05, 0]
            gate.addChild(cap)
        }
        let lintelY = pillarTop + proportions.lintelHeight / 2 + 0.1
        let lintelDepth = proportions.pillarWidth + 0.06
        let lintel = ModelEntity(mesh: .generateBox(size: [span * 2 + proportions.pillarWidth * 2, proportions.lintelHeight, lintelDepth], cornerRadius: 0.05), materials: [stone])
        lintel.position = [0, lintelY, 0]
        gate.addChild(lintel)
        if proportions.crown {
            let crown = ModelEntity(mesh: .generateBox(size: [span * 1.1, proportions.lintelHeight * 0.7, lintelDepth * 0.8], cornerRadius: 0.05), materials: [stone])
            crown.position = [0, lintelY + proportions.lintelHeight * 0.85, 0]
            gate.addChild(crown)
        }

        if let plaque = Self.plaqueMaterial(title: marker.title, subtitle: marker.subtitle) {
            let width = proportions.plaqueWidth
            let face = ModelEntity(mesh: .generatePlane(width: width, height: width / 2, cornerRadius: 0.06), materials: [plaque])
            face.position = [0, lintelY, lintelDepth / 2 + 0.01]
            gate.addChild(face)
        }
        return gate
    }

    /// A stone trail post just outside the right kerb, its sign turned in toward the climber.
    private func makePost(for marker: MountainMarker) -> Entity {
        let post = Entity()
        let stone = resources.stairMaterials[0]
        let side = Float(MountainStairGeometry.width / 2 + MountainChunkGeometry.kerbWidth) + 0.3
        let top: Float = 1.15
        let bottom: Float = -1
        let shaft = ModelEntity(mesh: .generateBox(size: [0.2, top - bottom, 0.2], cornerRadius: 0.03), materials: [stone])
        shaft.position = [side, (top + bottom) / 2, 0]
        post.addChild(shaft)

        let sign = Entity()
        sign.position = [side - 0.06, top - 0.04, 0]
        sign.orientation = simd_quatf(angle: -0.35, axis: [0, 1, 0])
        let board = ModelEntity(mesh: .generateBox(size: [0.86, 0.46, 0.07], cornerRadius: 0.03), materials: [stone])
        sign.addChild(board)
        if let plaque = Self.plaqueMaterial(title: marker.title, subtitle: marker.subtitle) {
            let face = ModelEntity(mesh: .generatePlane(width: 0.8, height: 0.4, cornerRadius: 0.04), materials: [plaque])
            face.position = [0, 0, 0.04]
            sign.addChild(face)
        }
        post.addChild(sign)
        return post
    }

    /// The marker's words on dark stone: the number large, the unit in the lime accent, drawn once
    /// into a texture and shown unlit so it reads in any light from the stair-stepper console.
    private static func plaqueMaterial(title: String, subtitle: String?) -> UnlitMaterial? {
        let size = CGSize(width: 1_024, height: 512)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 36).fill()
            UIColor(white: 1, alpha: 0.14).setStroke()
            let border = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14), cornerRadius: 26)
            border.lineWidth = 6
            border.stroke()

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let titleFont = UIFont(name: "Montserrat-Bold", size: 250) ?? .systemFont(ofSize: 250, weight: .heavy)
            let subtitleFont = UIFont(name: "Montserrat-Bold", size: 92) ?? .systemFont(ofSize: 92, weight: .bold)
            let titleHeight: CGFloat = subtitle == nil ? 330 : 290
            (title as NSString).draw(
                in: CGRect(x: 0, y: subtitle == nil ? 80 : 30, width: size.width, height: titleHeight),
                withAttributes: [.font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: style]
            )
            if let subtitle {
                (subtitle as NSString).draw(
                    in: CGRect(x: 0, y: 330, width: size.width, height: 130),
                    withAttributes: [.font: subtitleFont, .foregroundColor: UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 1), .kern: 14, .paragraphStyle: style]
                )
            }
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, withName: nil, options: .init(semantic: .color)) else {
            return nil
        }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        return material
    }

    /// A colour rounded coarsely enough that the sky is rebuilt only for a visible change.
    private static func quantized(_ color: MountainColor) -> [Int] {
        let red = Int(color.red * 60)
        let green = Int(color.green * 60)
        let blue = Int(color.blue * 60)
        return [red, green, blue]
    }

    private static func flat(_ color: MountainColor) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: color.uiColor)
        return material
    }

    private static func matte(_ color: MountainColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.uiColor)
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    private static func cloudMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.96, alpha: 1))
        material.emissiveColor = .init(color: UIColor(white: 1, alpha: 1))
        material.emissiveIntensity = 0.35
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        return material
    }
}

/// Uploads `MountainMeshData` as one mesh with a material slot per face.
@MainActor
enum MountainMeshResource {
    static func make(_ data: MountainMeshData, name: String = "mountain-far") throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        if data.uvs.count == data.positions.count {
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.uvs)
        }
        descriptor.primitives = .triangles(data.indices)
        descriptor.materials = .perFace(data.faceMaterials)
        return try MeshResource.generate(from: [descriptor])
    }
}
