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
        /// White cloth with two eye holes cut in the front.
        case ghostSheet
        /// Candy corn's yellow, orange and white bands, up the shape.
        case candyCornBands
        /// A chocolate bar's purple wrapper, an Ascend-lime band round it.
        case wrapper
    }

    enum PumpkinSkin: String, Hashable, Sendable, CaseIterable {
        case classic, ghost, heirloom, lantern, midnight, giantLantern

        /// Crease, body and highlight, light to dark across each lobe.
        var palette: (crease: MountainColor, body: MountainColor, highlight: MountainColor) {
            switch self {
            case .classic, .lantern, .giantLantern:
                (MountainColor(hex: "#8A3C06")!, MountainColor(hex: "#E8730C")!, MountainColor(hex: "#F79A2E")!)
            case .ghost:
                (MountainColor(hex: "#A9AE9A")!, MountainColor(hex: "#E9E6DA")!, MountainColor(hex: "#FBFAF4")!)
            case .heirloom:
                (MountainColor(hex: "#2C5755")!, MountainColor(hex: "#5E9C95")!, MountainColor(hex: "#8CC2B8")!)
            case .midnight:
                (MountainColor(hex: "#050506")!, MountainColor(hex: "#1C1C21")!, MountainColor(hex: "#34343C")!)
            }
        }

        /// The face carved into it, if any.
        var face: Face? {
            switch self {
            case .classic, .heirloom: nil
            case .ghost: .hollow
            case .lantern, .midnight: .classic
            case .giantLantern: .grin
            }
        }

        enum Face: Sendable {
            /// Triangle eyes and nose, a toothy smile.
            case classic
            /// Round staring eyes and a round mouth: a ghost's.
            case hollow
            /// Slanted eyes and a wide jagged grin: the giant's.
            case grin
        }

        /// The light through a carved face, or nil for an uncarved pumpkin.
        var glow: MountainColor? {
            switch self {
            case .lantern, .giantLantern: MountainColor(hex: "#FFB83A")!
            case .midnight: MountainColor(hex: "#86D30A")!
            case .ghost: MountainColor(hex: "#9FE8FF")!
            case .classic, .heirloom: nil
            }
        }

        var stem: MountainColor {
            switch self {
            case .ghost: MountainColor(hex: "#8C8F6A")!
            case .midnight: MountainColor(hex: "#2A2E1E")!
            default: MountainColor(hex: "#4E5B22")!
            }
        }

        /// How warty the skin is, 0 smooth.
        var warts: Float {
            switch self {
            case .heirloom: 0.6
            case .giantLantern: 0.5
            default: 0
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
        case .pumpkinGiant: pumpkin(.classic, radius: 0.42, squash: 0.78)
        case .pumpkinGiantLantern: pumpkin(.giantLantern, radius: 0.42, squash: 0.8)
        case .witchHat: witchHat()
        case .pumpkinHead: pumpkinHead()
        case .ghostSheet: ghostSheet()
        case .candyCorn: candyCorn()
        case .chocolateBar: chocolateBar()
        case .witchingShorts, .glowTrainers, .emberTrainers:
            // Kit is drawn on the athlete's own body (`MountainKitColor`), not as a shape.
            MountainGearModel(parts: [])
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
    static let leafGreen = MountainColor(hex: "#3F6A22")!
    static let witchBlack = MountainColor(hex: "#1A1622")!
    static let witchBand = MountainColor(hex: "#7B3FC4")!
    static let buckleGold = MountainColor(hex: "#D4AF37")!
    static let sheetWhite = MountainColor(hex: "#F2F2EE")!

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

    /// Raises warts on a body centred on the origin: a few dozen soft bumps at fixed spots, so
    /// every copy of an item has the same ones.
    static func warted(_ body: MountainGearGeometry, amount: Float) -> MountainGearGeometry {
        guard amount > 0 else { return body }
        var spots: [SIMD3<Float>] = []
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24)
        }
        for _ in 0..<46 {
            let z = next() * 1.6 - 0.8, angle = next() * 2 * .pi
            let ring = sqrt(max(1 - z * z, 0))
            spots.append(SIMD3(ring * cos(angle), z, ring * sin(angle)))
        }
        return body.deformed { point in
            let length = simd_length(point)
            guard length > 1e-6 else { return point }
            let direction = point / length
            var bump: Float = 0
            for spot in spots {
                let closeness = simd_dot(direction, spot)
                if closeness > 0.985 { bump += (closeness - 0.985) / 0.015 }
            }
            return point * (1 + amount * 0.045 * min(bump, 1.4))
        }
    }

    /// A curling tendril and a leaf at the foot of the stem.
    static func vine(base: SIMD3<Float>, radius: Float) -> (tendril: MountainGearGeometry, leaf: MountainGearGeometry) {
        let steps = 28
        // Runs out from the stem along the top of the pumpkin, then curls up tight at its end.
        let path = (0...steps).map { i -> SIMD3<Float> in
            let t = Float(i) / Float(steps)
            let run = SIMD3<Float>(radius * 0.5 * t, radius * 0.06 * sin(t * .pi), -radius * 0.2 * t)
            let curl = max(t - 0.45, 0) / 0.55
            let angle = curl * 1.5 * 2 * .pi
            let spiral = radius * 0.13 * curl * (1 - curl * 0.5)
            return base + run + SIMD3(sin(angle) * spiral, (1 - cos(angle)) * spiral, 0)
        }
        let taper = (0...steps).map { 1 - Float($0) / Float(steps + 8) }
        let tendril = MountainGearGeometry.tube(path: path, radius: radius * 0.035, taper: taper, sides: 6)
        let leaf = MountainGearGeometry.sphere(radius: 1, segments: 10)
            .deformed { point in
                // Long, thin, and bent down toward its tip, lying on the pumpkin's shoulder.
                let x = point.x * radius * 0.3, z = point.z * radius * 0.18
                return SIMD3(x, point.y * radius * 0.02 - x * x * 3 / max(radius, 0.01), z)
            }
            .transformed(rotation: simd_quatf(angle: 0.6, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.35, axis: SIMD3(0, 0, 1)),
                         translation: base + SIMD3(-radius * 0.32, -radius * 0.04, radius * 0.1))
        return (tendril, leaf)
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
        let body = warted(pumpkinBody(radius: radius, squash: squash), amount: skin.warts)
            .transformed(rotation: facing, translation: SIMD3(0, pole, 0))
        let top = SIMD3<Float>(0, 2 * pole - radius * 0.06, 0)
        let stem = stem(base: top, height: radius * 0.42, radius: radius * 0.13)
        let vine = vine(base: top, radius: radius)
        var parts = [
            Part(geometry: body, paint: .pumpkin(skin)),
            Part(geometry: stem, paint: .color(skin.stem, roughness: 0.85)),
            Part(geometry: vine.tendril, paint: .color(skin.stem, roughness: 0.8)),
            Part(geometry: vine.leaf, paint: .color(leafGreen, roughness: 0.7))
        ]
        if skin.face != nil {
            // The face is a lit decal a hair outside the skin, over the front lobes only. Warts
            // stay off it, so the carving sits flush.
            let face = pumpkinBody(radius: radius * 1.006, squash: squash)
                .keepingTriangles { uv in uv.x > 0.37 && uv.x < 0.63 && uv.y > 0.22 && uv.y < 0.8 }
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

    /// A woven horn spilling fruit out of its mouth, which faces forward, laid along the palm.
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
        // Open at the mouth, so its inside is drawn too.
        let horn = MountainGearGeometry.tube(path: path, radius: 0.1, taper: taper, sides: 14).doubleSided()
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

    // MARK: - Candy

    /// A giant piece of candy corn, perched point up on the shoulder.
    static func candyCorn() -> MountainGearModel {
        var profile: [SIMD2<Float>] = [SIMD2(0, 0)]
        let base: Float = 0.105, height: Float = 0.3
        for i in 0...14 {
            let t = Float(i) / 14
            // A rounded base swelling out, then tapering to a soft point.
            let radius = base * (sin(min(t * 4, 1) * .pi / 2) * (1 - t * t * 0.92))
            profile.append(SIMD2(max(radius, 0.004), height * t))
        }
        profile.append(SIMD2(0, height + 0.006))
        let corn = MountainGearGeometry.lathe(profile: profile, segments: 24) { angle in
            // Candy corn is a little flattened front to back.
            1 - 0.18 * abs(cos(angle))
        }
        .transformed(rotation: simd_quatf(angle: 0.25, axis: SIMD3(0, 0, 1)))
        return MountainGearModel(parts: [Part(geometry: corn, paint: .candyCornBands)])
    }

    /// A giant chocolate bar, half unwrapped, held flat out on the palm with its squares showing.
    static func chocolateBar() -> MountainGearModel {
        let length: Float = 0.5, width: Float = 0.22, thickness: Float = 0.05
        var squares = MountainGearGeometry()
        let columns = 3, rows = 4
        let squareLength = length * 0.5 / Float(rows), squareWidth = width / Float(columns)
        for row in 0..<rows {
            for column in 0..<columns {
                let centre = SIMD3<Float>(
                    -width / 2 + squareWidth * (Float(column) + 0.5),
                    thickness * 0.5,
                    length * 0.5 - squareLength * (Float(row) + 0.5)
                )
                squares.append(MountainGearGeometry.box(size: SIMD3(squareWidth * 0.9, thickness, squareLength * 0.9)).transformed(translation: centre))
            }
        }
        let slab = MountainGearGeometry.box(size: SIMD3(width, thickness * 0.55, length * 0.5)).transformed(translation: SIMD3(0, thickness * 0.28, length * 0.25))
        squares.append(slab)
        let wrapper = MountainGearGeometry.box(size: SIMD3(width * 1.06, thickness * 1.18, length * 0.52)).transformed(translation: SIMD3(0, thickness * 0.55, -length * 0.25))
        let foil = MountainGearGeometry.box(size: SIMD3(width * 1.02, thickness * 1.1, 0.02)).transformed(translation: SIMD3(0, thickness * 0.55, 0.005))
        // Tipped back toward the camera behind so the unwrapped squares show.
        let tilt = simd_quatf(angle: 0.35, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: 0.6, axis: SIMD3(0, 1, 0))
        // Lifted so the tilted bar rests on the palm rather than through it.
        let lift = SIMD3<Float>(0, 0.05, 0)
        return MountainGearModel(parts: [
            Part(geometry: squares.transformed(rotation: tilt, translation: lift), paint: .color(MountainColor(hex: "#4A2512")!, roughness: 0.42)),
            Part(geometry: wrapper.transformed(rotation: tilt, translation: lift), paint: .wrapper),
            Part(geometry: foil.transformed(rotation: tilt, translation: lift), paint: .metal(MountainColor(hex: "#C9CCD2")!, roughness: 0.25))
        ])
    }

    // MARK: - Worn

    /// Where the top of the head sits above the head joint, which every head item is authored
    /// from: the athlete pack's bodies differ by under a centimetre here.
    static let crown: Float = 0.21

    /// A tall black hat with a purple band and a gold buckle, its tip bent back. Authored from
    /// the head joint at rest.
    static func witchHat() -> MountainGearModel {
        let base = crown * 0.72
        let brimRadius: Float = 0.25, crownRadius: Float = 0.118, height: Float = 0.36
        var profile: [SIMD2<Float>] = [
            SIMD2(0.0, base - 0.004),
            SIMD2(crownRadius, base - 0.006),
            SIMD2(brimRadius * 0.8, base - 0.012),
            SIMD2(brimRadius, base - 0.022),
            SIMD2(brimRadius + 0.004, base - 0.014),
            SIMD2(brimRadius * 0.8, base - 0.002),
            SIMD2(crownRadius + 0.004, base + 0.008)
        ]
        for i in 1...12 {
            let t = Float(i) / 12
            profile.append(SIMD2(crownRadius * (1 - t) * (1 - 0.25 * t) + 0.004 * (1 - t), base + 0.008 + height * t))
        }
        profile.append(SIMD2(0, base + 0.008 + height))
        let bendStart = base + height * 0.42
        let hat = MountainGearGeometry.lathe(profile: profile, segments: 32).deformed { point in
            guard point.y > bendStart else { return point }
            let rise = point.y - bendStart
            return SIMD3(point.x, point.y - rise * rise * 0.9, point.z - rise * rise * 2.6)
        }
        let band = MountainGearGeometry.lathe(profile: [
            SIMD2(crownRadius + 0.006, base + 0.008), SIMD2(crownRadius * 0.97 + 0.006, base + 0.05),
            SIMD2(crownRadius * 0.9 + 0.005, base + 0.052)
        ], segments: 32)
        var buckle = MountainGearGeometry()
        let width: Float = 0.05, tall: Float = 0.04, bar: Float = 0.009, depth: Float = 0.008
        let middle = SIMD3<Float>(0, base + 0.03, crownRadius + 0.008)
        for (offset, size) in [
            (SIMD3<Float>(0, (tall - bar) / 2, 0), SIMD3<Float>(width, bar, depth)),
            (SIMD3<Float>(0, -(tall - bar) / 2, 0), SIMD3<Float>(width, bar, depth)),
            (SIMD3<Float>((width - bar) / 2, 0, 0), SIMD3<Float>(bar, tall, depth)),
            (SIMD3<Float>(-(width - bar) / 2, 0, 0), SIMD3<Float>(bar, tall, depth))
        ] {
            buckle.append(MountainGearGeometry.box(size: size).transformed(translation: middle + offset))
        }
        let tilt = simd_quatf(angle: -0.12, axis: SIMD3(1, 0, 0))
        let lift = SIMD3<Float>(0, 0, -0.012)
        return MountainGearModel(parts: [
            Part(geometry: hat.transformed(rotation: tilt, translation: lift), paint: .color(witchBlack, roughness: 0.75)),
            Part(geometry: band.transformed(rotation: tilt, translation: lift), paint: .color(witchBand, roughness: 0.5)),
            Part(geometry: buckle.transformed(rotation: tilt, translation: lift), paint: .metal(buckleGold, roughness: 0.3))
        ])
    }

    /// A glowing jack-o'-lantern worn over the whole head: the headless horseman's. Authored from
    /// the head joint at rest.
    static func pumpkinHead() -> MountainGearModel {
        let radius: Float = 0.19, squash: Float = 0.86
        let centre = SIMD3<Float>(0, crown * 0.48, 0.012)
        let body = pumpkinBody(radius: radius, squash: squash, segments: 48).transformed(translation: centre)
        let face = pumpkinBody(radius: radius * 1.006, squash: squash, segments: 48)
            .keepingTriangles { uv in uv.x > 0.37 && uv.x < 0.63 && uv.y > 0.22 && uv.y < 0.8 }
            .transformed(translation: centre)
        let top = centre + SIMD3(0, pumpkinPole(radius: radius, squash: squash) - radius * 0.05, 0)
        let stem = stem(base: top, height: radius * 0.4, radius: radius * 0.12)
        let vine = vine(base: top, radius: radius)
        return MountainGearModel(parts: [
            Part(geometry: body, paint: .pumpkin(.lantern)),
            Part(geometry: stem, paint: .color(PumpkinSkin.lantern.stem, roughness: 0.85)),
            Part(geometry: vine.tendril, paint: .color(PumpkinSkin.lantern.stem, roughness: 0.8)),
            Part(geometry: vine.leaf, paint: .color(leafGreen, roughness: 0.7)),
            Part(geometry: face, paint: .carvedGlow(.lantern))
        ], glow: PumpkinSkin.lantern.glow)
    }

    /// A white sheet thrown over the athlete, eye holes cut, hem rippling at the thighs: every
    /// trick-or-treater's first costume. Authored from the base of the neck at rest, and drawn
    /// both sides so the inside shows under the hem.
    static func ghostSheet() -> MountainGearModel {
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0.36), SIMD2(0.08, 0.35), SIMD2(0.135, 0.3), SIMD2(0.158, 0.21), SIMD2(0.158, 0.12),
            SIMD2(0.165, 0.04), SIMD2(0.24, -0.04), SIMD2(0.28, -0.12), SIMD2(0.3, -0.3), SIMD2(0.33, -0.55),
            SIMD2(0.38, -0.78), SIMD2(0.41, -0.86)
        ]
        let sheet = MountainGearGeometry.lathe(profile: profile, segments: 40) { angle in
            1 + 0.05 * sin(angle * 5)
        }
        .deformed { point in
            // The hem ripples, and the cloth hangs a little in front where the chest pushes it.
            let ripple: Float = point.y < -0.6 ? 0.035 * sin(atan2(point.x, point.z) * 7) * (-0.6 - point.y) / 0.26 : 0
            let chest: Float = point.y < 0 && point.z > 0 ? 0.03 * min(-point.y / 0.3, 1) : 0
            return SIMD3(point.x, point.y + ripple, point.z + chest)
        }
        .transformed(translation: SIMD3(0, 0, 0.02))
        return MountainGearModel(parts: [Part(geometry: sheet.doubleSided(), paint: .ghostSheet)])
    }
}
