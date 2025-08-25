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
    
    private let themeKey = "selectedTheme"
    
    var selectedTheme: AppTheme {
        didSet {
            saveTheme()
        }
    }
    
    private init() {
        // Load saved theme or default to system
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .system
        }
    }
    
    private func saveTheme() {
        UserDefaults.standard.set(selectedTheme.rawValue, forKey: themeKey)
        UserDefaults.standard.synchronize()
    }
    
    func effectiveColorScheme(for systemScheme: ColorScheme) -> ColorScheme {
        return selectedTheme.colorScheme(for: systemScheme)
    }
    
    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTheme = theme
        }
    }
}