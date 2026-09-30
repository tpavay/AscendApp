import Foundation
import simd

/// One file of the athlete pack: a skinned mesh, its skeleton and the textures it names, read from
/// a bundled `.json` and `.bin` pair. The pack (`scripts/athlete/build-ascend-athlete-pack.sh`,
/// Blender, from Quaternius's CC0 Universal Base Characters with the running kit modelled on the
/// body) holds one mesh per body and size, without hair, and one hair pack per body holding every
/// hairstyle as its own part; `MountainAthleteFigure` puts the two together for a look.
///
/// Model space is metres, +Y up, the athlete standing on y = 0 and facing +Z. Vertices are baked
/// in the rest pose, and every joint's inverse bind matrix is the inverse of its rest frame, so
/// posing a joint by its rest transform leaves the mesh exactly as authored.
struct MountainAthleteAsset: Sendable {
    struct Joint: Decodable, Sendable {
        let name: String
        let parent: Int
        let translation: [Double]
        let rotation: [Double]
        let scale: [Double]
        let inverseBind: [Double]

        var parentIndex: Int? { parent >= 0 ? parent : nil }
        var restTranslation: SIMD3<Double> { SIMD3(translation[0], translation[1], translation[2]) }
        var restRotation: simd_quatd { simd_quatd(ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3]) }
        var inverseBindMatrix: simd_float4x4 {
            let f = inverseBind.map(Float.init)
            return simd_float4x4(
                SIMD4(f[0], f[1], f[2], f[3]),
                SIMD4(f[4], f[5], f[6], f[7]),
                SIMD4(f[8], f[9], f[10], f[11]),
                SIMD4(f[12], f[13], f[14], f[15])
            )
        }
    }

    /// Which joints play which part in a stride, so the poser works on any humanoid skeleton.
    struct Roles: Decodable, Sendable {
        let body: String
        let spine: [String]
        let neck: String
        let head: String
        /// Left then right: hip, knee and ankle joints.
        let legs: [[String]]
        /// Left then right: shoulder, elbow and wrist joints.
        let arms: [[String]]
    }

    /// The image files a material slot is drawn with; a slot without one is a flat tinted colour.
    struct Textures: Decodable, Sendable {
        let baseColor: String?
        let normal: String?
        let roughness: String?
        /// The base colour's average, linear, for a texture drawn in a tint: hair is painted as
        /// grey strands, and the tint that lands a hair colour exactly is the colour over this.
        let shade: Double?
    }

    /// One primitive of the mesh and the colour slot it is tinted with.
    struct Part: Decodable, Sendable {
        let name: String
        let slot: String
        let vertexStart: Int
        let vertexCount: Int
        let indexStart: Int
        let indexCount: Int
    }

    private struct Header: Decodable {
        let format: String
        let height: Double
        let vertexCount: Int
        let indexCount: Int
        let roles: Roles
        let textures: [String: Textures]
        let skinTones: [String: String]
        let joints: [Joint]
        let parts: [Part]
    }

    enum LoadError: Error, Equatable {
        case missingResource
        case unsupportedFormat(String)
        case truncatedBuffer
    }

    static let format = "ascend-athlete-v3"
    static let floatsPerVertex = 16

    let joints: [Joint]
    let roles: Roles
    let textures: [String: Textures]
    /// The skin tones the pack baked a texture for, by the id the app stores, as `#RRGGBB`.
    let skinTones: [String: String]
    let parts: [Part]
    let height: Double
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    /// Four joint indices and weights per vertex.
    let jointIndices: [SIMD4<Int32>]
    let jointWeights: [SIMD4<Float>]
    let indices: [UInt32]

    init(header data: Data, buffer: Data) throws {
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.format == Self.format else { throw LoadError.unsupportedFormat(header.format) }
        let floatCount = header.vertexCount * Self.floatsPerVertex
        guard buffer.count >= floatCount * 4 + header.indexCount * 4 else { throw LoadError.truncatedBuffer }

        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = []
        var jointIndices: [SIMD4<Int32>] = [], jointWeights: [SIMD4<Float>] = []
        positions.reserveCapacity(header.vertexCount)
        normals.reserveCapacity(header.vertexCount)
        uvs.reserveCapacity(header.vertexCount)
        jointIndices.reserveCapacity(header.vertexCount)
        jointWeights.reserveCapacity(header.vertexCount)
        var indices: [UInt32] = []
        indices.reserveCapacity(header.indexCount)

        buffer.withUnsafeBytes { raw in
            func float(_ index: Int) -> Float { raw.loadUnaligned(fromByteOffset: index * 4, as: Float.self) }
            for vertex in 0..<header.vertexCount {
                let base = vertex * Self.floatsPerVertex
                positions.append(SIMD3(float(base), float(base + 1), float(base + 2)))
                normals.append(SIMD3(float(base + 3), float(base + 4), float(base + 5)))
                uvs.append(SIMD2(float(base + 6), float(base + 7)))
                jointIndices.append(SIMD4(Int32(float(base + 8)), Int32(float(base + 9)), Int32(float(base + 10)), Int32(float(base + 11))))
                jointWeights.append(SIMD4(float(base + 12), float(base + 13), float(base + 14), float(base + 15)))
            }
            for index in 0..<header.indexCount {
                indices.append(raw.loadUnaligned(fromByteOffset: (floatCount + index) * 4, as: UInt32.self))
            }
        }

        self.joints = header.joints
        self.roles = header.roles
        self.textures = header.textures
        self.skinTones = header.skinTones
        self.parts = header.parts
        self.height = header.height
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.jointIndices = jointIndices
        self.jointWeights = jointWeights
        self.indices = indices
    }

    /// The pack file holding one body at one size, without hair.
    static func figureResource(body: AthleteLook.Body, size: AthleteLook.Size) -> String {
        "ascend-athlete-\(body.packName)-\(size.rawValue)"
    }

    /// The pack file holding every hairstyle, fitted to one body.
    static func hairResource(body: AthleteLook.Body) -> String {
        "ascend-athlete-\(body.packName)-hair"
    }

    static func bundled(_ resource: String, in bundle: Bundle = .main) throws -> MountainAthleteAsset {
        guard let headerURL = bundle.url(forResource: resource, withExtension: "json"),
              let bufferURL = bundle.url(forResource: resource, withExtension: "bin") else {
            throw LoadError.missingResource
        }
        return try MountainAthleteAsset(header: Data(contentsOf: headerURL), buffer: Data(contentsOf: bufferURL))
    }
}

extension AthleteLook.Body {
    /// The pack's name for the body: Universal Base Characters' male and female superhero bodies.
    var packName: String {
        switch self {
        case .a: "male"
        case .b: "female"
        }
    }
}
