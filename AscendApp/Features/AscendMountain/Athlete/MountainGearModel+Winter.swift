import Foundation
import simd

/// December's Winter Lights and January's New Year: the shapes of the ten items that follow
/// Thanksgiving. Authored the way the earlier seasons are - origin where the item rests, +Z the
/// athlete's front, +Y up - and painted with flat colours and metals only, so they need no new
/// material and no texture.
extension MountainGearModel {
    // MARK: - Palette

    static let candyRed = MountainColor(hex: "#D62828")!
    static let peppermint = MountainColor(hex: "#F7F3EC")!
    static let giftGreen = MountainColor(hex: "#1F7A4D")!
    static let ribbonRed = MountainColor(hex: "#D62828")!
    static let bauble = MountainColor(hex: "#C8242B")!
    static let santaRed = MountainColor(hex: "#C62828")!
    static let furWhite = MountainColor(hex: "#F4F1EA")!
    static let partyGold = MountainColor(hex: "#E5B93C")!
    static let partyInk = MountainColor(hex: "#2A3D8F")!
    static let partyPink = MountainColor(hex: "#F06A9B")!
    static let rocketRed = MountainColor(hex: "#D8372E")!
    static let rocketFin = MountainColor(hex: "#2A5DB0")!
    static let sparklerWire = MountainColor(hex: "#B8BCC4")!
    static let plinthDark = MountainColor(hex: "#2B2118")!

    // MARK: - December

    /// A candy cane standing on its end, striped red and white in short bands, its hook curling
    /// forward over the top.
    static func candyCane() -> MountainGearModel {
        let stem = 10, hook = 14, height: Float = 0.3, radius: Float = 0.068
        var path = (0...stem).map { SIMD3<Float>(0, height * Float($0) / Float(stem), 0) }
        for i in 1...hook {
            let angle = Float.pi * Float(i) / Float(hook)
            path.append(SIMD3(0, height + radius * sin(angle), radius * (1 - cos(angle))))
        }

        var red = MountainGearGeometry(), white = MountainGearGeometry()
        let band = 3
        var start = 0, isRed = true
        while start < path.count - 1 {
            let end = min(start + band, path.count - 1)
            let segment = MountainGearGeometry.tube(path: Array(path[start...end]), radius: 0.022, sides: 10)
            if isRed { red.append(segment) } else { white.append(segment) }
            isRed.toggle()
            start = end
        }

        let lean = simd_quatf(angle: -0.18, axis: SIMD3(0, 0, 1))
        return MountainGearModel(parts: [
            Part(geometry: red.transformed(rotation: lean), paint: .color(candyRed, roughness: 0.3)),
            Part(geometry: white.transformed(rotation: lean), paint: .color(peppermint, roughness: 0.3))
        ])
    }

    /// A wrapped gift, ribbon crossed over the lid and a bow on top, carried flat like a tray.
    static func giftBox() -> MountainGearModel {
        let width: Float = 0.2, tall: Float = 0.13
        let box = MountainGearGeometry.box(size: SIMD3(width, tall, width)).transformed(translation: SIMD3(0, tall / 2, 0))
        var ribbon = MountainGearGeometry.box(size: SIMD3(0.034, tall + 0.006, width + 0.006)).transformed(translation: SIMD3(0, tall / 2, 0))
        ribbon.append(MountainGearGeometry.box(size: SIMD3(width + 0.006, tall + 0.006, 0.034)).transformed(translation: SIMD3(0, tall / 2, 0)))

        var bow = MountainGearGeometry()
        for side in [-1, 1] as [Float] {
            let loop = MountainGearGeometry.sphere(radius: 0.04, segments: 14)
                .deformed { SIMD3($0.x * 1.5, $0.y * 0.8, $0.z * 0.9) }
                .transformed(
                    rotation: simd_quatf(angle: side * 0.45, axis: SIMD3(0, 0, 1)),
                    translation: SIMD3(side * 0.05, tall + 0.03, 0)
                )
            bow.append(loop)
        }
        bow.append(MountainGearGeometry.sphere(radius: 0.022, segments: 10).transformed(translation: SIMD3(0, tall + 0.022, 0)))

        return MountainGearModel(parts: [
            Part(geometry: box, paint: .color(giftGreen, roughness: 0.55)),
            Part(geometry: ribbon, paint: .color(ribbonRed, roughness: 0.4)),
            Part(geometry: bow, paint: .color(ribbonRed, roughness: 0.4))
        ])
    }

