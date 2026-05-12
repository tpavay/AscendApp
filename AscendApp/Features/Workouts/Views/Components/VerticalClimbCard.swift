//
//  VerticalClimbCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Standalone horizontal card displaying vertical climb with a triangle icon.
struct VerticalClimbCard: View {
    let value: String
    let unit: String
    let effectiveColorScheme: ColorScheme

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 28)

            Text("Vertical climb")
                .font(.montserratMedium(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(primaryTextColor)

                Text(unit)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        VerticalClimbCard(value: "7,232.7", unit: "ft", effectiveColorScheme: .dark)
        VerticalClimbCard(value: "1,204.5", unit: "m", effectiveColorScheme: .dark)
    }
    .padding(20)
    .background(Color.black)
}
