import Foundation

/// How a climber's athlete looks on Ascend Mountain. Every field is one of the editor's preset
/// options, so there is no text or image to moderate. Stored at `users/{uid}/athlete_look/current`
/// (`firestore.rules` lists the same options) and drawn wherever the climber races, including on
/// other climbers' stairs.
struct AthleteLook: Codable, Hashable, Sendable {
    /// The two bodies of the athlete pack, named neutrally in the editor.
    enum Body: String, Codable, CaseIterable, Identifiable, Sendable {
        case a
        case b

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }

        /// The body's hairstyle a new athlete starts with.
        var firstHairStyle: HairStyle {
            switch self {
            case .a: .parted
            case .b: .long
            }
        }
    }

    /// Light to dark. The athlete pack bakes one skin texture per tone whose average is exactly
    /// the swatch (`scripts/athlete/build-ascend-athlete.py` holds the same list).
    enum SkinTone: String, Codable, CaseIterable, Identifiable, Sendable {
        case tone1, tone2, tone3, tone4, tone5, tone6

        var id: String { rawValue }

        var color: MountainColor {
            switch self {
            case .tone1: MountainColor(hex: "#F3D2B8")!
            case .tone2: MountainColor(hex: "#E2B08C")!
            case .tone3: MountainColor(hex: "#C68C62")!
            case .tone4: MountainColor(hex: "#9B6640")!
            case .tone5: MountainColor(hex: "#6E4428")!
            case .tone6: MountainColor(hex: "#452818")!
            }
        }
    }

    enum HairStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case parted, long, buns, buzzed, short

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum HairColor: String, Codable, CaseIterable, Identifiable, Sendable {
        case black
        case darkBrown = "dark_brown"
        case brown
        case blond
        case red
        case grey

        var id: String { rawValue }

        var color: MountainColor {
            switch self {
            case .black: MountainColor(hex: "#0D0A08")!
            case .darkBrown: MountainColor(hex: "#4A2C17")!
            case .brown: MountainColor(hex: "#8A5A2B")!
            case .blond: MountainColor(hex: "#D8B064")!
            case .red: MountainColor(hex: "#B9442A")!
            case .grey: MountainColor(hex: "#C9C9C9")!
            }
        }
    }

    /// One palette for the tank, the shorts and the trainers.
    enum KitColor: String, Codable, CaseIterable, Identifiable, Sendable {
        case lime, white, blue, pink, orange, black

        var id: String { rawValue }

        var color: MountainColor {
            switch self {
            case .lime: MountainColor(hex: "#86D30A")!
            case .white: MountainColor(hex: "#E4E4E4")!
            case .blue: MountainColor(hex: "#1F6FD8")!
            case .pink: MountainColor(hex: "#E0457B")!
            case .orange: MountainColor(hex: "#F28A1C")!
            case .black: MountainColor(hex: "#1D1F24")!
            }
        }
    }

    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case slim, regular, solid, big

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Muscle: String, Codable, CaseIterable, Identifiable, Sendable {
        case smooth, some, defined

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: Body
    var skinTone: SkinTone
    var hairStyle: HairStyle
    var hairColor: HairColor
    var top: KitColor
    var bottom: KitColor
    var shoes: KitColor
    var size: Size
    var muscle: Muscle

    /// The athlete a climber starts with, from the onboarding gender answer (captain, round 8):
    /// the body the answer suggests - body A for any answer that names none - a middle skin tone,
    /// that body's first hairstyle in dark brown, the Ascend kit, Regular and Some.
    static func starting(for gender: ProfileGender?) -> AthleteLook {
        let body: Body = gender == .woman ? .b : .a
        return AthleteLook(
            body: body,
            skinTone: .tone3,
            hairStyle: body.firstHairStyle,
            hairColor: .darkBrown,
            top: .lime,
            bottom: .black,
            shoes: .white,
            size: .regular,
            muscle: .some
        )
    }

    /// Changes the body and, when the current hairstyle was simply the old body's first one, moves
    /// it to the new body's, so switching body in the editor does not strand a default.
    func switching(to body: Body) -> AthleteLook {
        var look = self
        if hairStyle == self.body.firstHairStyle {
            look.hairStyle = body.firstHairStyle
        }
        look.body = body
        return look
    }

    /// A look for another climber until their own is read, or for one who never saved one:
    /// preset choices picked by their id, so the same climber always looks the same. Lime is the
    /// climber's own kit colour on their stairs, so no stand-in wears a lime tank.
    static func standIn(for id: String) -> AthleteLook {
        var hash = id.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 }
        func pick<Option: CaseIterable>(_ options: Option.Type, excluding excluded: [Option] = []) -> Option where Option: Equatable {
            let choices = Array(options.allCases).filter { !excluded.contains($0) }
            let choice = choices[Int(hash % UInt64(choices.count))]
            hash /= UInt64(choices.count)
            hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return choice
        }
        return AthleteLook(
            body: pick(Body.self),
            skinTone: pick(SkinTone.self),
            hairStyle: pick(HairStyle.self),
            hairColor: pick(HairColor.self),
            top: pick(KitColor.self, excluding: [.lime]),
            bottom: pick(KitColor.self, excluding: [.lime, .pink, .orange]),
            shoes: pick(KitColor.self),
            size: pick(Size.self),
            muscle: pick(Muscle.self)
        )
    }
}
