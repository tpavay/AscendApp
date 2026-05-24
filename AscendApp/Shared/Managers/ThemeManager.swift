//
//  ThemeManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private init() {}

    func effectiveColorScheme(for _: ColorScheme) -> ColorScheme {
        .dark
    }
}
