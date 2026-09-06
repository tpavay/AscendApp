//
//  Color+Extension.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/9/25.
//

import SwiftUI

extension Color {
    static var ascendAccent: Color {
        Color(
            uiColor: UIColor(
                named: "AccentColor",
                in: .main,
                compatibleWith: nil
            ) ?? UIColor(red: 134 / 255, green: 211 / 255, blue: 10 / 255, alpha: 1)
        )
    }

    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex string (with or without #, supports 3, 6, or 8 characters)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func darker(by amount: CGFloat) -> Color {
            let ui = UIColor(self)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return Color(.sRGB,
                         red: max(r - amount, 0),
                         green: max(g - amount, 0),
                         blue: max(b - amount, 0),
                         opacity: a)
        }

    func lighter(by amount: CGFloat) -> Color {
            let ui = UIColor(self)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return Color(.sRGB,
                         red: min(r + amount, 1),
                         green: min(g + amount, 1),
                         blue: min(b + amount, 1),
                         opacity: a)
        }

    /// Custom gray colors
    static let customGray = Color(hex: "888888")
    static let darkGray = Color(hex: "333333")

    /// The caution token: a climber's own work that has not reached their account.
    ///
    /// Deliberately not the lime accent, which means "earned", and not red, which the app uses for
    /// destructive actions. Amber is the captain's call; this exact value is still the design
    /// board's proposal (`design-ascend-backup-failure-surface`) and is the one visual detail he
    /// has not confirmed, so it lives here as a single token to change rather than a literal
    /// scattered across the surface.
    static let ascendCaution = Color(hex: "FF9F0A")

    /// The gold medal token from the core project guide, reserved for
    /// podium and rank-prestige moments. Applied sparingly, never as a primary
    /// surface colour - today the First Ascent claim on a completion summary.
    static let ascendMedalGold = Color(hex: "D4AF37")
    
    // MARK: - Workout Intensity Colors
    
    /// Returns a gradient for workout intensity
    /// Uses lighter/darker versions of the yellow-orange gradient
    static func intensityGradient(for intensity: IntensityTier, colorScheme: ColorScheme) -> LinearGradient {
        let colors = intensityColors(for: intensity, colorScheme: colorScheme)
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Returns the color pair for a given intensity level
    static func intensityColors(for intensity: IntensityTier, colorScheme: ColorScheme) -> [Color] {
        switch intensity {
        case .minimal:
            // Lightest - very subtle gradient (keeping as is)
            return [
                Color(red: 1.0, green: 0.95, blue: 0.7),   // Very light yellow
                Color(red: 1.0, green: 0.9, blue: 0.6)     // Light yellow-orange
            ]
            
        case .light:
            // Light - more saturated yellow
            return [
                Color(red: 1.0, green: 0.9, blue: 0.3),    // Brighter yellow
                Color(red: 1.0, green: 0.8, blue: 0.2)     // Yellow-orange
            ]
            
        case .moderate:
            // Moderate - clear orange gradient
            return [
                Color(red: 1.0, green: 0.75, blue: 0.1),   // Golden yellow
                Color(red: 1.0, green: 0.55, blue: 0.0)    // Orange
            ]
            
        case .high:
            // Hard - deep orange to red-orange
            return [
                Color(red: 1.0, green: 0.55, blue: 0.0),   // Deep orange
                Color(red: 1.0, green: 0.3, blue: 0.0)     // Red-orange
            ]
            
        case .maximum:
            // Very Hard - orange to deep red
            return [
                Color(red: 1.0, green: 0.4, blue: 0.0),    // Bright red-orange
                Color(red: 0.9, green: 0.0, blue: 0.0)     // Deep red
            ]
        }
    }
}
