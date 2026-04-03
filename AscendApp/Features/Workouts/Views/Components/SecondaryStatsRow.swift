//
//  SecondaryStatsRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// A data item for the secondary stats row.
struct SecondaryStatItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let isPR: Bool
}

/// Compact row of 1–3 secondary stat cards (pace, calories, METs).
/// Each card supports PR-aware accent borders.
struct SecondaryStatsRow: View {
    let items: [SecondaryStatItem]
    let effectiveColorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                secondaryStatCard(item: item)
            }
        }
    }

    private func secondaryStatCard(item: SecondaryStatItem) -> some View {
        let borderColor: Color = item.isPR
            ? .accent.opacity(0.6)
            : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
        let borderWidth: CGFloat = item.isPR ? 1.5 : 1

        return VStack(spacing: 4) {
            Text(item.value)
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(item.label.uppercased())
                .font(.montserratMedium(size: 10))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        )
    }
}

#Preview {
    SecondaryStatsRow(
        items: [
            SecondaryStatItem(label: "Steps/Min", value: "90.1", isPR: true),
            SecondaryStatItem(label: "Calories", value: "1,692", isPR: false),
            SecondaryStatItem(label: "METs", value: "10.3", isPR: false)
        ],
        effectiveColorScheme: .dark
    )
    .padding(20)
    .background(Color.black)
}
