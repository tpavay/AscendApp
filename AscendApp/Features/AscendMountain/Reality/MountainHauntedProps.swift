import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// What stands on the haunted stretch (`MountainHauntedStretch`): jack-o'-lanterns at the stair's
/// edge, ghosts drifting over the mountainside beside them, and the gates' webs, spiders and
/// coloured light. Every prop reuses a shared mesh, and only the gates carry lights - two each,
/// with at most two gates in view - so the stretch costs about what the plain stairs do.
@MainActor
enum MountainHauntedProps {
    /// How far out from the stair's centre line a lantern stands: on the kerb.
    static var kerbSide: Float {
        Float(MountainStairGeometry.width / 2 + MountainChunkGeometry.kerbWidth / 2)
    }

    /// A lit jack-o'-lantern sitting on the kerb, alternating sides every lantern; one in six
    /// has a ghost hanging in the air beyond it.
    static func lantern(for marker: MountainMarker, gear: MountainGearLibrary = .shared) -> Entity {
        let post = Entity()
        let index = marker.step / MountainHauntedStretch.lanternEvery
        let side: Float = index.isMultiple(of: 2) ? 1 : -1
        if let prepared = gear.ready(.pumpkinLantern) {
            let pumpkin = ModelEntity(mesh: prepared.mesh, materials: prepared.materials)
            pumpkin.scale = SIMD3(repeating: 2)
            pumpkin.position = [side * kerbSide, Float(MountainChunkGeometry.kerbHeight), 0]
            // Faces the climber coming up the stairs, turned a little in toward them.
            pumpkin.orientation = simd_quatf(angle: 2.75 + side * 0.5, axis: [0, 1, 0])
            post.addChild(pumpkin)
        }
        if index % 6 == 3, let sheet = gear.ready(.ghostSheet) {
            let ghost = ModelEntity(mesh: sheet.mesh, materials: sheet.materials)
            ghost.scale = SIMD3(repeating: 1.15)
            ghost.position = [side * (kerbSide + 2.4), 2.3, -0.8]
            ghost.orientation = simd_quatf(angle: -side * 0.7, axis: [0, 1, 0])
            ghost.components.set(OpacityComponent(opacity: 0.72))
            post.addChild(ghost)
        }
        return post
    }

    /// Dresses a gate inside the stretch: a lantern on each pillar cap, one lit orange and one
    /// purple, webs strung in the corners under the lintel, and spiders hanging on threads.
    static func haunt(_ gate: Entity, span: Float, pillarTop: Float, lintelBottom: Float, depth: Float, gear: MountainGearLibrary = .shared) {
        for side: Float in [-1, 1] {
            if let prepared = gear.ready(.pumpkinLantern) {
                let pumpkin = ModelEntity(mesh: prepared.mesh, materials: prepared.materials)
                pumpkin.scale = SIMD3(repeating: 2.1)
                pumpkin.position = [side * span, pillarTop + 0.14, 0]
                pumpkin.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                gate.addChild(pumpkin)
            }
            let light = PointLight()
            light.light.color = side < 0
                ? UIColor(red: 1, green: 0.55, blue: 0.12, alpha: 1)
                : UIColor(red: 0.62, green: 0.3, blue: 1, alpha: 1)
            light.light.intensity = 30_000
            light.light.attenuationRadius = 7
            light.position = [side * span, pillarTop + 0.6, 0.8]
            gate.addChild(light)

            if let web = web {
                let corner = ModelEntity(mesh: .generatePlane(width: 0.7, height: 0.7), materials: [web])
                corner.position = [side * (span - 0.58), lintelBottom - 0.35, depth / 2 + 0.02]
                corner.orientation = simd_quatf(angle: side < 0 ? 0 : .pi / 2, axis: [0, 0, 1])
                gate.addChild(corner)
            }
        }
        for (offset, drop) in [(Float(-0.55), Float(0.9)), (0.35, 1.3), (0.9, 0.7)] {
            gate.addChild(spider(hangingFrom: [offset, lintelBottom, depth / 2 - 0.05], drop: drop))
        }
    }

    /// A black spider at the end of its thread.
    private static func spider(hangingFrom anchor: SIMD3<Float>, drop: Float) -> Entity {
        let spider = Entity()
        var black = PhysicallyBasedMaterial()
        black.baseColor = .init(tint: UIColor(red: 0.04, green: 0.03, blue: 0.05, alpha: 1))
        black.roughness = .init(floatLiteral: 0.35)
        var silk = UnlitMaterial(color: UIColor(white: 0.85, alpha: 1))
        silk.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let thread = ModelEntity(mesh: .generateBox(size: [0.006, drop, 0.006]), materials: [silk])
        thread.position = anchor - [0, drop / 2, 0]
        spider.addChild(thread)
        let body = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [black])
        body.position = anchor - [0, drop + 0.07, 0]
        spider.addChild(body)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [black])
        head.position = anchor - [0, drop - 0.005, 0]
        spider.addChild(head)
        for (index, side) in [Float(-1), -1, -1, -1, 1, 1, 1, 1].enumerated() {
            let leg = ModelEntity(mesh: .generateBox(size: [0.16, 0.012, 0.012]), materials: [black])
            let tilt = Float(index % 4) * 0.35 - 0.5
            leg.position = anchor - [-side * 0.09, drop + 0.06 - tilt * 0.06, 0]
            leg.orientation = simd_quatf(angle: side * (0.5 + tilt * 0.4), axis: [0, 0, 1])
            spider.addChild(leg)
        }
        return spider
    }

    /// A spider web in one corner, white silk on nothing, drawn once.
    private static let web: UnlitMaterial? = {
        let size = 512
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Spokes from the top-left corner, then sagging threads across them.
        let corner = CGPoint(x: 0, y: CGFloat(size))
        context.setStrokeColor(CGColor(srgbRed: 0.92, green: 0.92, blue: 0.95, alpha: 0.85))
        context.setLineWidth(3)
        let spokes = 7
        for spoke in 0...spokes {
            let angle = -CGFloat.pi / 2 * CGFloat(spoke) / CGFloat(spokes)
            context.move(to: corner)
            context.addLine(to: CGPoint(x: corner.x + cos(angle) * CGFloat(size) * 1.1, y: corner.y + sin(angle) * CGFloat(size) * 1.1))
        }
        context.strokePath()
        context.setLineWidth(2)
        for ring in 1...6 {
            let radius = CGFloat(ring) * CGFloat(size) / 6.5
            for spoke in 0..<spokes {
                let a0 = -CGFloat.pi / 2 * CGFloat(spoke) / CGFloat(spokes)
                let a1 = -CGFloat.pi / 2 * CGFloat(spoke + 1) / CGFloat(spokes)
                let start = CGPoint(x: corner.x + cos(a0) * radius, y: corner.y + sin(a0) * radius)
                let end = CGPoint(x: corner.x + cos(a1) * radius, y: corner.y + sin(a1) * radius)
                let mid = CGPoint(x: corner.x + cos((a0 + a1) / 2) * radius * 0.9, y: corner.y + sin((a0 + a1) / 2) * radius * 0.9)
                context.move(to: start)
                context.addQuadCurve(to: end, control: mid)
            }
        }
        context.strokePath()
        guard let image = context.makeImage(),
              let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .none
        return material
    }()
}
