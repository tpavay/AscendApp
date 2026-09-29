import Foundation
import RealityKit
import UIKit
import simd

/// The athlete: the CC0 skinned character, posed every frame by `MountainAthletePoser` from
/// `MountainAthleteKinematics`. Feet are planted by IK on the treads the course says, so the
/// climb animation is the steps themselves rather than a clip played over them.
@MainActor
final class MountainAthleteRig {
    /// How an athlete is drawn: as themselves, or as a ghost - one glowing colour, see-through,
    /// so it never reads as a real climber on the stairs.
    enum Style: Equatable {
        case athlete(AthleteLook)
        case ghost(MountainColor)
    }

    let root = Entity()
    let figureKey: MountainAthleteFigure.Key
    private let model: ModelEntity
    private let poser: MountainAthletePoser
    private var groundRing: ModelEntity?
    private var tag: Entity?

    /// How far the foot joint sits behind the middle of the foot, so the sole lands centred on
    /// the tread.
    private static let footSetback = 0.05

    init(figure: MountainAthleteFigure, style: Style, label: String? = nil, bundle: Bundle = .main) throws {
        guard let poser = MountainAthletePoser(asset: figure.body) else {
            throw MountainAthleteAsset.LoadError.unsupportedFormat("rig is missing a joint the poser needs")
        }
        self.poser = poser
        figureKey = figure.key

        let slots = figure.slots
        let materials: [any RealityKit.Material] = slots.map { slot in
            switch style {
            case .athlete(let look):
                Self.material(for: slot, look: look, figure: figure, bundle: bundle)
            case .ghost(let color):
                Self.ghostMaterial(color)
            }
        }
        model = ModelEntity(mesh: try Self.mesh(for: figure), materials: materials)
        root.addChild(model)
        if case .ghost = style {
            model.components.set(OpacityComponent(opacity: 0.5))
        }
        if let label, !label.isEmpty, let tag = Self.tag(label, style: style) {
            tag.position = [0, Float(figure.body.height) + 0.2, 0]
            root.addChild(tag)
            self.tag = tag
        }
    }

    /// Every climber who shares a body, size and hairstyle draws the same mesh; only their
    /// materials and their pose are their own.
    private static var meshCache: [MountainAthleteFigure.Key: MeshResource] = [:]

