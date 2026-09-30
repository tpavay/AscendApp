import Foundation
import simd

/// Flat-shaded source geometry for the reusable props, as plain triangles so a course piece can
/// bake many of them into its one mesh. The shapes are content, built in Blender by
/// `scripts/mountain-art/build-mountain-props.py` and bundled as `ascend-mountain-props`, so a
/// better tree is a new asset, never a code change.
struct MountainPropTemplate: Sendable {
    struct Triangle: Sendable {
        let corners: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        /// Which of the prop's materials the triangle takes (a pine's foliage or its trunk).
        let part: Int
    }

    let triangles: [Triangle]

    /// A pine about 3.6 m tall at scale 1: part 0 foliage, part 1 trunk.
    static let pine = bundled["pine"] ?? MountainPropTemplate(triangles: [])
    /// A boulder about a metre across at scale 1, sunk a fifth into the ground.
    static let boulder = bundled["boulder"] ?? MountainPropTemplate(triangles: [])

    static let resourceName = "ascend-mountain-props"
    private static let floatsPerTriangle = 10

    static let bundled: [String: MountainPropTemplate] = (try? load(from: .main)) ?? [:]

    static func load(from bundle: Bundle) throws -> [String: MountainPropTemplate] {
        struct Header: Decodable {
            struct Prop: Decodable {
                let name: String
                let firstTriangle: Int
                let triangleCount: Int
            }
            let format: String
            let props: [Prop]
        }
        guard let headerURL = bundle.url(forResource: resourceName, withExtension: "json"),
              let bufferURL = bundle.url(forResource: resourceName, withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: headerURL))
        guard header.format == "ascend-props-v1" else { throw CocoaError(.fileReadCorruptFile) }
        let buffer = try Data(contentsOf: bufferURL)
        return try buffer.withUnsafeBytes { raw in
            func float(_ index: Int) -> Float { raw.loadUnaligned(fromByteOffset: index * 4, as: Float.self) }
            var templates: [String: MountainPropTemplate] = [:]
            for prop in header.props {
                guard (prop.firstTriangle + prop.triangleCount) * floatsPerTriangle * 4 <= raw.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                templates[prop.name] = MountainPropTemplate(triangles: (0..<prop.triangleCount).map { t in
                    let base = (prop.firstTriangle + t) * floatsPerTriangle
                    func point(_ offset: Int) -> SIMD3<Float> { SIMD3(float(base + offset), float(base + offset + 1), float(base + offset + 2)) }
                    return Triangle(corners: (point(0), point(3), point(6)), part: Int(float(base + 9)))
                })
            }
            return templates
        }
    }
}
