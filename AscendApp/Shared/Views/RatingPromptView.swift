//
//  RatingPromptView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI

/// Custom rating prompt shown before the system App Store review dialog
/// Inspired by Partiful's personal approach to rating requests
struct RatingPromptView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    let onRateUs: () -> Void
    let onNotNow: () -> Void
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Emoji header
            Text("🏔️")
                .font(.system(size: 60))
            
            // Personal message
            VStack(spacing: 12) {
                Text("Enjoying Ascend?")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Hey! I'm Tyler, the developer behind Ascend. I built this app because I couldn't find a workout tracker that truly understood stairstepper training.\n\nIf Ascend has helped you crush your fitness goals, would you mind leaving a quick review? It really helps other fitness enthusiasts discover the app.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    HapticsManager.shared.trigger(.selection)
                    onRateUs()
                }) {
                    Text("Rate Ascend ⭐")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    HapticsManager.shared.trigger(.selection)
                    onNotNow()
                }) {
                    Text("Maybe Later")
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? Color.jetLighter : Color.white)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 32)
    }
}

/// Full-screen overlay for the rating prompt
struct RatingPromptOverlay: View {
    @Binding var isPresented: Bool
    let onRateUs: () -> Void
    var onNotNow: (() -> Void)? = nil
    
    var body: some View {
        if isPresented {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Dismiss on background tap (counts as "not now")
                        withAnimation(.spring(response: 0.3)) {
                            isPresented = false
                        }
                        onNotNow?()
                    }
                
                // Prompt card
                RatingPromptView(
                    onRateUs: {
                        withAnimation(.spring(response: 0.3)) {
                            isPresented = false
                        }
                        // Small delay to let animation complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onRateUs()
                        }
                    },
                    onNotNow: {
                        withAnimation(.spring(response: 0.3)) {
                            isPresented = false
                        }
                        onNotNow?()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: isPresented)
        }
    }
}

#Preview {
    RatingPromptView(
        onRateUs: { print("Rate us tapped") },
        onNotNow: { print("Not now tapped") }
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Dark Mode") {
    RatingPromptView(
        onRateUs: { print("Rate us tapped") },
        onNotNow: { print("Not now tapped") }
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Overlay") {
    ZStack {
        Color.blue
            .ignoresSafeArea()
        
        RatingPromptOverlay(
            isPresented: .constant(true),
            onRateUs: { print("Rate us!") }
        )
    }
}
