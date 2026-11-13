//
//  HeroStatsPair.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Large side-by-side hero stats (duration + steps/floors) with a vertical divider.
struct HeroStatsPair: View {
    let leftLabel: String
    let leftValue: String
    let rightLabel: String
    let rightValue: String
    let effectiveColorScheme: ColorScheme
    /// Replaces the right-hand value with a dashed prompt, for a stat the climber has yet to give.
    var rightAction: Action?

    struct Action {
        let title: String
        let perform: () -> Void
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    var body: some View {
        HStack(spacing: 0) {
            statColumn(label: leftLabel, value: leftValue)

            // Vertical divider
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.3))
                .frame(width: 1, height: 36)

            if let rightAction {
                actionColumn(label: rightLabel, action: rightAction)
            } else {
                statColumn(label: rightLabel, value: rightValue)
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private func actionColumn(label: String, action: Action) -> some View {
        VStack(spacing: 4) {
            Button(action: action.perform) {
                Text("+ \(action.title)")
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                Color.accent.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
            }
            .buttonStyle(.plain)

            Text(label.uppercased())
                .font(.montserratMedium(size: 11))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
        }
        .frame(maxWidth: .infinity)
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
            effectiveColorScheme: .dark
        )

        HeroStatsPair(
            leftLabel: "Duration",
            leftValue: "30:00",
            rightLabel: "Floors",
            rightValue: "156",
            effectiveColorScheme: .dark
        )
    }
    .padding(20)
    .background(Color.black)
}
