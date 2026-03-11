//
//  WorkoutMetricExplanationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import SwiftUI

struct WorkoutMetricExplanationView: View {
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
                        Text("Workout Metric")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Choose whether to display your climbing progress in steps or floors throughout the app. Both values are always tracked - this setting controls which one is shown as the primary metric.")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Affected Areas
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Where This Setting Applies")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        affectedAreaItem(
                            icon: "list.bullet.rectangle",
                            title: "Workout List",
                            description: "Each workout card shows your preferred metric (e.g., \"2,401 steps\" or \"150 floors\")."
                        )
                        
                        affectedAreaItem(
                            icon: "house.fill",
                            title: "Home Dashboard",
                            description: "The 7-day summary card and daily totals display in your preferred metric."
                        )
                        
                        affectedAreaItem(
                            icon: "trophy.fill",
                            title: "Leaderboards",
                            description: "Compare with others using your preferred metric. Everyone's data is converted to match your view."
                        )
                        
                        affectedAreaItem(
                            icon: "square.and.arrow.up",
                            title: "Sharing",
                            description: "Share cards and copied text use your preferred metric."
                        )
                        
                        affectedAreaItem(
                            icon: "slider.horizontal.3",
                            title: "Filters",
                            description: "Workout filters use your preferred metric for range selection."
                        )
                        
                        affectedAreaItem(
                            icon: "star.fill",
                            title: "Personal Record Badges",
                            description: "PR badges show \"Most Steps\" or \"Most Floors\" based on your selection. Other PR types (duration, pace, etc.) always appear."
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Conversion Note
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How Conversion Works")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Floors are calculated using your \"Steps Per Floor\" setting. Each workout saves this value at creation time, so changing the setting later won't affect past workouts.")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appSheetBackground()
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
    
    private func affectedAreaItem(icon: String, title: String, description: String) -> some View {
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
    WorkoutMetricExplanationView()
}

#Preview("Dark Mode") {
    WorkoutMetricExplanationView()
        .preferredColorScheme(.dark)
}
