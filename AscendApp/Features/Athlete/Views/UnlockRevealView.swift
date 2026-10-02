import RealityKit
import SwiftUI
import UIKit

/// The unlock moment: the climber's athlete turned to face them, the new item bursting into
/// view above it, hovering, then settling where it is worn - on the shoulder, overhead, on the
/// head, or over the whole athlete. Plays once each time it appears; with Reduce Motion the item
/// is simply on.
struct UnlockRevealView: View {
    /// The athlete as it was before the unlock.
    let look: AthleteLook
    let item: AthleteGear

    @State private var stage = UnlockRevealStage()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = stage
        RealityView { content in
            stage.install(in: &content, raisedOverhead: item.slot == .carry && item.carry == .overhead)
        } placeholder: {
            Color.clear
        }
        .task(id: item) {
            await stage.play(look: look, item: item, animated: !reduceMotion)
        }
        .accessibilityElement()
        .accessibilityLabel("Unlocked: \(item.title)")
    }
}

/// The entities behind `UnlockRevealView`.
@MainActor
final class UnlockRevealStage {
    private let root = Entity()
    private let athleteHolder = Entity()
    private let camera = PerspectiveCamera()
    private let flight = Entity()
    private let spotlight = PointLight()
    private var flying: ModelEntity?
    private var burst: ModelEntity?
    private var rig: MountainAthleteRig?
    private var updates: EventSubscription?
    private var elapsed: Double = 0
    private var playing: (item: AthleteGear, worn: [AthleteGear], landing: SIMD3<Float>)?
    private let rigs: MountainRigFactory
    private let gear: MountainGearLibrary

    /// Seconds the item takes to burst in, hover, and settle.
    static let appear = 0.35
    static let hover = 1.1
    static let settle = 0.55