    /// A red knit hat with a white band and pom-pom, its tip flopped back. Authored from the head
    /// joint at rest, tilted and set back a hair like the witch hat.
    static func winterHat() -> MountainGearModel {
        let base = crown * 0.62, rise: Float = 0.3, bendStart = base + rise * 0.45
        func bend(_ point: SIMD3<Float>) -> SIMD3<Float> {
            guard point.y > bendStart else { return point }
            let lift = point.y - bendStart
            return SIMD3(point.x, point.y - lift * lift * 1.1, point.z - lift * lift * 3.4)
        }

        var profile: [SIMD2<Float>] = []
        for i in 0...12 {
            let t = Float(i) / 12
            profile.append(SIMD2(0.128 * (1 - t) * (1 - 0.15 * t) + 0.004, base + 0.03 + rise * t))
        }
        profile.append(SIMD2(0, base + 0.03 + rise))
        let cap = MountainGearGeometry.lathe(profile: profile, segments: 28).deformed(bend)

        let band = MountainGearGeometry.lathe(profile: [
            SIMD2(0.12, base - 0.014), SIMD2(0.14, base - 0.006), SIMD2(0.148, base + 0.02),
            SIMD2(0.14, base + 0.046), SIMD2(0.12, base + 0.054)
        ], segments: 28) { angle in 1 + 0.03 * sin(angle * 9) }

        let tip = bend(SIMD3(0, base + 0.03 + rise, 0))
        let pom = MountainGearGeometry.sphere(radius: 0.036, segments: 14).transformed(translation: tip + SIMD3(0, -0.01, -0.01))

        let tilt = simd_quatf(angle: -0.1, axis: SIMD3(1, 0, 0))
        let lift = SIMD3<Float>(0, 0, -0.01)
        return MountainGearModel(parts: [
            Part(geometry: cap.transformed(rotation: tilt, translation: lift), paint: .color(santaRed, roughness: 0.85)),
            Part(geometry: band.transformed(rotation: tilt, translation: lift), paint: .color(furWhite, roughness: 0.95)),
            Part(geometry: pom.transformed(rotation: tilt, translation: lift), paint: .color(furWhite, roughness: 0.95))
        ])
    }

    /// A glossy red bauble with a gold band, cap and hanging loop, perched on the shoulder. Scaled,
    /// it is the giant pressed overhead: the ball is its first part, so the hands close round it.
    static func ornament(scale: Float = 1) -> MountainGearModel {
        let radius: Float = 0.085
        let ball = MountainGearGeometry.sphere(radius: radius, segments: 28)
            .deformed { SIMD3($0.x, $0.y * 1.06, $0.z) }
            .transformed(translation: SIMD3(0, radius * 1.06, 0))
        let band = MountainGearGeometry.lathe(profile: [
            SIMD2(radius * 0.97, radius * 0.78), SIMD2(radius * 1.015, radius * 0.98),
            SIMD2(radius * 1.015, radius * 1.14), SIMD2(radius * 0.97, radius * 1.34)
        ], segments: 28).transformed(translation: SIMD3(0, radius * 0.05, 0))
        let capBase = radius * 2.12
        let cap = MountainGearGeometry.lathe(profile: [
            SIMD2(0.026, capBase - 0.012), SIMD2(0.03, capBase), SIMD2(0.022, capBase + 0.022), SIMD2(0.012, capBase + 0.03)
        ], segments: 16)
        let loop = MountainGearGeometry.tube(
            path: (0..<14).map { i in
                let angle = 2 * Float.pi * Float(i) / 13
                return SIMD3(0, capBase + 0.052 + 0.02 * sin(angle), 0.02 * cos(angle))
            },
            radius: 0.004,
            sides: 6
        )

        let parts = [
            Part(geometry: ball, paint: .color(bauble, roughness: 0.14)),
            Part(geometry: band, paint: .metal(gold, roughness: 0.25)),
            Part(geometry: cap, paint: .metal(gold, roughness: 0.22)),
            Part(geometry: loop, paint: .metal(gold, roughness: 0.22))
        ]
        return MountainGearModel(parts: parts.map { Part(geometry: $0.geometry.scaled(by: scale), paint: $0.paint) })
    }

    // MARK: - January

    /// A tall party cone in gold with navy stripes and a pink pom-pom, tipped a jaunty angle.
    /// Authored from the head joint at rest.
    static func partyHat() -> MountainGearModel {
        let base = crown * 0.6, height: Float = 0.3, bottom: Float = 0.1
        func radius(at y: Float) -> Float { bottom * (1 - (y - base) / height) + 0.002 }

        let cone = MountainGearGeometry.lathe(profile: [
            SIMD2(bottom, base - 0.004), SIMD2(bottom * 0.5, base + height * 0.5), SIMD2(0, base + height)
        ], segments: 28)
        var stripes = MountainGearGeometry()
        for fraction in [0.0, 0.34, 0.68] as [Float] {
            let low = base + height * fraction, high = low + 0.045
            stripes.append(MountainGearGeometry.lathe(profile: [
                SIMD2(radius(at: low) + 0.003, low), SIMD2(radius(at: high) + 0.003, high)
            ], segments: 28))
        }
        let pom = MountainGearGeometry.sphere(radius: 0.034, segments: 14)
            .transformed(translation: SIMD3(0, base + height + 0.004, 0))

        let tilt = simd_quatf(angle: 0.2, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: -0.08, axis: SIMD3(1, 0, 0))
        return MountainGearModel(parts: [
            Part(geometry: cone.transformed(rotation: tilt), paint: .color(partyGold, roughness: 0.4)),
            Part(geometry: stripes.transformed(rotation: tilt), paint: .color(partyInk, roughness: 0.45)),
            Part(geometry: pom.transformed(rotation: tilt), paint: .color(partyPink, roughness: 0.8))
        ])
    }

