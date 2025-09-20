//
//  ThemedBackground.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct ThemedBackground: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    var body: some View {
        Group {
            if effectiveColorScheme == .dark {
                LinearGradient(
                    colors: [.night, .jetLighter],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func themedBackground() -> some View {
        ZStack {
            ThemedBackground()
            self
        }
    }
}

#Preview("Dark Mode") {
    VStack {
        Text("Dark Mode Preview")
            .font(.title)
            .foregroundStyle(.white)
    }
    .themedBackground()
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VStack {
        Text("Light Mode Preview")
            .font(.title)
            .foregroundStyle(.black)
    }
    .themedBackground()
    .preferredColorScheme(.light)
}