    init(rigs: MountainRigFactory = .shared, gear: MountainGearLibrary = .shared) {
        self.rigs = rigs
        self.gear = gear
        // Turned so the right shoulder, where items are carried, comes toward the camera.
        athleteHolder.orientation = simd_quatf(angle: 0.38, axis: [0, 1, 0])
        root.addChild(athleteHolder)
        root.addChild(flight)
        // Lime light on the item while it hovers, gone once it is on.
        spotlight.light.color = UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 1)
        spotlight.light.intensity = 0
        spotlight.light.attenuationRadius = 2.5
        flight.addChild(spotlight)
        camera.camera.fieldOfViewInDegrees = 30
        root.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 1_800
        key.look(at: .zero, from: [1.6, 3, 2.6], relativeTo: nil)
        root.addChild(key)
        let rim = DirectionalLight()
        rim.light.intensity = 1_200
        rim.light.color = UIColor(red: 0.8, green: 0.95, blue: 0.62, alpha: 1)
        rim.look(at: [0, 1, 0], from: [-2, 2.2, -2.6], relativeTo: nil)
        root.addChild(rim)
    }

    func install(in content: inout RealityViewCameraContent, raisedOverhead: Bool) {
        if raisedOverhead {
            camera.look(at: [0, 1.25, 0], from: [0, 1.4, 5.8], relativeTo: nil)
        } else {
            camera.look(at: [0, 1.05, 0], from: [0, 1.2, 4.4], relativeTo: nil)
        }
        content.camera = .virtual
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.add(root)
        updates?.cancel()
        updates = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            self?.advance(by: event.deltaTime)
        }
    }

    func play(look: AthleteLook, item: AthleteGear, animated: Bool) async {
        var before = look
        before.unequip(item.slot)
        var after = before
        after.equip(item)
        guard let made = try? await rigs.rig(.init(look: before, style: .athlete(before), label: "", castsLight: true)) else { return }
        made.stand()
        rig?.root.removeFromParent()
        athleteHolder.addChild(made.root)
        rig = made

        // Kit is the athlete's own body redrawn, so it arrives as a second athlete swapped in
        // when the burst peaks; a shape flies in and lands.
        var dressed: MountainAthleteRig?
        if !item.isWornShape {
            dressed = try? await rigs.rig(.init(look: after, style: .athlete(after), label: "", castsLight: true))
            dressed?.stand()
        }
        guard animated else {
            if let dressed {
                swap(to: dressed)
            } else {
                made.wear(after.gear)
                made.stand()
            }
            return
        }
        flying?.removeFromParent()
        let entity: ModelEntity
        if item.isWornShape, let prepared = await gear.prepare(item) {
            entity = ModelEntity(mesh: prepared.mesh, materials: prepared.materials)
        } else {
            entity = ModelEntity()
        }
        entity.scale = .zero
        flight.addChild(entity)
        flying = entity
        pendingRig = dressed
        burst?.removeFromParent()
        if let made = await Self.makeBurst() {
            made.position = Self.hoverPoint(for: item)
            made.scale = .zero
            flight.addChild(made)
            burst = made
        }
        elapsed = 0
        playing = (item, after.gear, Self.landing(for: item))
    }

    private var pendingRig: MountainAthleteRig?

    private func swap(to dressed: MountainAthleteRig) {
        rig?.root.removeFromParent()
        athleteHolder.addChild(dressed.root)
        rig = dressed
    }

    /// Where the item hovers before it settles: above and a little in front of the athlete.
    private static func hoverPoint(for item: AthleteGear) -> SIMD3<Float> {
        item.carry == .overhead && item.slot == .carry ? [0, 2.3, 0.45] : [0, 1.85, 0.6]
    }

    /// Roughly where the item ends up, in the stage's space; the rig places it exactly when it
    /// takes over.
    private static func landing(for item: AthleteGear) -> SIMD3<Float> {
        let turn = simd_quatf(angle: 0.38, axis: [0, 1, 0])
        let local: SIMD3<Float> = switch (item.slot, item.carry) {
        case (.carry, .overhead): [0, 1.95, 0.05]
        case (.carry, .tray): [-0.22, 1.35, 0.4]
        case (.carry, _): [-0.19, 1.5, -0.03]
        case (.head, _): [0, 1.6, 0]
        case (.costume, _): [0, 1.35, 0]
        case (.tank, _): [0, 1.3, 0.15]
        case (.shorts, _): [0, 0.95, 0.15]
        case (.trainers, _): [0.1, 0.1, 0.15]
        }
        return turn.act(local)
    }

    private func advance(by seconds: Double) {
        guard let playing, let flying, seconds > 0 else { return }
        elapsed += seconds
        let hover = Self.hoverPoint(for: playing.item)
        let spin = simd_quatf(angle: Float(elapsed) * 3.2, axis: [0, 1, 0])
        spotlight.position = flying.position + [0, 0.1, 0.45]
        spotlight.light.intensity = elapsed < Self.appear + Self.hover ? 14_000 : max(0, 14_000 * Float(1 - (elapsed - Self.appear - Self.hover) / Self.settle))
        if elapsed < Self.appear {
            let t = Float(elapsed / Self.appear)
            // Overshoot, then settle to full size.
            let pop = 1.25 * sin(t * .pi * 0.5) + 0.12 * sin(t * .pi)
            flying.scale = SIMD3(repeating: pop)
            flying.position = hover
            flying.orientation = spin
        } else if elapsed < Self.appear + Self.hover {
            let t = Float((elapsed - Self.appear) / Self.hover)
            flying.scale = SIMD3(repeating: 1.25 - 0.05 * sin(t * .pi))
            flying.position = hover + [0, 0.05 * sin(Float(elapsed) * 4), 0]
            flying.orientation = spin
        } else if elapsed < Self.appear + Self.hover + Self.settle {
            let t = Float((elapsed - Self.appear - Self.hover) / Self.settle)
            let ease = t * t * (3 - 2 * t)
            flying.scale = SIMD3(repeating: 1.25 - 0.25 * ease)
            flying.position = hover + (playing.landing - hover) * ease
            flying.orientation = simd_slerp(spin, simd_quatf(angle: 0, axis: [0, 1, 0]), ease)
        } else {
            flying.removeFromParent()
            self.flying = nil
            spotlight.light.intensity = 0
            if let pendingRig {
                swap(to: pendingRig)
                self.pendingRig = nil
            } else {
                rig?.wear(playing.worn)
                rig?.stand()
            }
            self.playing = nil
        }
        if let burst {
            let t = Float(min(elapsed / 0.9, 1))
            burst.scale = SIMD3(repeating: 0.2 + 1.6 * t)
            burst.components.set(OpacityComponent(opacity: 1 - t))
            if t >= 1 {
                burst.removeFromParent()
                self.burst = nil
            }
        }
    }

    /// A ring of lime light that bursts outward as the item appears, always facing the camera.
    private static func makeBurst() async -> ModelEntity? {
        let size = 256
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colors = [
            UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 0).cgColor,
            UIColor(red: 0.75, green: 1, blue: 0.3, alpha: 0.95).cgColor,
            UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0.55, 0.78, 1]) else { return nil }
        let centre = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: CGFloat(size / 2), options: [])
        guard let image = context.makeImage(),
              let texture = try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let ring = ModelEntity(mesh: .generatePlane(width: 0.9, height: 0.9), materials: [material])
        ring.components.set(BillboardComponent())
        return ring
    }
}
