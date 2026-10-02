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
    enum Style: Hashable {
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

    /// The item the athlete carries, and the one it was asked to carry: they differ for the
    /// frames it takes the item to be made.
    private let carriedRoot = Entity()
    private var carried: (gear: AthleteGear, entity: ModelEntity, hold: MountainCarryHold)?
    private var wanted: AthleteGear?
    private var castsLight = false
    private let carryJoints: CarryJoints?
    private let gearLibrary: MountainGearLibrary

    /// A rig from parts `MountainRigFactory` has already prepared, so building one costs a frame
    /// almost nothing: the mesh is shared by every climber of that figure, and every material and
    /// tag is already made.
    init(parts: MountainRigFactory.Parts, gearLibrary: MountainGearLibrary = .shared) throws {
        guard let poser = MountainAthletePoser(asset: parts.figure.body) else {
            throw MountainAthleteAsset.LoadError.unsupportedFormat("rig is missing a joint the poser needs")
        }
        self.poser = poser
        figureKey = parts.figure.key
        height = Float(parts.figure.body.height)
        model = ModelEntity(mesh: parts.mesh, materials: parts.materials)
        root.addChild(model)
        root.addChild(carriedRoot)
        carryJoints = CarryJoints(body: parts.figure.body)
        self.gearLibrary = gearLibrary
        dress(parts)
    }

    /// The joints a carried item rests on: the chest it turns with, and the right shoulder.
    private struct CarryJoints {
        let chest: Int
        let rightShoulder: Int

        init?(body: MountainAthleteAsset) {
            let names = body.joints.map(\.name)
            guard let chestName = body.roles.spine.last, let chest = names.firstIndex(of: chestName),
                  body.roles.arms.count == 2, let shoulderName = body.roles.arms[1].first,
                  let rightShoulder = names.firstIndex(of: shoulderName) else { return nil }
            self.chest = chest
            self.rightShoulder = rightShoulder
        }

        var all: [Int] { [chest, rightShoulder] }
    }

    /// Has the athlete carry `gear`, or nothing. The item appears the first frame it is made.
    func carry(_ gear: AthleteGear?) {
        wanted = gear
        refreshCarried()
    }

    private func refreshCarried() {
        guard carried?.gear != wanted else { return }
        guard let wanted else {
            carried?.entity.removeFromParent()
            carried = nil
            return
        }
        guard let prepared = gearLibrary.ready(wanted) else { return }
        carried?.entity.removeFromParent()
        let entity = ModelEntity(mesh: prepared.mesh, materials: prepared.materials)
        if castsLight, let glow = prepared.glow {
            // A candle inside: it lights the climber's head and shoulder and the stairs round
            // them, and reaches no further, so a pack of lanterns costs a few lit pixels each.
            let candle = PointLight()
            candle.light.color = glow.uiColor
            candle.light.intensity = 6_000
            candle.light.attenuationRadius = 1.4
            candle.position = [0, Float(prepared.height * 0.45), 0]
            entity.addChild(candle)
        }
        carriedRoot.addChild(entity)
        carried = (wanted, entity, MountainCarryHold(carry: wanted.carry, height: prepared.height, halfWidth: prepared.halfWidth))
    }

    /// Dresses a rig of the same figure as another climber: their materials, their see-through or
    /// not, their name. Reusing a rig spares the renderer a new skinned model.
    func redress(_ parts: MountainRigFactory.Parts) {
        guard parts.figure.key == figureKey else { return }
        model.model?.materials = parts.materials
        dress(parts)
    }

    private func dress(_ parts: MountainRigFactory.Parts) {
        if castsLight != parts.carryCastsLight {
            // The item is rebuilt with or without its candle.
            castsLight = parts.carryCastsLight
            carried?.entity.removeFromParent()
            carried = nil
        }
        carry(parts.carry)
        baseOpacity = parts.ghostly ? Self.ghostOpacity : 1
        visibility = 1
        applyOpacity()
        tag?.removeFromParent()
        tag = nil
        if let parts = parts.tag {
            let plane = ModelEntity(mesh: parts.mesh, materials: [parts.material])
            let tag = Entity()
            tag.addChild(plane)
            tag.components.set(BillboardComponent())
            tag.position = [0, height + 0.2, 0]
            root.addChild(tag)
            self.tag = tag
        }
    }

    private let height: Float

    /// How see-through a ghost is: never mistaken for a real climber on the stairs.
    static let ghostOpacity: Float = 0.5
    private var baseOpacity: Float = 1
    private var visibility: Float = 1

    /// How much of the athlete shows, from none to all: a climber fading in as they join the
    /// stairs, fading out as they leave, or thinned where they would stand in front of you.
    func show(visibility amount: Float) {
        let clamped = min(max(amount, 0), 1)
        guard clamped != visibility else { return }
        visibility = clamped
        applyOpacity()
    }

    private func applyOpacity() {
        let opacity = baseOpacity * visibility
        if opacity >= 0.999 {
            // Opaque drawing is cheaper than blending, and sorts correctly.
            model.components.remove(OpacityComponent.self)
            carriedRoot.components.remove(OpacityComponent.self)
        } else {
            model.components.set(OpacityComponent(opacity: opacity))
            carriedRoot.components.set(OpacityComponent(opacity: opacity))
        }
    }

    /// The skinned mesh for `figure`, built off the main actor: generating a mesh of twelve
    /// thousand skinned vertices is tens of milliseconds, more than a frame.
    nonisolated static func makeMesh(for figure: MountainAthleteFigure) async throws -> MeshResource {
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
        return try await MeshResource(from: contents)
    }

    static func ghostMaterial(_ color: MountainColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.uiColor)
        material.emissiveColor = .init(color: color.uiColor)
        material.emissiveIntensity = 0.9
        material.roughness = .init(floatLiteral: 0.35)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    /// The accent a style's tag carries: the ghost's own colour, or the climber's lime.
    static func tagAccent(for style: Style) -> MountainColor {
        switch style {
        case .ghost(let color): color
        case .athlete: MountainColor(red: 0.53, green: 0.83, blue: 0.04)
        }
    }

    /// The words over an athlete's head, drawn once into an image. Pure Core Graphics and Core
    /// Text, so it can be drawn off the main actor: a name is drawn the first time its climber
    /// joins the pack, and hundreds of names pass through a crowded climb.
    nonisolated static func tagImage(_ text: String, accent: MountainColor, scale: CGFloat = 2) -> CGImage? {
        let font = CTFontCreateWithName("Montserrat-Bold" as CFString, 64 * scale, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            NSAttributedString.Key(kCTKernAttributeName as String): 3 * scale
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let width = Int(ceil(textWidth + 88 * scale)), height = Int(112 * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: 56 * scale, cornerHeight: 56 * scale, transform: nil))
        context.setFillColor(CGColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 0.82))
        context.fillPath()
        context.setFillColor(CGColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 1))
        context.fillEllipse(in: CGRect(x: 30 * scale, y: 44 * scale, width: 24 * scale, height: 24 * scale))
        context.textPosition = CGPoint(x: 66 * scale, y: (CGFloat(height) - (ascent + descent)) / 2 + descent)
        CTLineDraw(line, context)
        return context.makeImage()
    }

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
        pose(targets)
    }

    private func pose(_ targets: MountainAthletePoseTargets) {
        refreshCarried()
        var targets = targets
        targets.carry = carried?.hold
        let local = poser.pose(targets)
        model.jointTransforms = local.map { local in
            Transform(scale: .one, rotation: local.rotation, translation: local.translation)
        }
        if let carried { place(carried.entity, hold: carried.hold, pose: local) }
    }

    /// Rests the carried item where this frame's pose holds it: on the right shoulder, or on both
    /// hands overhead. It turns with the chest, not the hand, so it does not spin as the arm moves.
    private func place(_ entity: ModelEntity, hold: MountainCarryHold, pose local: [MountainAthletePoser.LocalTransform]) {
        guard let joints = carryJoints else { return }
        let frames = poser.frames(of: local, joints: joints.all)
        let chest = frames[0], rightShoulder = frames[1]
        let seat = hold.seat(chest: chest.position, chestTurn: chest.turn, rightShoulder: rightShoulder.position)
        entity.transform = Transform(scale: .one, rotation: chest.turn.float, translation: SIMD3<Float>(seat))
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
        pose(targets)
        root.position = SIMD3<Float>(body.position - origin)
        root.orientation = facing.float
    }
}
