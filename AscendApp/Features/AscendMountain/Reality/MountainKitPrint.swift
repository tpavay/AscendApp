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
        case .spiderwebTank: spiderweb()
        case .pumpkinStripeTank: stripes()
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

    /// White webs on black, four across.
    private static func spiderweb() -> CGImage? {
        let size = 1024, tiles = 4
        guard let context = context(size) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.94, alpha: 1))
        let cell = CGFloat(size / tiles)
        for row in 0..<tiles {
            for column in 0..<tiles {
                let centre = CGPoint(x: (CGFloat(column) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
                context.setLineWidth(3)
                for spoke in 0..<8 {
                    let angle = CGFloat(spoke) * .pi / 4
                    context.move(to: centre)
                    context.addLine(to: CGPoint(x: centre.x + cos(angle) * cell * 0.5, y: centre.y + sin(angle) * cell * 0.5))
                }
                context.strokePath()
                context.setLineWidth(2)
                for ring in 1...4 {
                    let radius = CGFloat(ring) * cell * 0.11
                    for spoke in 0..<8 {
                        let a0 = CGFloat(spoke) * .pi / 4, a1 = CGFloat(spoke + 1) * .pi / 4
                        context.move(to: CGPoint(x: centre.x + cos(a0) * radius, y: centre.y + sin(a0) * radius))
                        context.addQuadCurve(
                            to: CGPoint(x: centre.x + cos(a1) * radius, y: centre.y + sin(a1) * radius),
                            control: CGPoint(x: centre.x + cos((a0 + a1) / 2) * radius * 0.86, y: centre.y + sin((a0 + a1) / 2) * radius * 0.86)
                        )
                    }
                }
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    /// Pumpkin orange and black bands.
    private static func stripes() -> CGImage? {
        let size = 512, bands = 18
        guard let context = context(size) else { return nil }
        for band in 0..<bands {
            let orange = band.isMultiple(of: 2)
            context.setFillColor(orange ? CGColor(srgbRed: 0.95, green: 0.5, blue: 0.08, alpha: 1) : CGColor(srgbRed: 0.07, green: 0.06, blue: 0.08, alpha: 1))
            context.fill(CGRect(x: 0, y: band * size / bands, width: size, height: size / bands))
        }
        return context.makeImage()
    }
}
