import Foundation
import RealityKit
import UIKit
import simd

/// The colours the athlete is tinted with, one per material slot the asset names. The avatar
/// system will fill this from the climber's saved look; until then every climber wears the
/// Ascend kit.
struct MountainAthleteLook: Equatable, Sendable {
    var skin = MountainColor(red: 0.78, green: 0.58, blue: 0.43)
    var hair = MountainColor(red: 0.42, green: 0.27, blue: 0.16)
    var top = MountainColor(red: 0.53, green: 0.83, blue: 0.04)
    var bottom = MountainColor(red: 0.1, green: 0.11, blue: 0.13)
    var shoe = MountainColor(red: 0.95, green: 0.95, blue: 0.95)
    var shoeAccent = MountainColor(red: 0.13, green: 0.14, blue: 0.16)

    static let ascendKit = MountainAthleteLook()

    func color(forSlot slot: String) -> MountainColor {
        switch slot {
        case "skin": return skin
        case "skinShade": return skin.mixed(with: MountainColor(red: 0, green: 0, blue: 0), amount: 0.12)
        case "hair": return hair
        case "eyes": return MountainColor(red: 0.05, green: 0.04, blue: 0.04)
        case "top": return top
        case "bottom": return bottom
        case "shoe": return shoe
        case "shoeAccent": return shoeAccent
        default: return MountainColor(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

/// The athlete: the CC0 skinned character, posed every frame by `MountainAthletePoser` from
/// `MountainAthleteKinematics`. Feet are planted by IK on the treads the course says, so the
/// climb animation is the steps themselves rather than a clip played over them.
@MainActor
final class MountainAthleteRig {
    /// How an athlete is drawn: as themselves, or as a ghost - one glowing colour, see-through,
    /// so it never reads as a real climber on the stairs.
    enum Style: Equatable {
        case athlete(MountainAthleteLook)
        case ghost(MountainColor)
    }

    let root = Entity()
    private let model: ModelEntity
    private let poser: MountainAthletePoser

    /// How far the foot joint sits behind the middle of the foot, so the sole lands centred on
    /// the tread.
    private static let footSetback = 0.05

    init(asset: MountainAthleteAsset, style: Style = .athlete(.ascendKit), label: String? = nil, bundle: Bundle = .main) throws {
        guard let poser = MountainAthletePoser(asset: asset) else {
            throw MountainAthleteAsset.LoadError.unsupportedFormat("rig is missing a joint the poser needs")
        }
        self.poser = poser

        let slots = Array(Set(asset.parts.map(\.slot))).sorted()
        var contents = MeshResource.Contents()
        guard let skeleton = MeshResource.Skeleton(
            id: "athlete",
            jointNames: asset.joints.map(\.name),
            inverseBindPoseMatrices: asset.joints.map(\.inverseBindMatrix),
            restPoseTransforms: asset.joints.map { joint in
                Transform(
                    scale: .one,
                    rotation: joint.restRotation.float,
                    translation: SIMD3<Float>(joint.restTranslation)
                )
            },
            parentIndices: asset.joints.map(\.parentIndex)
        ) else {
            throw MountainAthleteAsset.LoadError.unsupportedFormat("skeleton rejected")
        }
        contents.skeletons = MeshSkeletonCollection([skeleton])

        var parts: [MeshResource.Part] = []
        for (index, part) in asset.parts.enumerated() {
            let vertices = part.vertexStart..<(part.vertexStart + part.vertexCount)
            var meshPart = MeshResource.Part(id: "part-\(index)", materialIndex: slots.firstIndex(of: part.slot) ?? 0)
            meshPart.positions = MeshBuffers.Positions(Array(asset.positions[vertices]))
            meshPart.normals = MeshBuffers.Normals(Array(asset.normals[vertices]))
            meshPart.textureCoordinates = MeshBuffers.TextureCoordinates(Array(asset.uvs[vertices]))
            meshPart.triangleIndices = MeshBuffers.TriangleIndices(
                asset.indices[part.indexStart..<(part.indexStart + part.indexCount)].map { $0 - UInt32(part.vertexStart) }
            )
            var influences: [MeshJointInfluence] = []
            influences.reserveCapacity(part.vertexCount * 4)
            for vertex in vertices {
                let joints = asset.jointIndices[vertex], weights = asset.jointWeights[vertex]
                for k in 0..<4 {
                    influences.append(MeshJointInfluence(jointIndex: Int(joints[k]), weight: weights[k]))
                }
            }
            meshPart.skeletonID = "athlete"
            meshPart.jointInfluences = .init(influences: MeshBuffers.JointInfluences(influences), influencesPerVertex: 4)
            parts.append(meshPart)
        }
        contents.models = MeshModelCollection([MeshResource.Model(id: "athlete", parts: parts)])
        contents.instances = MeshInstanceCollection([MeshResource.Instance(id: "athlete-0", model: "athlete")])

        let materials: [any RealityKit.Material] = slots.map { slot in
            switch style {
            case .athlete(let look):
                Self.material(for: slot, textures: asset.textures[slot], look: look, bundle: bundle)
            case .ghost(let color):
                Self.ghostMaterial(color)
            }
        }
        model = ModelEntity(mesh: try MeshResource.generate(from: contents), materials: materials)
        root.addChild(model)
        if case .ghost = style {
            model.components.set(OpacityComponent(opacity: 0.5))
        }
        if let label, let tag = Self.tag(label, style: style) {
            tag.position = [0, Float(asset.height) + 0.32, 0]
            root.addChild(tag)
        }
    }

    private static func ghostMaterial(_ color: MountainColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.uiColor)
        material.emissiveColor = .init(color: color.uiColor)
        material.emissiveIntensity = 0.9
        material.roughness = .init(floatLiteral: 0.35)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    /// The words over an athlete's head, drawn once into a texture and turned to face the
    /// camera wherever the stairs bend.
    private static func tag(_ text: String, style: Style) -> Entity? {
        let accent: UIColor = switch style {
        case .ghost(let color): color.uiColor
        case .athlete: UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 1)
        }
        let font = UIFont(name: "Montserrat-Bold", size: 64) ?? .systemFont(ofSize: 64, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .kern: 3]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 88, height: 112)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 0.82).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 56).fill()
            accent.setFill()
            UIBezierPath(ovalIn: CGRect(x: 30, y: 44, width: 24, height: 24)).fill()
            (text as NSString).draw(at: CGPoint(x: 66, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, withName: nil, options: .init(semantic: .color)) else {
            return nil
        }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let height: Float = 0.2
        let plane = ModelEntity(mesh: .generatePlane(width: height * Float(size.width / size.height), height: height), materials: [material])
        let tag = Entity()
        tag.addChild(plane)
        tag.components.set(BillboardComponent())
        return tag
    }

    /// A slot drawn from its textures (skin, eyes, hair) or as a flat colour (the kit). Textured
    /// slots are still multiplied by the look's colour, so the grey hair texture takes the
    /// climber's hair colour; skin and eyes carry their colour in the texture itself.
    private static func material(for slot: String, textures: MountainAthleteAsset.Textures?, look: MountainAthleteLook, bundle: Bundle) -> PhysicallyBasedMaterial {
        func texture(_ name: String?, _ semantic: TextureResource.Semantic) -> TextureResource? {
            guard let name, let url = bundle.url(forResource: name, withExtension: nil) else { return nil }
            return try? TextureResource.load(contentsOf: url, options: .init(semantic: semantic))
        }
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: 0)
        let tint: UIColor = switch slot {
        case "skin", "eyes": .white
        default: look.color(forSlot: slot).uiColor
        }
        if let base = texture(textures?.baseColor, .color) {
            material.baseColor = .init(tint: tint, texture: .init(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let normal = texture(textures?.normal, .normal) {
            material.normal = .init(texture: .init(normal))
        }
        if let roughness = texture(textures?.roughness, .raw) {
            material.roughness = .init(texture: .init(roughness))
        } else {
            let roughness: Float = switch slot {
            case "hair": 0.6
            case "eyes": 0.2
            case "shoeAccent": 0.9
            default: 0.78
            }
            material.roughness = .init(floatLiteral: roughness)
        }
        return material
    }

    /// Poses the athlete for this frame. `origin` is the course point at the render origin.
    func apply(_ kinematics: MountainAthleteKinematics, origin: SIMD3<Double>) {
        let body = kinematics.bodyPose
        // Model space faces +Z; the course faces -Z at heading 0.
        let facing = simd_quatd(angle: body.heading + .pi, axis: SIMD3(0, 1, 0))
        let toModel = facing.inverse
        func toModelSpace(_ course: SIMD3<Double>) -> SIMD3<Double> {
            toModel.act(course - body.position)
        }

        let forward = SIMD3<Double>(0, 0, 1)
        func foot(_ ground: SIMD3<Double>) -> SIMD3<Double> {
            toModelSpace(ground) + SIMD3(0, poser.restFootHeight, 0) - forward * Self.footSetback
        }

        let targets = MountainAthletePoseTargets(
            pelvis: toModelSpace(kinematics.hipCentre),
            leftFoot: foot(kinematics.leftFoot),
            rightFoot: foot(kinematics.rightFoot),
            torsoLean: kinematics.torsoLean,
            leftArmSwing: kinematics.leftArmSwing,
            elbowBend: kinematics.elbowBend,
            twist: kinematics.twist
        )
        model.jointTransforms = poser.pose(targets).map { local in
            Transform(scale: .one, rotation: local.rotation, translation: local.translation)
        }
        root.position = SIMD3<Float>(body.position - origin)
        root.orientation = facing.float
    }
}
