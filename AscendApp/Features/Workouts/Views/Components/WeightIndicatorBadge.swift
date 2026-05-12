//
//  WeightIndicatorBadge.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/29/25.
//

import SwiftUI

/// Small badge indicator showing that weights were used in a workout
/// Used in the workout list view as a subtle indicator
struct WeightIndicatorBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let size: BadgeSize

    enum BadgeSize {
        case small  // For list view (14x14)
        case medium // For detail view (18x18)

        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 18
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            }
        }
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(size: BadgeSize = .small) {
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background capsule
            RoundedRectangle(cornerRadius: size.iconSize / 2 + size.padding)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.12))

            // Icon
            weightIcon
                .frame(width: size.iconSize, height: size.iconSize)
        }
        .frame(width: size.iconSize + size.padding * 2, height: size.iconSize + size.padding * 2)
    }

    @ViewBuilder
    private var weightIcon: some View {
        // Try custom icon first, fall back to SF Symbol
        if let _ = UIImage(named: "weight-generic") {
            Image("weight-generic")
                .resizable()
                .scaledToFit()
        } else {
            // Fallback to dumbbell SF Symbol
            Image(systemName: "dumbbell.fill")
                .font(.system(size: size.iconSize * 0.7, weight: .medium))
                .foregroundStyle(.accent)
        }
    }
}

// MARK: - Preview

#Preview("Weight Badge Sizes") {
    HStack(spacing: 20) {
        VStack {
            WeightIndicatorBadge(size: .small)
            Text("Small")
                .font(.caption)
        }

        VStack {
            WeightIndicatorBadge(size: .medium)
            Text("Medium")
                .font(.caption)
        }
    }
    .padding()
    .background(Color.jet)
    .preferredColorScheme(.dark)
}

#Preview("In Context") {
    // Simulating how it looks in the workout list row
    HStack {
        Text("2,029 steps")
            .font(.montserratSemiBold(size: 18))

        Text("20:13")
            .font(.montserratRegular(size: 14))

        Text("100 spm")
            .font(.montserratRegular(size: 14))

        Spacer()

        WeightIndicatorBadge(size: .small)

        // Adjacent badge simulation
        HStack(spacing: 2) {
            Text("8")
                .font(.montserratSemiBold(size: 12))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.accent.opacity(0.2))
        )
    }
    .padding()
    .background(Color.jet)
    .preferredColorScheme(.dark)
}
