//
//  ThemeManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private init() {}

    var preferredColorScheme: ColorScheme {
        .dark
    }

    func effectiveColorScheme(for _: ColorScheme) -> ColorScheme {
        .dark
    }
}