    /// A lit sparkler held up on the shoulder: a thin wire and a starburst of gold sparks.
    static func sparkler() -> MountainGearModel {
        let length: Float = 0.34
        let wire = MountainGearGeometry.tube(
            path: [SIMD3(0, 0, 0), SIMD3(0, length * 0.5, 0), SIMD3(0, length, 0)],
            radius: 0.006,
            sides: 6
        )
        var sparks = MountainGearGeometry()
        let centre = SIMD3<Float>(0, length + 0.02, 0)
        let directions: [SIMD3<Float>] = (0..<14).map { i in
            let t = Float(i) / 13
            let phi = acos(1 - 2 * t)
            let theta = Float.pi * (1 + sqrt(5)) * Float(i)
            return SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
        }
        for (index, direction) in directions.enumerated() {
            let reach: Float = index.isMultiple(of: 2) ? 0.085 : 0.06
            let spark = MountainGearGeometry.box(size: SIMD3(0.007, 0.007, reach))
            let aim = simd_quatf(from: SIMD3(0, 0, 1), to: direction)
            sparks.append(spark.transformed(rotation: aim, translation: centre + direction * reach * 0.55))
        }
        return MountainGearModel(parts: [
            Part(geometry: wire, paint: .metal(sparklerWire, roughness: 0.35)),
            Part(geometry: sparks, paint: .metal(partyGold, roughness: 0.15))
        ])
    }

    /// A firework rocket standing on its fins: red body, a gold nose and blue fins.
    static func fireworksRocket() -> MountainGearModel {
        let radius: Float = 0.04, body: Float = 0.26
        let tube = MountainGearGeometry.lathe(profile: [
            SIMD2(0, 0.01), SIMD2(radius * 0.8, 0.012), SIMD2(radius, 0.04), SIMD2(radius, body), SIMD2(radius * 0.92, body + 0.004)
        ], segments: 24)
        let nose = MountainGearGeometry.lathe(profile: [
            SIMD2(radius * 0.96, body), SIMD2(radius * 0.7, body + 0.05), SIMD2(radius * 0.3, body + 0.095), SIMD2(0, body + 0.115)
        ], segments: 24)
        var fins = MountainGearGeometry()
        for i in 0..<3 {
            let angle = Float(i) * 2 * .pi / 3
            let fin = MountainGearGeometry.box(size: SIMD3(0.01, 0.085, 0.06))
                .transformed(translation: SIMD3(0, 0.05, radius + 0.022))
                .transformed(rotation: simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)))
            fins.append(fin)
        }
        let lean = simd_quatf(angle: -0.14, axis: SIMD3(0, 0, 1))
        return MountainGearModel(parts: [
            Part(geometry: tube.transformed(rotation: lean), paint: .color(rocketRed, roughness: 0.4)),
            Part(geometry: nose.transformed(rotation: lean), paint: .metal(partyGold, roughness: 0.25)),
            Part(geometry: fins.transformed(rotation: lean), paint: .color(rocketFin, roughness: 0.5))
        ])
    }

    /// A gold cup on a stem and foot, with a handle each side, on a dark plinth. Scaled, it is the
    /// giant pressed overhead: the gold is its first part, so the hands close round it.
    static func trophy(scale: Float = 1) -> MountainGearModel {
        let foot = MountainGearGeometry.lathe(profile: [
            SIMD2(0, 0), SIMD2(0.05, 0), SIMD2(0.05, 0.012), SIMD2(0.03, 0.026), SIMD2(0.014, 0.05),
            SIMD2(0.012, 0.1), SIMD2(0.026, 0.115), SIMD2(0.034, 0.13)
        ], segments: 24)
        var cup = MountainGearGeometry.lathe(profile: [
            SIMD2(0.034, 0.13), SIMD2(0.07, 0.15), SIMD2(0.088, 0.2), SIMD2(0.086, 0.26), SIMD2(0.092, 0.285), SIMD2(0.082, 0.288), SIMD2(0.076, 0.262)
        ], segments: 28).doubleSided()
        for side in [-1, 1] as [Float] {
            let path = (0..<10).map { i -> SIMD3<Float> in
                let t = Float(i) / 9
                let angle = Float.pi * (0.2 + 0.9 * t)
                return SIMD3(side * (0.088 + 0.05 * sin(angle)), 0.225 - 0.05 * cos(angle) * 1.1, 0)
            }
            cup.append(MountainGearGeometry.tube(path: path, radius: 0.007, sides: 8))
        }
        var gold = foot
        gold.append(cup)

        let plinth = MountainGearGeometry.box(size: SIMD3(0.1, 0.018, 0.1)).transformed(translation: SIMD3(0, -0.002, 0))
        let parts = [
            Part(geometry: gold, paint: .metal(Self.gold, roughness: 0.2)),
            Part(geometry: plinth, paint: .color(plinthDark, roughness: 0.6))
        ]
        return MountainGearModel(parts: parts.map { Part(geometry: $0.geometry.scaled(by: scale), paint: $0.paint) })
    }
}
