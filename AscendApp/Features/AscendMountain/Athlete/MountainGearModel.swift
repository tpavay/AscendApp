import Foundation
import simd

/// What one seasonal item looks like: its shapes and what each is painted with. Authored with
/// the origin at the point the item rests on - the shoulder it perches on, or the hands that
/// press it overhead - with +Z the athlete's front and +Y up. Pure geometry, so the shapes are
/// testable without a renderer; `MountainGearLibrary` turns them into one mesh per item, shared
/// by every climber carrying it.
struct MountainGearModel: Sendable {
    /// How a part is painted.
    enum Paint: Hashable, Sendable {
        /// A flat colour.
        case color(MountainColor, roughness: Float)
        /// A polished metal.
        case metal(MountainColor, roughness: Float)
        /// A pumpkin's skin, lobed, perhaps with a glowing carved face.
        case pumpkin(PumpkinSkin)
        /// A gourd's green and gold stripes.
        case gourdStripes
        /// Candlelight through a carved face: lit, and see-through outside the carving.
        case carvedGlow(PumpkinSkin)
    }

    enum PumpkinSkin: String, Hashable, Sendable, CaseIterable {
        case classic, ghost, heirloom, lantern, midnight

        /// Crease, body and highlight, light to dark across each lobe.
        var palette: (crease: MountainColor, body: MountainColor, highlight: MountainColor) {
            switch self {
            case .classic, .lantern:
                (MountainColor(hex: "#8A3C06")!, MountainColor(hex: "#E8730C")!, MountainColor(hex: "#F79A2E")!)
            case .ghost:
                (MountainColor(hex: "#A9AE9A")!, MountainColor(hex: "#E9E6DA")!, MountainColor(hex: "#FBFAF4")!)
            case .heirloom:
                (MountainColor(hex: "#2C5755")!, MountainColor(hex: "#5E9C95")!, MountainColor(hex: "#8CC2B8")!)
            case .midnight:
                (MountainColor(hex: "#050506")!, MountainColor(hex: "#1C1C21")!, MountainColor(hex: "#34343C")!)
            }
        }

        /// The light through a carved face, or nil for an uncarved pumpkin.
        var glow: MountainColor? {
            switch self {
            case .lantern: MountainColor(hex: "#FFB83A")!
            case .midnight: MountainColor(hex: "#86D30A")!
            case .classic, .ghost, .heirloom: nil
            }
        }

        var stem: MountainColor {
            switch self {
            case .ghost: MountainColor(hex: "#8C8F6A")!
            case .midnight: MountainColor(hex: "#2A2E1E")!
            default: MountainColor(hex: "#4E5B22")!
            }
        }
    }

    struct Part: Sendable {
        let geometry: MountainGearGeometry
        let paint: Paint
    }

    let parts: [Part]
    /// The colour of the light a carved item casts from inside, if it glows.
    var glow: MountainColor? = nil

    var triangleCount: Int { parts.reduce(0) { $0 + $1.geometry.triangleCount } }

    /// How far above its resting point the item reaches, for framing it.
    var height: Float {
        parts.flatMap(\.geometry.positions).map(\.y).max() ?? 0
    }

    static func model(for gear: AthleteGear) -> MountainGearModel {
        switch gear {
        case .pumpkinClassic: pumpkin(.classic)
        case .pumpkinGhost: pumpkin(.ghost)
        case .pumpkinLantern: pumpkin(.lantern)
        case .pumpkinHeirloom: pumpkin(.heirloom, squash: 0.7)
        case .pumpkinMidnight: pumpkin(.midnight)
        case .pumpkinGiant: pumpkin(.classic, radius: 0.34, squash: 0.78)
        case .harvestGourd: gourd()
        case .cornucopia: cornucopia()
        case .roastTurkey: turkey(skin: .color(roastBrown, roughness: 0.32))
        case .pumpkinPie: pie()
        case .goldenTurkey: turkey(skin: .metal(gold, roughness: 0.22))
        case .turkeyGiant: turkey(skin: .color(roastBrown, roughness: 0.32), scale: 2.4)
        }
    }

    // MARK: - Palette

    static let roastBrown = MountainColor(hex: "#9C4E1A")!
    static let gold = MountainColor(hex: "#D4AF37")!
    static let boneCream = MountainColor(hex: "#F1EADB")!
    static let wicker = MountainColor(hex: "#B07A3A")!
    static let crust = MountainColor(hex: "#D9A35B")!
    static let pieFilling = MountainColor(hex: "#B95A1A")!
    static let cream = MountainColor(hex: "#FBF7EE")!
    static let gourdStem = MountainColor(hex: "#5B4A2A")!

    // MARK: - Shapes

