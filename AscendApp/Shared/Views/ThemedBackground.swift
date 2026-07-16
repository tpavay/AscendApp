//
//  ThemedBackground.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct ThemedBackground: View {
    var body: some View {
        Color.black
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