    private static func mesh(for figure: MountainAthleteFigure) throws -> MeshResource {
        if let cached = meshCache[figure.key] { return cached }
        let body = figure.body
        var contents = MeshResource.Contents()
        guard let skeleton = MeshResource.Skeleton(
            id: "athlete",
            jointNames: body.joints.map(\.name),
            inverseBindPoseMatrices: body.joints.map(\.inverseBindMatrix),
            restPoseTransforms: body.joints.map { joint in
                Transform(
                    scale: .one,
                    rotation: joint.restRotation.float,
                    translation: SIMD3<Float>(joint.restTranslation)
                )
            },
            parentIndices: body.joints.map(\.parentIndex)
        ) else {
            throw MountainAthleteAsset.LoadError.unsupportedFormat("skeleton rejected")
        }
        contents.skeletons = MeshSkeletonCollection([skeleton])

        let slots = figure.slots
        var parts: [MeshResource.Part] = []
        for (index, piece) in figure.pieces.enumerated() {
            let asset = piece.asset, part = piece.part
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
        let mesh = try MeshResource.generate(from: contents)
        meshCache[figure.key] = mesh
        return mesh
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

    /// Every athlete on the stairs shares one copy of each texture, so a start line full of
    /// climbers costs no more texture memory than the looks they wear.
    private static var textureCache: [String: TextureResource] = [:]

    /// The pack's key for the textures a slot is drawn with under `look`: the skin is baked once
    /// per tone and muscle level.
    nonisolated static func texturesKey(forSlot slot: String, look: AthleteLook) -> String {
        slot == "skin" ? "skin.\(look.skinTone.rawValue).\(look.muscle.rawValue)" : slot
    }

    /// The colour a slot is tinted with. Skin and eyes carry their colour in the texture; hair is
    /// painted grey, and the tint that lands the hair colour exactly is that colour over the
    /// paint's average, in linear light; the kit is flat colour.
    nonisolated static func tint(forSlot slot: String, look: AthleteLook, textures: MountainAthleteAsset.Textures?) -> MountainColor {
        switch slot {
        case "skin", "eyes":
            return MountainColor(red: 1, green: 1, blue: 1)
        case "hair", "hair2":
            let color = look.hairColor.color
            guard let shade = textures?.shade, shade > 0 else { return color }
            return color.linearScaled(by: 1 / shade)
        case "top": return look.top.color
        case "bottom": return look.bottom.color
        case "shoe": return look.shoes.color
        case "shoeAccent": return MountainColor(red: 0.13, green: 0.14, blue: 0.16)
        default: return MountainColor(red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    private static func material(for slot: String, look: AthleteLook, figure: MountainAthleteFigure, bundle: Bundle) -> PhysicallyBasedMaterial {
        func texture(_ name: String?, _ semantic: TextureResource.Semantic) -> TextureResource? {
            guard let name else { return nil }
            if let cached = textureCache[name] { return cached }
            guard let url = bundle.url(forResource: name, withExtension: nil),
                  let loaded = try? TextureResource.load(contentsOf: url, options: .init(semantic: semantic)) else { return nil }
            textureCache[name] = loaded
            return loaded
        }
        let textures = figure.textures(forSlot: texturesKey(forSlot: slot, look: look))
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: 0)
        let tint = tint(forSlot: slot, look: look, textures: textures).uiColor
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
            case "hair", "hair2": 0.6
            case "eyes": 0.2
            case "shoeAccent": 0.9
            default: 0.78
            }
            material.roughness = .init(floatLiteral: roughness)
        }
        return material
    }

    /// How much of the tag shows, from none to all.
    func showTag(opacity: Float) {
        guard let tag else { return }
        tag.isEnabled = opacity > 0.01
        tag.components.set(OpacityComponent(opacity: opacity))
    }

    /// The lime ring under the climber's feet that marks them out when others share the stairs
    /// (captain, 2026-09-29), hidden when they climb alone.
    func showGroundRing(_ visible: Bool) {
        if groundRing == nil, visible, let ring = Self.makeGroundRing() {
            root.addChild(ring)
            groundRing = ring
        }
        groundRing?.isEnabled = visible
    }

    private static func makeGroundRing() -> ModelEntity? {
        var descriptor = MeshDescriptor(name: "athlete-ring")
        let segments = 48, inner: Float = 0.34, outer: Float = 0.44
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            positions.append(SIMD3(cos(a) * inner, 0, sin(a) * inner))
            positions.append(SIMD3(cos(a) * outer, 0, sin(a) * outer))
            let j = UInt32(i * 2), k = UInt32(((i + 1) % segments) * 2)
            indices.append(contentsOf: [j, k, j + 1, j + 1, k, k + 1])
        }
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count))
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        var material = UnlitMaterial(color: UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let ring = ModelEntity(mesh: mesh, materials: [material])
        ring.position = [0, 0.03, 0]
        return ring
    }

    /// Stands the athlete at ease on flat ground at the origin, facing +Z: how the editor and
    /// onboarding show them.
    func stand() {
        let footHeight = poser.restFootHeight
        let targets = MountainAthletePoseTargets(
            pelvis: SIMD3(0, footHeight + poser.restPelvisHeight - 0.015, 0),
            leftFoot: SIMD3(0.1, footHeight, -Self.footSetback),
            rightFoot: SIMD3(-0.1, footHeight, -Self.footSetback),
            torsoLean: 0.03,
            leftArmSwing: 0,
            elbowBend: 0.22,
            twist: 0
        )
        model.jointTransforms = poser.pose(targets).map { local in
            Transform(scale: .one, rotation: local.rotation, translation: local.translation)
        }
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
