//
//  WorkoutMetricSelectionView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct WorkoutMetricSelectionView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.accent)
                    .padding(.top, 20)
                
                Text("Workout Metric")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Choose what you want to track")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            // Metric Options
            VStack(spacing: 12) {
                ForEach(WorkoutMetric.allCases) { metric in
                    metricOptionRow(metric: metric)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .themedBackground()
        .navigationTitle("Workout Metric")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
    
    private func metricOptionRow(metric: WorkoutMetric) -> some View {
        Button(action: {
            settingsManager.setPreferredMetric(metric)
        }) {
            HStack(spacing: 16) {
                // Metric Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: metric == .steps ? "figure.walk" : "building.2")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                // Metric Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(metric.description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if settingsManager.preferredWorkoutMetric == metric {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(settingsManager.preferredWorkoutMetric == metric ? 1.0 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settingsManager.preferredWorkoutMetric)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(settingsManager.preferredWorkoutMetric == metric ? .accent.opacity(0.5) : 
                                   (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)), 
                                   lineWidth: settingsManager.preferredWorkoutMetric == metric ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light Theme") {
    NavigationStack {
        WorkoutMetricSelectionView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    NavigationStack {
        WorkoutMetricSelectionView()
    }
    .preferredColorScheme(.dark)
}