//
//  ThemeAwareModifier.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct ThemeAwareModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(effectiveColorScheme)
    }
}

extension View {
    func themeAware() -> some View {
        modifier(ThemeAwareModifier())
    }
}