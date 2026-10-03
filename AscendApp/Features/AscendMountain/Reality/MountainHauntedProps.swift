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
            ghost.name = ghostName
            post.addChild(ghost)
        }
        return post
    }

    static let ghostName = "haunted-ghost"
    private static let ghostHeight: Float = 2.3

    /// Lets every ghost in view drift: a slow bob and a little sway, each on its own phase so a
    /// row of them never moves in step.
    static func drift(_ ghosts: [Entity], at time: TimeInterval) {
        for (index, ghost) in ghosts.enumerated() {
            let phase = time * 1.1 + Double(index) * 1.7
            // Each ghost faces in toward the stairs from whichever side it hangs on.
            let side: Float = ghost.position.x >= 0 ? 1 : -1
            ghost.position.y = ghostHeight + Float(sin(phase)) * 0.18
            ghost.orientation = simd_quatf(angle: -side * 0.7 + Float(cos(phase * 0.4)) * 0.3, axis: [0, 1, 0])
                * simd_quatf(angle: Float(sin(phase * 0.6)) * 0.12, axis: [0, 0, 1])
        }
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
                // The web fills the corner between the pillar and the lintel, its spokes meeting
                // in the corner itself.
                let reach: Float = 1.15
                let corner = ModelEntity(mesh: .generatePlane(width: reach, height: reach), materials: [web])
                // Just behind the step plaque, so the number always reads over the silk.
                corner.position = [side * (span - 0.23 - reach / 2), lintelBottom - reach / 2, depth / 2 - 0.02]
                corner.orientation = simd_quatf(angle: side < 0 ? 0 : -.pi / 2, axis: [0, 0, 1])
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

    /// An old cobweb in one corner, drawn once: a haze of loose silk sagging between the two
    /// walls of the corner, and an orb over it that is uneven, broken in places and torn at the
    /// edge, so it reads as left there rather than drawn.
    private static let web: UnlitMaterial? = {
        let size = 1024
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        var seed: UInt64 = 0x5EED_C0B3
        func random() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 40) / CGFloat(1 << 24)
        }
        let full = CGFloat(size)
        let corner = CGPoint(x: 0, y: full)
        func point(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: corner.x + cos(angle) * radius, y: corner.y + sin(angle) * radius)
        }

        // The haze: threads strung from the top wall to the side wall, each sagging.
        for _ in 0..<260 {
            let from = CGPoint(x: random() * full * 0.9, y: full)
            let to = CGPoint(x: 0, y: full - random() * full * 0.9)
            let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let sag = CGPoint(x: middle.x + random() * 60, y: middle.y - 40 - random() * 120)
            context.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.95, alpha: 0.05 + random() * 0.12))
            context.setLineWidth(1 + random() * 1.4)
            context.move(to: from)
            context.addQuadCurve(to: to, control: sag)
            context.strokePath()
        }

        // The orb: uneven spokes, a spiral with gaps where threads have broken.
        var angles: [CGFloat] = []
        for spoke in 0...12 {
            let wobble = (random() - 0.5) * 0.09
            angles.append(-CGFloat.pi / 2 * min(max(CGFloat(spoke) / 12 + wobble, 0), 1))
        }
        context.setStrokeColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.98, alpha: 0.75))
        for angle in angles {
            context.setLineWidth(2 + random() * 1.2)
            context.move(to: corner)
            let reach = full * (0.72 + random() * 0.26)
            context.addQuadCurve(to: point(angle, reach), control: point(angle + (random() - 0.5) * 0.06, reach * 0.5))
            context.strokePath()
        }
        var radius = full * 0.06
        while radius < full * 0.78 {
            for (a0, a1) in zip(angles, angles.dropFirst()) where random() > 0.16 {
                let r0 = radius * (0.97 + random() * 0.06), r1 = radius * (0.97 + random() * 0.06)
                context.setStrokeColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.98, alpha: 0.35 + random() * 0.35))
                context.setLineWidth(1.2 + random())
                context.move(to: point(a0, r0))
                context.addQuadCurve(to: point(a1, r1), control: point((a0 + a1) / 2, (r0 + r1) / 2 * (0.86 + random() * 0.08)))
                context.strokePath()
            }
            radius *= 1.1 + random() * 0.06
        }

        // A few torn threads hanging loose from the orb's edge.
        for _ in 0..<5 {
            let start = point(-CGFloat.pi / 2 * (0.15 + random() * 0.7), full * (0.55 + random() * 0.2))
            context.setStrokeColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.98, alpha: 0.5))
            context.setLineWidth(1.5)
            context.move(to: start)
            context.addQuadCurve(to: CGPoint(x: start.x + (random() - 0.5) * 40, y: start.y - 120 - random() * 160),
                                 control: CGPoint(x: start.x + 30, y: start.y - 60))
            context.strokePath()
        }

        guard let image = context.makeImage(),
              let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .none
        return material
    }()
}
