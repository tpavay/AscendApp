import Foundation
import RealityKit
import UIKit

/// The far scenery and the markers: sky, distant peaks, valley floor, clouds, and the stone
/// gates standing on the staircase. Everything here follows the camera or the course; nothing
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
    private var gates: [String: Entity] = [:]
    private var appliedSkyKey: [Int]?
    private var seaDepth: Float = 400

    init(resources: MountainEnvironmentResources) throws {
        self.resources = resources
        sky = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.skyDome(radius: Self.skyRadius)), materials: [UnlitMaterial()])
        peaks = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.peakRing()), materials: [UnlitMaterial(), UnlitMaterial()])
        floor = ModelEntity(mesh: try MountainMeshResource.make(MountainFarGeometry.disc(radius: 2_400)), materials: [UnlitMaterial()])
        cloudSea = ModelEntity(
            mesh: try MountainMeshResource.make(MountainFarGeometry.clouds(count: 260, innerRadius: 40, outerRadius: 1_100, heightSpread: 14, puffSize: 18...46, seed: 3)),
            materials: [Self.cloudMaterial()]
        )
        cloudBanks = ModelEntity(
            mesh: try MountainMeshResource.make(MountainFarGeometry.clouds(count: 34, innerRadius: 90, outerRadius: 420, heightSpread: 50, puffSize: 10...26, seed: 4)),
            materials: [Self.cloudMaterial()]
        )
        cloudSea.isEnabled = false
        cloudBanks.isEnabled = false
        for entity in [sky, peaks, floor, cloudSea, cloudBanks] {
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
        let seaTarget: Float = region.environment.clouds == .below ? 48 : 400
        seaDepth += (seaTarget - seaDepth) * Float(min(deltaTime / 6, 1))
        cloudSea.isEnabled = seaDepth < 380
        cloudSea.position = SIMD3(camera.x, climberY - seaDepth, camera.z)
        cloudBanks.isEnabled = region.environment.clouds == .around
        cloudBanks.position = SIMD3(camera.x, climberY + 6, camera.z)
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

    // MARK: - Markers

    /// Stands a gate at each marker's stair, building a marker's gate the first time it is near.
    func place(markers: [MountainMarkerFrame]) {
        let live = Set(markers.map(\.marker.id))
        for (id, gate) in gates where !live.contains(id) {
            gate.isEnabled = false
        }
        for frame in markers {
            let gate = gates[frame.marker.id] ?? makeGate(for: frame.marker)
            gate.position = frame.renderPosition
            gate.orientation = simd_quatf(angle: frame.heading, axis: [0, 1, 0])
            gate.isEnabled = true
        }
    }

    private func makeGate(for marker: MountainMarker) -> Entity {
        let gate = Entity()
        let stone = resources.stairMaterials[0]
        let span = Float(MountainStairGeometry.width / 2 + MountainChunkGeometry.kerbWidth) + 0.28
        let pillar = MeshResource.generateBox(size: [0.46, 4.2, 0.46], cornerRadius: 0.04)
        for side: Float in [-1, 1] {
            let entity = ModelEntity(mesh: pillar, materials: [stone])
            entity.position = [side * span, 1.1, 0]
            gate.addChild(entity)
            let cap = ModelEntity(mesh: .generateBox(size: [0.6, 0.18, 0.6], cornerRadius: 0.03), materials: [stone])
            cap.position = [side * span, 3.25, 0]
            gate.addChild(cap)
        }
        let lintel = ModelEntity(mesh: .generateBox(size: [span * 2 + 0.9, 0.5, 0.52], cornerRadius: 0.05), materials: [stone])
        lintel.position = [0, 3.55, 0]
        gate.addChild(lintel)

        if let plaque = Self.plaqueMaterial(title: marker.title, subtitle: marker.subtitle) {
            let face = ModelEntity(mesh: .generatePlane(width: 1.9, height: 0.95, cornerRadius: 0.06), materials: [plaque])
            face.position = [0, 3.55, 0.27]
            gate.addChild(face)
        }
        gates[marker.id] = gate
        root.addChild(gate)
        return gate
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
