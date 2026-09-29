import Foundation

/// A look's body put together from the athlete pack: the mesh for its body and size, and its
/// hairstyle taken from that body's hair pack. The two share the body's skeleton, so the hair
/// rides the head joint every other part is posed with.
struct MountainAthleteFigure: Sendable {
    /// What decides the geometry; everything else about a look is a material.
    struct Key: Hashable, Sendable {
        let body: AthleteLook.Body
        let size: AthleteLook.Size
        let hairStyle: AthleteLook.HairStyle

        init(_ look: AthleteLook) {
            body = look.body
            size = look.size
            hairStyle = look.hairStyle
        }
    }

    /// One drawn part and the asset holding its vertices.
    struct Piece: Sendable {
        let asset: MountainAthleteAsset
        let part: MountainAthleteAsset.Part
    }

    enum AssemblyError: Error, Equatable {
        case hairStyleMissing(String)
        case skeletonsDiffer
    }

    let key: Key
    /// The body's mesh, whose skeleton, joint roles and height the figure uses.
    let body: MountainAthleteAsset
    let pieces: [Piece]

    init(key: Key, body: MountainAthleteAsset, hair: MountainAthleteAsset) throws {
        let partName = "hair.\(key.hairStyle.rawValue)"
        guard let hairPart = hair.parts.first(where: { $0.name == partName }) else {
            throw AssemblyError.hairStyleMissing(partName)
        }
        guard hair.joints.map(\.name) == body.joints.map(\.name) else {
            throw AssemblyError.skeletonsDiffer
        }
        self.key = key
        self.body = body
        self.pieces = body.parts.map { Piece(asset: body, part: $0) } + [Piece(asset: hair, part: hairPart)]
        self.hairTextures = hair.textures
    }

    private let hairTextures: [String: MountainAthleteAsset.Textures]

    /// The textures a material slot is drawn with, whichever file of the pack names them.
    func textures(forSlot slot: String) -> MountainAthleteAsset.Textures? {
        body.textures[slot] ?? hairTextures[slot]
    }

    /// The material slots the pieces are drawn in, in the order a mesh's material indices use.
    var slots: [String] {
        Array(Set(pieces.map(\.part.slot))).sorted()
    }
}

/// Loads the athlete pack's files on demand and keeps them, so every climber on the stairs who
/// shares a body and size shares one copy. Loading reads and unpacks a megabyte or so, off the
/// main actor; a caller drawing frames asks for a figure without waiting and gets it once ready.
@MainActor
final class MountainAthleteLibrary {
    static let shared = MountainAthleteLibrary()

    private let bundle: Bundle
    private var assets: [String: MountainAthleteAsset] = [:]
    private var loads: [String: Task<MountainAthleteAsset, any Error>] = [:]
    private var failed: Set<String> = []
    /// Figures already put together, asked for every frame by every climber waiting to be drawn.
    private var figures: [MountainAthleteFigure.Key: MountainAthleteFigure] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// The figure for `look`, loading whatever part of the pack it needs.
    func figure(for look: AthleteLook) async throws -> MountainAthleteFigure {
        let key = MountainAthleteFigure.Key(look)
        async let body = asset(MountainAthleteAsset.figureResource(body: key.body, size: key.size))
        async let hair = asset(MountainAthleteAsset.hairResource(body: key.body))
        return try await MountainAthleteFigure(key: key, body: body, hair: hair)
    }

    /// The figure for `look` if its files are already loaded; otherwise nil, and they start
    /// loading so a later frame finds them.
    func readyFigure(for look: AthleteLook) -> MountainAthleteFigure? {
        let key = MountainAthleteFigure.Key(look)
        if let figure = figures[key] { return figure }
        let bodyName = MountainAthleteAsset.figureResource(body: key.body, size: key.size)
        let hairName = MountainAthleteAsset.hairResource(body: key.body)
        guard let body = assets[bodyName], let hair = assets[hairName] else {
            for name in [bodyName, hairName] where assets[name] == nil && loads[name] == nil && !failed.contains(name) {
                Task { _ = try? await asset(name) }
            }
            return nil
        }
        let figure = try? MountainAthleteFigure(key: key, body: body, hair: hair)
        figures[key] = figure
        return figure
    }

    private func asset(_ name: String) async throws -> MountainAthleteAsset {
        if let loaded = assets[name] { return loaded }
        if let loading = loads[name] { return try await loading.value }
        let bundle = bundle
        let load = Task.detached(priority: .userInitiated) { try MountainAthleteAsset.bundled(name, in: bundle) }
        loads[name] = load
        defer { loads[name] = nil }
        do {
            let loaded = try await load.value
            assets[name] = loaded
            return loaded
        } catch {
            failed.insert(name)
            throw error
        }
    }
}
