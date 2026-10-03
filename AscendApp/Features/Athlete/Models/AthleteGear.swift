import Foundation

/// An item an athlete carries or wears up Ascend Mountain, earned by climbing. Like the rest of a
/// look, every item is a preset, so there is nothing to moderate. An athlete has at most one item
/// in each slot: one carried, one on the head, one costume.
enum AthleteGear: String, Codable, CaseIterable, Identifiable, Sendable {
    // Halloween
    case pumpkinClassic = "pumpkin_classic"
    case pumpkinGhost = "pumpkin_ghost"
    case pumpkinLantern = "pumpkin_lantern"
    case pumpkinHeirloom = "pumpkin_heirloom"
    case pumpkinMidnight = "pumpkin_midnight"
    case pumpkinGiant = "pumpkin_giant"
    case pumpkinGiantLantern = "pumpkin_giant_lantern"
    case witchHat = "witch_hat"
    case pumpkinHead = "pumpkin_head"
    case ghostSheet = "ghost_sheet"
    case candyCorn = "candy_corn"
    case chocolateBar = "chocolate_bar"
    case witchingShorts = "witching_shorts"
    case glowTrainers = "glow_trainers"
    case emberTrainers = "ember_trainers"
    // Thanksgiving
    case harvestGourd = "harvest_gourd"
    case cornucopia
    case roastTurkey = "roast_turkey"
    case pumpkinPie = "pumpkin_pie"
    case goldenTurkey = "golden_turkey"
    case turkeyGiant = "turkey_giant"

    var id: String { rawValue }

    /// Where on the athlete an item goes.
    enum Slot: String, Codable, CaseIterable, Sendable {
        /// Held up the mountain: on the shoulder, or overhead.
        case carry
        /// On the head.
        case head
        /// Over the whole athlete.
        case costume
        /// The shorts and the trainers: kit lit for the season, worn in place of the colour the
        /// climber picked.
        case shorts
        case trainers
    }

    /// Whether the item is a shape of its own on the athlete, rather than kit drawn on the body.
    var isWornShape: Bool {
        [.carry, .head, .costume].contains(slot)
    }

    var slot: Slot {
        switch self {
        case .witchHat, .pumpkinHead: .head
        case .ghostSheet: .costume
        case .witchingShorts: .shorts
        case .glowTrainers, .emberTrainers: .trainers
        default: .carry
        }
    }

    /// How the athlete holds a carried item: perched on the right shoulder with the left arm still swinging,
    /// or a giant pressed overhead with both. Tucked under the arm was tried first and hid the
    /// item behind the climber from the race camera, which films from behind.
    enum Carry: String, Sendable {
        case shoulder
        case overhead
        /// Flat on the right palm, forearm level, like a waiter's tray: a pie.
        case tray
    }

    var carry: Carry {
        switch self {
        case .pumpkinGiant, .pumpkinGiantLantern, .turkeyGiant: .overhead
        case .pumpkinPie, .chocolateBar, .cornucopia: .tray
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
        case .pumpkinGiant: "The Giant"
        case .pumpkinGiantLantern: "Giant Jack-o'-Lantern"
        case .witchHat: "Witch Hat"
        case .pumpkinHead: "Pumpkin Head"
        case .ghostSheet: "Ghost Sheet"
        case .candyCorn: "Candy Corn"
        case .chocolateBar: "Chocolate Bar"
        case .witchingShorts: "Witching Hour Shorts"
        case .glowTrainers: "Glow Trainers"
        case .emberTrainers: "Ember Trainers"
        case .harvestGourd: "Harvest Gourd"
        case .cornucopia: "Cornucopia"
        case .roastTurkey: "Roast Turkey"
        case .pumpkinPie: "Pumpkin Pie"
        case .goldenTurkey: "Golden Turkey"
        case .turkeyGiant: "Giant Turkey"
        }
    }
}
