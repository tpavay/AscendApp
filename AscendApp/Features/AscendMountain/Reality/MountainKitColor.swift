import Foundation

/// Unlocked kit drawn on the athlete's own body: shorts or trainers in a colour that glows, worn
/// in place of the colour the climber picked. A colour rather than a print, because the shorts'
/// texture coordinates are cut small across seams and the trainers have none.
enum MountainKitColor {
    /// The item drawn on a body slot, as the athlete pack names its material slots.
    static func item(forSlot slot: String, look: AthleteLook) -> AthleteGear? {
        switch slot {
        case "bottom": look.shorts
        case "shoe": look.trainers
        default: nil
        }
    }

    /// The colour an item tints its slot.
    static func tint(_ item: AthleteGear) -> MountainColor {
        switch item {
        case .glowTrainers: MountainColor(hex: "#86D30A")!
        case .emberTrainers: MountainColor(hex: "#FF7A1A")!
        case .witchingShorts: MountainColor(hex: "#5B2A86")!
        default: MountainColor(red: 1, green: 1, blue: 1)
        }
    }

    /// How brightly an item glows on its own, 0 for none.
    static func glow(_ item: AthleteGear) -> Float {
        switch item {
        case .glowTrainers, .emberTrainers: 1.6
        case .witchingShorts: 0.35
        default: 0
        }
    }
}
