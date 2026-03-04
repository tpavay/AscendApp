//
//  LeaderboardHeroBackground.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardHeroBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(gradient)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.accent.opacity(colorScheme == .dark ? 0.18 : 0.11))
                    .blur(radius: 54)
                    .frame(width: 170, height: 170)
                    .offset(x: 34, y: -36)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.night.opacity(colorScheme == .dark ? 0.5 : 0.12))
                    .blur(radius: 66)
                    .frame(width: 220, height: 220)
                    .offset(x: -58, y: 40)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(colorScheme == .dark ? .white.opacity(0.04) : .black.opacity(0.05))
                    .frame(height: 1)
            }
    }

    private var gradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [.night, .jetLighter, .night],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [.white, Color.accent.opacity(0.08), Color.gray.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

