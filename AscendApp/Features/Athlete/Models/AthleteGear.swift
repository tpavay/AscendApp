import Foundation

/// A seasonal item an athlete carries up Ascend Mountain, earned by climbing during its season.
/// Like the rest of a look, every item is a preset, so there is nothing to moderate. An athlete
/// carries one at a time.
enum AthleteGear: String, Codable, CaseIterable, Identifiable, Sendable {
    // Halloween
    case pumpkinClassic = "pumpkin_classic"
    case pumpkinGhost = "pumpkin_ghost"
    case pumpkinLantern = "pumpkin_lantern"
    case pumpkinHeirloom = "pumpkin_heirloom"
    case pumpkinMidnight = "pumpkin_midnight"
    case pumpkinGiant = "pumpkin_giant"
    // Thanksgiving
    case harvestGourd = "harvest_gourd"
    case cornucopia
    case roastTurkey = "roast_turkey"
    case pumpkinPie = "pumpkin_pie"
    case goldenTurkey = "golden_turkey"
    case turkeyGiant = "turkey_giant"

    var id: String { rawValue }

    /// How the athlete holds it: perched on the right shoulder with the left arm still swinging,
    /// or a giant pressed overhead with both. Tucked under the arm was tried first and hid the
    /// item behind the climber from the race camera, which films from behind.
    enum Carry: String, Sendable {
        case shoulder
        case overhead
    }

    var carry: Carry {
        switch self {
        case .pumpkinGiant, .turkeyGiant: .overhead
        default: .shoulder
        }
    }

    var title: String {
        switch self {
        case .pumpkinClassic: "Pumpkin"
        case .pumpkinGhost: "Ghost Pumpkin"
        case .pumpkinLantern: "Jack-o'-Lantern"
        case .pumpkinHeirloom: "Heirloom Pumpkin"
        case .pumpkinMidnight: "Midnight Pumpkin"
        case .pumpkinGiant: "Giant Pumpkin"
        case .harvestGourd: "Harvest Gourd"
        case .cornucopia: "Cornucopia"
        case .roastTurkey: "Roast Turkey"
        case .pumpkinPie: "Pumpkin Pie"
        case .goldenTurkey: "Golden Turkey"
        case .turkeyGiant: "Giant Turkey"
        }
    }
}
