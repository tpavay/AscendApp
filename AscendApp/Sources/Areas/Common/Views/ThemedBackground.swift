//
//  ThemedBackground.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct ThemedBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if colorScheme == .dark {
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