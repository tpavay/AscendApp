//
//  StatTile.swift
//  AscendApp
//

import SwiftUI

/// A single stat tile with value + label for celebration surfaces.
struct StatTile: View {
    let value: Int
    let label: String
    let iconName: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var tileFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06)
    }

    private var tileStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.accent)
                .frame(height: 20)

            Text(value, format: .number)
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(label)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(tileStroke, lineWidth: 1)
                )
        )
    }
}
