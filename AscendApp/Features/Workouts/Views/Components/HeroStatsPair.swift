//
//  HeroStatsPair.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Large side-by-side hero stats (duration + steps/floors) with a vertical divider.
/// Supports PR-aware accent border when either stat is a personal record.
struct HeroStatsPair: View {
    let leftLabel: String
    let leftValue: String
    let rightLabel: String
    let rightValue: String
    let leftIsPR: Bool
    let rightIsPR: Bool
    let effectiveColorScheme: ColorScheme

    private var hasPR: Bool {
        leftIsPR || rightIsPR
    }

    private var borderColor: Color {
        hasPR
            ? .accent.opacity(0.6)
            : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
    }

    private var borderWidth: CGFloat {
        hasPR ? 1.5 : 1
    }

    var body: some View {
        HStack(spacing: 0) {
            statColumn(label: leftLabel, value: leftValue)

            // Vertical divider
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.3))
                .frame(width: 1, height: 36)

            statColumn(label: rightLabel, value: rightValue)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        )
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label.uppercased())
                .font(.montserratMedium(size: 11))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 16) {
        HeroStatsPair(
            leftLabel: "Duration",
            leftValue: "2:00:22",
            rightLabel: "Steps",
            rightValue: "10,849",
            leftIsPR: false,
            rightIsPR: true,
            effectiveColorScheme: .dark
        )

        HeroStatsPair(
            leftLabel: "Duration",
            leftValue: "30:00",
            rightLabel: "Floors",
            rightValue: "156",
            leftIsPR: false,
            rightIsPR: false,
            effectiveColorScheme: .dark
        )
    }
    .padding(20)
    .background(Color.black)
}
