import Foundation
import RealityKit
import UIKit

/// Builds athletes for the stairs without ever stalling a frame.
///
/// An athlete needs a skinned mesh for its body, size and hairstyle, the textures its look is
/// drawn with, and a name tag. Each is tens of milliseconds to make, and a leaderboard refresh
/// can bring thirty climbers at once, so they are prepared in the background and kept: every
/// climber who shares a figure shares one mesh, every look shares its textures, and every name
/// its tag. A rig is only assembled once all of it is ready, which costs a frame almost nothing.
@MainActor
final class MountainRigFactory {
    static let shared = MountainRigFactory()

    /// What one rig is built from.
    struct Request: Hashable {
        let look: AthleteLook
        let style: MountainAthleteRig.Style
        let label: String
        /// Whether a glowing item lights its surroundings. Only the climber's own athlete
        /// does: a pack of thirty lanterns would be thirty lights, and a rival's carved face
        /// glows without one.
        var castsLight = false
    }

    /// A material depends only on its slot's textures and tint, so hundreds of looks share a
    /// few dozen of them.
    private struct MaterialKey: Hashable {
        let slot: String
        let textures: String
        let tint: MountainColor
        let ghostly: Bool
    }

    private struct TagKey: Hashable {
        let label: String
        let accent: MountainColor
    }

    /// Everything one rig is drawn with, ready to use.
    struct Parts {
        let figure: MountainAthleteFigure
        let mesh: MeshResource
        let materials: [any RealityKit.Material]
        let ghostly: Bool
        let tag: Tag?
        /// The unlocked items the athlete has on; a ghost wears nothing.
        let gear: [AthleteGear]
        let gearCastsLight: Bool
    }

    /// A name drawn once: its texture on a plane of the right shape.
    struct Tag {
        let mesh: MeshResource
        let material: UnlitMaterial
    }

    private let athletes: MountainAthleteLibrary
    private let gear: MountainGearLibrary
    private let bundle: Bundle
    private var meshes: [MountainAthleteFigure.Key: MeshResource] = [:]
    private var meshLoads: [MountainAthleteFigure.Key: Task<MeshResource, any Error>] = [:]
    private var textures: [String: TextureResource] = [:]
    private var textureLoads: [String: Task<TextureResource, any Error>] = [:]
    private var tags: [TagKey: Tag] = [:]
    private var tagLoads: Set<TagKey> = []
    private var materials: [MaterialKey: any RealityKit.Material] = [:]
    /// Resources that failed to load: drawn without rather than asked for every frame.
    private var failed: Set<String> = []

    init(athletes: MountainAthleteLibrary = .shared, gear: MountainGearLibrary = .shared, bundle: Bundle = .main) {
        self.athletes = athletes
        self.gear = gear
        self.bundle = bundle
    }

    /// The rig for `request` if everything it needs is ready; otherwise nil, and whatever is
    /// missing starts loading so a later frame can build it.
    func readyRig(_ request: Request) -> MountainAthleteRig? {
        readyParts(request).flatMap { try? MountainAthleteRig(parts: $0, gearLibrary: gear) }
    }

    /// The parts for `request` if all of them are ready; otherwise nil, and whatever is missing
    /// starts loading. Dressing an existing rig in them costs nothing a frame would notice.
    func readyParts(_ request: Request) -> Parts? {
        guard let figure = athletes.readyFigure(for: request.look) else { return nil }
        guard let mesh = meshes[figure.key] else {
            startMesh(for: figure)
            return nil
        }
        let names = textureNames(for: figure, request: request)
        let missing = names.filter { textures[$0.name] == nil && !failed.contains($0.name) }
        guard missing.isEmpty else {
            for texture in missing { startTexture(texture.name, semantic: texture.semantic) }
            return nil
        }
        let tagKey = TagKey(label: request.label, accent: MountainAthleteRig.tagAccent(for: request.style))
        guard request.label.isEmpty || tags[tagKey] != nil else {
            startTag(tagKey)
            return nil
        }
        return parts(figure: figure, mesh: mesh, request: request)
    }

    /// The rig for `request`, waiting for whatever it needs: for the climber's own athlete and
    /// the editor, which show nothing until it stands.
    func rig(_ request: Request) async throws -> MountainAthleteRig {
        let figure = try await athletes.figure(for: request.look)
        let mesh = try await mesh(for: figure)
        for texture in textureNames(for: figure, request: request) where textures[texture.name] == nil && !failed.contains(texture.name) {
            _ = try? await load(texture.name, semantic: texture.semantic)
        }
        if !request.label.isEmpty {
            await makeTag(TagKey(label: request.label, accent: MountainAthleteRig.tagAccent(for: request.style)))
        }
        let parts = parts(figure: figure, mesh: mesh, request: request)
        // A standing athlete is posed once, so what it wears has to be made before it stands.
        for item in parts.gear {
            _ = await gear.prepare(item)
        }
        return try MountainAthleteRig(parts: parts, gearLibrary: gear)
    }

    // MARK: - Assembly

