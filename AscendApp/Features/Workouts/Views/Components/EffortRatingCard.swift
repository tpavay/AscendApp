//
//  EffortRatingCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Displays the workout effort rating as a horizontal stat card.
struct EffortRatingCard: View {
    let rating: Double
    let effectiveColorScheme: ColorScheme

    private var description: String {
        switch Int(rating) {
        case 1: return "Minimal"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Maximum"
        default: return "Moderate"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Effort Rating")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(rating))/5")
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text(description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        EffortRatingCard(rating: 4.0, effectiveColorScheme: .dark)
        EffortRatingCard(rating: 2.0, effectiveColorScheme: .dark)
    }
    .padding(20)
    .background(Color.black)
}
