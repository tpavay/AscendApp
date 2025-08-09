//
//  Color+Extension.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/9/25.
//

import SwiftUI

extension Color {
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

    /// Custom gray colors
    static let customGray = Color(hex: "888888")
    static let darkGray = Color(hex: "333333")
}
