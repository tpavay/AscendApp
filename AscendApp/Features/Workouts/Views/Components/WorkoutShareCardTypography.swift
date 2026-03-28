//
//  WorkoutShareCardTypography.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import SwiftUI

enum WorkoutShareCardTypography {
    // Swap these font names when a licensed display face is added to the bundle.
    private enum FontFamily {
        static let overline = "Montserrat-SemiBold"
        static let label = "Montserrat-Bold"
        static let value = "Montserrat-SemiBold"
        static let display = "Montserrat-Bold"
    }

    static func font(for style: WorkoutShareCardTextStyle) -> Font {
        switch style.token {
        case .overline:
            return Font.custom(FontFamily.overline, size: style.size)
        case .label:
            return Font.custom(FontFamily.label, size: style.size)
        case .value:
            return Font.custom(FontFamily.value, size: style.size)
        case .display:
            return Font.custom(FontFamily.display, size: style.size)
        }
    }
}
