//
//  IntensityExplanationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import SwiftUI

struct IntensityExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Introduction
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How We Calculate Intensity")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Your workout intensity is calculated using multiple data points to give you the most accurate representation of your effort level.")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Priority Explanation
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Calculation Priority")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        priorityItem(
                            number: 1,
                            title: "Your Effort Rating",
                            description: "If you manually enter an effort rating (1-5 scale), we use that as the primary indicator since you know your body best."
                        )
                        
                        priorityItem(
                            number: 2,
                            title: "Heart Rate Data",
                            description: "Heart rate is the most reliable physiological indicator of intensity. Higher heart rates indicate harder effort."
                        )
                        
                        priorityItem(
                            number: 3,
                            title: "Apple Health Intensity",
                            description: "If available, we factor in the METs (Metabolic Equivalent of Task) rating from Apple Health, weighted less than heart rate."
                        )
                        
                        priorityItem(
                            number: 4,
                            title: "Activity Metrics",
                            description: "For manual logs without heart rate, we use step count, steps per minute (cadence), and workout duration to estimate intensity."
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Intensity Levels
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Intensity Levels")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        ForEach(WorkoutIntensity.allCases, id: \.rawValue) { intensity in
                            intensityLevelCard(intensity: intensity)
                        }
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
    
    private func priorityItem(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.yellow, .orange]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.montserratBold(size: 16))
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
    
    private func intensityLevelCard(intensity: WorkoutIntensity) -> some View {
        HStack(spacing: 16) {
            // Color indicator
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    Color.intensityGradient(for: intensity, colorScheme: effectiveColorScheme)
                )
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.black.opacity(0.2), lineWidth: 1.5)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(intensity.displayName)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text(intensity.description)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
    IntensityExplanationView()
}

#Preview("Dark Mode") {
    IntensityExplanationView()
        .preferredColorScheme(.dark)
}

