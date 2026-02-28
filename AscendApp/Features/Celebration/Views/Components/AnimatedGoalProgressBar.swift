//
//  AnimatedGoalProgressBar.swift
//  AscendApp
//

import SwiftUI

struct AnimatedGoalProgressBar: View {
    let progress: Double
    var onCrossedGoal: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var didFireCrossingCallback = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 6)
                    .fill(.accent)
                    .frame(width: geometry.size.width * clampedProgress, height: 12)
            }
        }
        .frame(height: 12)
        .onChange(of: progress) { oldValue, newValue in
            guard oldValue < 1.0, newValue >= 1.0, !didFireCrossingCallback else { return }
            didFireCrossingCallback = true
            onCrossedGoal?()
        }
        .onAppear {
            didFireCrossingCallback = progress >= 1.0
        }
    }
}
