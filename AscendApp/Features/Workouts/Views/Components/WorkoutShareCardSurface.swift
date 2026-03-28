//
//  WorkoutShareCardSurface.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import SwiftUI

struct WorkoutShareCardSurface<Content: View>: View {
    let surface: WorkoutShareCardPreset.Surface
    private let content: Content

    init(
        surface: WorkoutShareCardPreset.Surface,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        ZStack {
            background
            content
        }
        .clipShape(.rect(cornerRadius: surface.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: surface.cornerRadius)
                .stroke(.white.opacity(surface.borderOpacity), lineWidth: surface.borderWidth)
        }
        .contentShape(.rect(cornerRadius: surface.cornerRadius))
    }

    @ViewBuilder
    private var background: some View {
        switch surface.background {
        case .asset(let assetName):
            Image(assetName)
                .resizable()
                .scaledToFill()
        case .transparent:
            Color.clear
        }
    }
}
