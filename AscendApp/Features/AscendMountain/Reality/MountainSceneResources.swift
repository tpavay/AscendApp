import RealityKit

/// The stair meshes every Ascend Mountain scene draws with, one per course-piece kind, built once
/// per scene. Chunk slots reference these rather than owning copies (spec 24).
@MainActor
struct MountainSceneResources {
    let chunkMeshes: [MountainChunkKind: MeshResource]

    static func make() throws -> MountainSceneResources {
        var meshes: [MountainChunkKind: MeshResource] = [:]
        for kind in MountainChunkKind.allCases {
            meshes[kind] = try chunkMesh(for: kind)
        }
        return MountainSceneResources(chunkMeshes: meshes)
    }

    private static func chunkMesh(for kind: MountainChunkKind) throws -> MeshResource {
        let geometry = MountainChunkGeometry(kind: kind)
        var descriptor = MeshDescriptor(name: "mountain-chunk-\(kind.rawValue)")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(geometry.uvs)
        descriptor.primitives = .triangles(geometry.indices)
        descriptor.materials = .perFace(geometry.triangleSurfaces)
        return try MeshResource.generate(from: [descriptor])
    }
}
