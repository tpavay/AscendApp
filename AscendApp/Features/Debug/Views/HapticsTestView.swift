//
//  HapticsTestView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import SwiftUI

#if DEBUG
struct HapticsTestView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Impact Haptics
                hapticSection(
                    title: "Impact Haptics",
                    subtitle: "Physical tap sensations of varying intensity",
                    haptics: [
                        ("Light Impact", "Subtle tap - good for minor interactions", .lightImpact),
                        ("Medium Impact", "Moderate tap - good for confirmations", .mediumImpact),
                        ("Heavy Impact", "Strong tap - good for major actions", .heavyImpact),
                    ]
                )
                
                // Selection Haptic
                hapticSection(
                    title: "Selection Haptic",
                    subtitle: "Designed for picker/selection changes",
                    haptics: [
                        ("Selection", "Crisp tick - good for toggles, pickers, sliders", .selection),
                    ]
                )
                
                // Notification Haptics
                hapticSection(
                    title: "Notification Haptics",
                    subtitle: "Communicates outcomes to the user",
                    haptics: [
                        ("Success", "Positive feedback - task completed", .success),
                        ("Warning", "Caution feedback - destructive actions", .warning),
                        ("Error", "Negative feedback - something failed", .error),
                    ]
                )
                
                // Combination Examples
                combinationSection
                
                Spacer(minLength: 40)
            }
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Haptics Test")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundStyle(.accent)
            
            Text("Test Haptic Feedback")
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("Tap each button to feel the haptic. Use this to decide which haptics work best for different interactions.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Haptic Section
    
    private func hapticSection(
        title: String,
        subtitle: String,
        haptics: [(name: String, description: String, type: HapticsManager.HapticType)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text(subtitle)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                ForEach(haptics, id: \.name) { haptic in
                    hapticButton(name: haptic.name, description: haptic.description, type: haptic.type)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func hapticButton(name: String, description: String, type: HapticsManager.HapticType) -> some View {
        Button {
            HapticsManager.shared.trigger(type)
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconForType(type))
                        .font(.system(size: 20))
                        .foregroundStyle(.accent)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(description)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.accent.opacity(0.6))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconForType(_ type: HapticsManager.HapticType) -> String {
        switch type {
        case .lightImpact: return "1.circle.fill"
        case .mediumImpact: return "2.circle.fill"
        case .heavyImpact: return "3.circle.fill"
        case .selection: return "checkmark.circle.fill"
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    // MARK: - Combination Section
    
    private var combinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Combinations")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Multi-haptic patterns for special moments")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                // Workout Complete (current)
                combinationButton(
                    name: "Workout Complete (Current)",
                    description: "Heavy impact → Success (100ms delay)",
                    action: {
                        HapticsManager.shared.trigger(.heavyImpact)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            HapticsManager.shared.trigger(.success)
                        }
                    }
                )
                
                // Double tap
                combinationButton(
                    name: "Double Tap",
                    description: "Two medium impacts in quick succession",
                    action: {
                        HapticsManager.shared.trigger(.mediumImpact)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            HapticsManager.shared.trigger(.mediumImpact)
                        }
                    }
                )
                
                // Celebration burst
                combinationButton(
                    name: "Celebration Burst",
                    description: "Triple light impacts → Success",
                    action: {
                        HapticsManager.shared.trigger(.lightImpact)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            HapticsManager.shared.trigger(.lightImpact)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            HapticsManager.shared.trigger(.lightImpact)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            HapticsManager.shared.trigger(.success)
                        }
                    }
                )
                
                // Rising intensity
                combinationButton(
                    name: "Rising Intensity",
                    description: "Light → Medium → Heavy",
                    action: {
                        HapticsManager.shared.trigger(.lightImpact)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            HapticsManager.shared.trigger(.mediumImpact)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            HapticsManager.shared.trigger(.heavyImpact)
                        }
                    }
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func combinationButton(name: String, description: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "waveform.path")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(description)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.purple.opacity(0.6))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HapticsTestView()
    }
}
#endif

