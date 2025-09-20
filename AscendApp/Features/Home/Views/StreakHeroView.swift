//
//  StreakHeroView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct StreakHeroView: View {
    let currentStreak: Int
    let showMyProgressButton: Bool
    let onMyProgressTap: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(currentStreak: Int, showMyProgressButton: Bool = false, onMyProgressTap: (() -> Void)? = nil) {
        self.currentStreak = currentStreak
        self.showMyProgressButton = showMyProgressButton
        self.onMyProgressTap = onMyProgressTap
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack() {
                // Main flame icon
                Image(systemName: "flame.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.yellow, .orange, .red]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )


                // Streak number next to flame
                Text("\(currentStreak)")
                    .font(.montserratBold)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.yellow, .orange]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    // "DAY STREAK" text
                    Text("DAY STREAK")
                        .font(.montserratBold(size: 14))
                        .tracking(1.5)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.yellow, .orange]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    // Description
                    Text("Days in a row you completed workouts")
                        .font(.montserratSemiBold(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                        .multilineTextAlignment(.center)


                }


                if showMyProgressButton, let onMyProgressTap = onMyProgressTap {
                    myProgressButton(action: onMyProgressTap)
                }
            }
                    }
    }
    
    private func myProgressButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("My Progress")
                    .font(.montserratSemiBold(size: 12))

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.yellow, .orange]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 40) {
        // Without My Progress button
        StreakHeroView(currentStreak: 7)
        
        // With My Progress button
        StreakHeroView(
            currentStreak: 101,
            showMyProgressButton: true,
            onMyProgressTap: {
                print("My Progress tapped")
            }
        )
    }
    .themedBackground()
}

#Preview("Dark Mode") {
    VStack(spacing: 40) {
        StreakHeroView(currentStreak: 0)
        
        StreakHeroView(
            currentStreak: 42,
            showMyProgressButton: true,
            onMyProgressTap: {}
        )
    }
    .themedBackground()
    .preferredColorScheme(.dark)
}