    /// A pumpkin's body: a squashed sphere with eight lobes, dimpled at both ends, centred on the
    /// origin. Its face, if carved, looks along +Z.
    static func pumpkinBody(radius: Float, squash: Float = 0.82, segments: Int = 40) -> MountainGearGeometry {
        let rings = 18
        let profile = (0...rings).map { j -> SIMD2<Float> in
            let phi = Float.pi * Float(j) / Float(rings)
            // Pull the poles in so the stem sits in a dimple.
            let dimple: Float = 1 - 0.18 * pow(abs(cos(phi)), 6)
            return SIMD2(sin(phi) * radius, -cos(phi) * radius * squash * dimple)
        }
        return .lathe(profile: profile, segments: segments) { angle in
            0.92 + 0.08 * pow(abs(sin(angle * 4)), 0.4)
        }
    }

    /// How far a pumpkin body's top and bottom sit from its centre.
    static func pumpkinPole(radius: Float, squash: Float) -> Float {
        radius * squash * 0.82
    }

    static func stem(base: SIMD3<Float>, height: Float, radius: Float) -> MountainGearGeometry {
        let profile: [SIMD2<Float>] = [
            SIMD2(radius * 1.3, 0), SIMD2(radius, height * 0.25), SIMD2(radius * 0.8, height * 0.85), SIMD2(radius * 0.6, height), SIMD2(0, height)
        ]
        return MountainGearGeometry.lathe(profile: profile, segments: 8)
            .deformed { point in SIMD3(point.x + point.y * point.y * 2.2 / max(height / 0.05, 1), point.y, point.z) }
            .transformed(translation: base)
    }

    /// A pumpkin resting on its base, its face turned to the climber's right so the glow reads
    /// from the camera behind them.
    static func pumpkin(_ skin: PumpkinSkin, radius: Float = 0.14, squash: Float = 0.82) -> MountainGearModel {
        let pole = pumpkinPole(radius: radius, squash: squash)
        let facing = simd_quatf(angle: -2.75, axis: SIMD3(0, 1, 0))
        let body = pumpkinBody(radius: radius, squash: squash).transformed(rotation: facing, translation: SIMD3(0, pole, 0))
        let stem = stem(base: SIMD3(0, 2 * pole - radius * 0.06, 0), height: radius * 0.42, radius: radius * 0.13)
        var parts = [
            Part(geometry: body, paint: .pumpkin(skin)),
            Part(geometry: stem, paint: .color(skin.stem, roughness: 0.85))
        ]
        if skin.glow != nil {
            // The face is a lit decal a hair outside the skin, over the front lobes only.
            let face = pumpkinBody(radius: radius * 1.006, squash: squash)
                .keepingTriangles { uv in uv.x > 0.37 && uv.x < 0.63 && uv.y > 0.25 && uv.y < 0.78 }
                .transformed(rotation: facing, translation: SIMD3(0, pole, 0))
            parts.append(Part(geometry: face, paint: .carvedGlow(skin)))
        }
        return MountainGearModel(parts: parts, glow: skin.glow)
    }

    /// A long striped gourd lying front to back on the shoulder.
    static func gourd() -> MountainGearModel {
        let radius: Float = 0.085, squash: Float = 1.7
        let pole = pumpkinPole(radius: radius, squash: squash)
        let lying = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        let body = pumpkinBody(radius: radius, squash: squash, segments: 32).transformed(rotation: lying, translation: SIMD3(0, radius * 0.92, 0))
        let stem = stem(base: .zero, height: 0.045, radius: 0.012)
            .transformed(rotation: lying, translation: SIMD3(0, radius * 0.92, pole - 0.006))
        return MountainGearModel(parts: [
            Part(geometry: body, paint: .gourdStripes),
            Part(geometry: stem, paint: .color(gourdStem, roughness: 0.85))
        ])
    }

