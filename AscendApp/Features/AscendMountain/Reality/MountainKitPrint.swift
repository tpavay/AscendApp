import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Unlocked kit drawn on the athlete's own body: a tank printed for the season, shorts or
/// trainers in a colour that glows. The tank's texture coordinates are a clean sheet, so a print
/// tiles across it; the shorts' are cut small across seams and the trainers have none, so theirs
/// is a colour and a glow.
enum MountainKitPrint {
    /// The body slot an item is drawn on, as the athlete pack names its material slots.
    static func item(forSlot slot: String, look: AthleteLook) -> AthleteGear? {
        switch slot {
        case "top": look.tank
        case "bottom": look.shorts
        case "shoe": look.trainers
        default: nil
        }
    }

    /// The colour a printed or lit item tints its slot.
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

    /// The print tiled across the item, or nil for a plain colour.
    static func image(_ item: AthleteGear) -> CGImage? {
        switch item {
        case .candyCornTank: candyCorn()
        default: nil
        }
    }

    private static func context(_ size: Int) -> CGContext? {
        CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Candy corn's three bands, white at the shoulders, orange through the chest, yellow at the
    /// hem, softened where they meet.
    private static func candyCorn() -> CGImage? {
        let size = 256
        guard let context = context(size) else { return nil }
        let colors = [
            CGColor(srgbRed: 0.98, green: 0.78, blue: 0.12, alpha: 1),
            CGColor(srgbRed: 0.98, green: 0.78, blue: 0.12, alpha: 1),
            CGColor(srgbRed: 0.96, green: 0.48, blue: 0.08, alpha: 1),
            CGColor(srgbRed: 0.96, green: 0.48, blue: 0.08, alpha: 1),
            CGColor(srgbRed: 0.98, green: 0.96, blue: 0.9, alpha: 1),
            CGColor(srgbRed: 0.98, green: 0.96, blue: 0.9, alpha: 1)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.3, 0.36, 0.66, 0.72, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
        return context.makeImage()
    }
}
