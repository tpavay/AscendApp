//
//  StepConfigurationExplanationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import SwiftUI

struct StepConfigurationExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Introduction
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step Configuration")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Configure your stair stepper settings for accurate climb calculations. These values help convert between steps, floors, and vertical distance.")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Step Height Section
                    VStack(alignment: .leading, spacing: 16) {
                        configurationItem(
                            icon: "arrow.up.and.down",
                            title: "Step Height",
                            description: "The height of each individual step on your stair stepper machine. This measurement is used to calculate your total vertical climb distance. Most stair steppers have adjustable step heights, typically ranging from 4-15 inches (10-38 cm).",
                            tip: "Check your machine's settings or manual to find the exact step height, or measure from the top of one step to the top of the next."
                        )
                        
                        configurationItem(
                            icon: "figure.stairs",
                            title: "Steps Per Floor",
                            description: "The number of individual steps that equal one floor on your stair stepper. This setting is used to convert your step count to floors for easier tracking and comparison.",
                            tip: "A typical floor in a building is about 10-12 feet high, which usually equals 16-20 steps depending on your machine's step height."
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // How It's Used Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How These Settings Are Used")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        usageItem(
                            icon: "ruler",
                            title: "Vertical Distance",
                            description: "Step height × total steps = your vertical climb distance."
                        )
                        
                        usageItem(
                            icon: "building.2.fill",
                            title: "Floor Conversion",
                            description: "Total steps ÷ steps per floor = floors climbed."
                        )
                        
                        usageItem(
                            icon: "clock.arrow.circlepath",
                            title: "Per-Workout Storage",
                            description: "These values are saved with each workout, so changing settings later won't affect past workouts."
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                }
            }
        }
    }
    
    private func configurationItem(icon: String, title: String, description: String, tip: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.accent.opacity(0.8), .accent]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                
                Text(title)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            
            Text(description)
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                .fixedSize(horizontal: false, vertical: true)
            
            // Tip callout
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.yellow)
                
                Text(tip)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(effectiveColorScheme == .dark ? .yellow.opacity(0.1) : .yellow.opacity(0.15))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func usageItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.accent.opacity(0.8), .accent]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    StepConfigurationExplanationView()
}

#Preview("Dark Mode") {
    StepConfigurationExplanationView()
        .preferredColorScheme(.dark)
}