    private func parts(figure: MountainAthleteFigure, mesh: MeshResource, request: Request) -> Parts {
        let ghostly = if case .ghost = request.style { true } else { false }
        return Parts(
            figure: figure,
            mesh: mesh,
            materials: materials(for: figure, style: request.style),
            ghostly: ghostly,
            tag: tags[TagKey(label: request.label, accent: MountainAthleteRig.tagAccent(for: request.style))],
            gear: ghostly ? [] : UnlockStore.shared.drawnGear(for: request.look),
            gearCastsLight: request.castsLight
        )
    }

    /// Each slot's material is made once and shared by every climber whose look paints that slot
    /// the same way.
    private func materials(for figure: MountainAthleteFigure, style: MountainAthleteRig.Style) -> [any RealityKit.Material] {
        figure.slots.map { slot in
            let key: MaterialKey
            switch style {
            case .athlete(let look):
                let set = figure.textures(forSlot: MountainAthleteRig.texturesKey(forSlot: slot, look: look))
                let textures = [set?.baseColor, set?.normal, set?.roughness].map { $0 ?? "-" }.joined(separator: "|")
                key = MaterialKey(slot: slot, textures: textures, tint: MountainAthleteRig.tint(forSlot: slot, look: look, textures: set), ghostly: false)
            case .ghost(let color):
                key = MaterialKey(slot: "", textures: "", tint: color, ghostly: true)
            }
            if let made = materials[key] { return made }
            let made: any RealityKit.Material = switch style {
            case .athlete(let look): material(for: slot, look: look, figure: figure)
            case .ghost(let color): MountainAthleteRig.ghostMaterial(color)
            }
            materials[key] = made
            return made
        }
    }

    private func material(for slot: String, look: AthleteLook, figure: MountainAthleteFigure) -> PhysicallyBasedMaterial {
        let textureSet = figure.textures(forSlot: MountainAthleteRig.texturesKey(forSlot: slot, look: look))
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: 0)
        let tint = MountainAthleteRig.tint(forSlot: slot, look: look, textures: textureSet).uiColor
        if let base = textureSet?.baseColor.flatMap({ textures[$0] }) {
            material.baseColor = .init(tint: tint, texture: .init(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let normal = textureSet?.normal.flatMap({ textures[$0] }) {
            material.normal = .init(texture: .init(normal))
        }
        if let roughness = textureSet?.roughness.flatMap({ textures[$0] }) {
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

    /// Every name is drawn once, off the main actor, with the plane it is shown on.
    private func startTag(_ key: TagKey) {
        guard !tagLoads.contains(key) else { return }
        Task { await makeTag(key) }
    }

    private func makeTag(_ key: TagKey) async {
        guard tags[key] == nil, !tagLoads.contains(key) else { return }
        tagLoads.insert(key)
        defer { tagLoads.remove(key) }
        let image = await Task.detached(priority: .userInitiated) {
            MountainAthleteRig.tagImage(key.label, accent: key.accent)
        }.value
        guard let image,
              let texture = try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let height: Float = 0.2
        let aspect = Float(texture.width) / Float(max(texture.height, 1))
        tags[key] = Tag(mesh: .generatePlane(width: height * aspect, height: height), material: material)
    }

    // MARK: - Loading

    private func textureNames(for figure: MountainAthleteFigure, request: Request) -> [(name: String, semantic: TextureResource.Semantic)] {
        guard case .athlete(let look) = request.style else { return [] }
        return figure.slots.flatMap { slot -> [(name: String, semantic: TextureResource.Semantic)] in
            guard let set = figure.textures(forSlot: MountainAthleteRig.texturesKey(forSlot: slot, look: look)) else { return [] }
            return [(set.baseColor, TextureResource.Semantic.color), (set.normal, .normal), (set.roughness, .raw)]
                .compactMap { name, semantic in name.map { ($0, semantic) } }
        }
    }

    private func startMesh(for figure: MountainAthleteFigure) {
        guard meshLoads[figure.key] == nil else { return }
        Task { _ = try? await mesh(for: figure) }
    }

    private func mesh(for figure: MountainAthleteFigure) async throws -> MeshResource {
        if let mesh = meshes[figure.key] { return mesh }
        if let loading = meshLoads[figure.key] { return try await loading.value }
        let load = Task.detached(priority: .userInitiated) { try await MountainAthleteRig.makeMesh(for: figure) }
        meshLoads[figure.key] = load
        defer { meshLoads[figure.key] = nil }
        let mesh = try await load.value
        meshes[figure.key] = mesh
        return mesh
    }

    private func startTexture(_ name: String, semantic: TextureResource.Semantic) {
        guard textureLoads[name] == nil else { return }
        Task { _ = try? await load(name, semantic: semantic) }
    }

    private func load(_ name: String, semantic: TextureResource.Semantic) async throws -> TextureResource {
        if let texture = textures[name] { return texture }
        if let loading = textureLoads[name] { return try await loading.value }
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            failed.insert(name)
            throw MountainAthleteAsset.LoadError.missingResource
        }
        let load = Task { try await TextureResource(contentsOf: url, options: .init(semantic: semantic)) }
        textureLoads[name] = load
        defer { textureLoads[name] = nil }
        do {
            let texture = try await load.value
            textures[name] = texture
            return texture
        } catch {
            failed.insert(name)
            throw error
        }
    }
}
