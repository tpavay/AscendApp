//
//  VerticalClimbCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Standalone horizontal card displaying vertical climb with a triangle icon.
/// Supports PR-aware accent border.
struct VerticalClimbCard: View {
    let value: String
    let unit: String
    let isPR: Bool
    let effectiveColorScheme: ColorScheme

    private var borderColor: Color {
        isPR
            ? .accent.opacity(0.6)
            : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
    }

    private var borderWidth: CGFloat {
        isPR ? 1.5 : 1
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 28)

            Text("Vertical climb")
                .font(.montserratMedium(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.accent)

                Text(unit)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        VerticalClimbCard(value: "7,232.7", unit: "ft", isPR: true, effectiveColorScheme: .dark)
        VerticalClimbCard(value: "1,204.5", unit: "m", isPR: false, effectiveColorScheme: .dark)
    }
    .padding(20)
    .background(Color.black)
}