    /// A woven horn spilling fruit out of its mouth, which faces forward.
    static func cornucopia() -> MountainGearModel {
        let count = 16
        let path = (0..<count).map { i -> SIMD3<Float> in
            let t = Float(i) / Float(count - 1)
            return SIMD3(0.03 * sin(t * 3.4), 0.1 + 0.16 * t * t * t, 0.14 - 0.32 * t + 0.08 * t * t * t)
        }
        let taper = (0..<count).map { i -> Float in
            let t = Float(i) / Float(count - 1)
            return max(1 - t * 0.97, 0.03)
        }
        let horn = MountainGearGeometry.tube(path: path, radius: 0.1, taper: taper, sides: 14)
        let fruit = MountainGearGeometry.sphere(radius: 0.05, segments: 12).transformed(translation: SIMD3(0.035, 0.085, 0.15))
        let orange = MountainGearGeometry.sphere(radius: 0.045, segments: 12).transformed(translation: SIMD3(-0.04, 0.075, 0.155))
        var grapes = MountainGearGeometry()
        for (x, y, z) in [(0.0, 0.14, 0.15), (0.02, 0.13, 0.17), (-0.02, 0.13, 0.17), (0.0, 0.115, 0.185), (0.012, 0.155, 0.16), (-0.012, 0.155, 0.16)] as [(Float, Float, Float)] {
            grapes.append(MountainGearGeometry.sphere(radius: 0.017, segments: 8).transformed(translation: SIMD3(x, y, z)))
        }
        return MountainGearModel(parts: [
            Part(geometry: horn, paint: .color(wicker, roughness: 0.92)),
            Part(geometry: fruit, paint: .color(MountainColor(hex: "#B3241E")!, roughness: 0.35)),
            Part(geometry: orange, paint: .color(MountainColor(hex: "#F08A1A")!, roughness: 0.6)),
            Part(geometry: grapes, paint: .color(MountainColor(hex: "#5A2A6E")!, roughness: 0.3))
        ])
    }

    /// A roast turkey, breast up, its drumsticks to the back with paper frills on the bones.
    static func turkey(skin: Paint, scale: Float = 1) -> MountainGearModel {
        let length: Float = 0.17, radius: Float = 0.125
        let rings = 14
        let profile = (0...rings).map { j -> SIMD2<Float> in
            let phi = Float.pi * Float(j) / Float(rings)
            return SIMD2(sin(phi) * radius, -cos(phi) * length)
        }
        let lying = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        var body = MountainGearGeometry.lathe(profile: profile, segments: 24).transformed(rotation: lying)
        body = body.deformed { point in
            // Flatter underneath, plumper at the breast.
            let y = point.y < 0 ? point.y * 0.62 : point.y * 0.95
            return SIMD3(point.x * (1 + 0.12 * max(point.z, 0) / length), y + radius * 0.62, point.z)
        }
        var legs = MountainGearGeometry()
        var bones = MountainGearGeometry()
        for side in [-1, 1] as [Float] {
            let leg = MountainGearGeometry.lathe(profile: [
                SIMD2(0, 0), SIMD2(0.035, 0.012), SIMD2(0.05, 0.05), SIMD2(0.04, 0.1), SIMD2(0.016, 0.13), SIMD2(0, 0.135)
            ], segments: 12)
            let aim = simd_quatf(angle: -1.1, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: side * 0.25, axis: SIMD3(0, 0, 1))
            let base = SIMD3<Float>(side * 0.075, radius * 0.7, -0.07)
            legs.append(leg.transformed(rotation: aim, translation: base))
            let frill = MountainGearGeometry.lathe(profile: [
                SIMD2(0, 0), SIMD2(0.013, 0.002), SIMD2(0.02, 0.03), SIMD2(0.026, 0.045), SIMD2(0, 0.046)
            ], segments: 10)
            bones.append(frill.transformed(rotation: aim, translation: base + aim.act(SIMD3(0, 0.125, 0))))
        }
        let parts = [
            Part(geometry: body, paint: skin),
            Part(geometry: legs, paint: skin),
            Part(geometry: bones, paint: .color(boneCream, roughness: 0.8))
        ]
        return MountainGearModel(parts: parts.map { Part(geometry: $0.geometry.scaled(by: scale), paint: $0.paint) })
    }

    /// A pumpkin pie with a fluted crust and a curl of cream, carried flat like a tray.
    static func pie() -> MountainGearModel {
        let crust = MountainGearGeometry.lathe(profile: [
            SIMD2(0, 0), SIMD2(0.1, 0), SIMD2(0.128, 0.034), SIMD2(0.14, 0.048), SIMD2(0.128, 0.055), SIMD2(0.116, 0.044), SIMD2(0.11, 0.04)
        ], segments: 36) { angle in 1 + 0.025 * sin(angle * 18) }
        let filling = MountainGearGeometry.lathe(profile: [SIMD2(0.112, 0.04), SIMD2(0.06, 0.043), SIMD2(0, 0.044)], segments: 36)
        let cream = MountainGearGeometry.lathe(profile: [
            SIMD2(0, 0.04), SIMD2(0.03, 0.044), SIMD2(0.026, 0.06), SIMD2(0.016, 0.072), SIMD2(0, 0.084)
        ], segments: 16) { angle in 1 + 0.12 * sin(angle * 6) }
        return MountainGearModel(parts: [
            Part(geometry: crust, paint: .color(Self.crust, roughness: 0.75)),
            Part(geometry: filling, paint: .color(pieFilling, roughness: 0.45)),
            Part(geometry: cream, paint: .color(Self.cream, roughness: 0.6))
        ])
    }
}
