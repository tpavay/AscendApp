//
//  MeasurementSystemSelectionView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/26/25.
//

import SwiftUI

struct MeasurementSystemSelectionView: View {
    @State private var settingsManager = SettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 20)
                
                // Measurement System Options
                VStack(spacing: 12) {
                    ForEach(MeasurementSystem.allCases) { system in
                        measurementSystemRow(system: system)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .themedBackground()
        .navigationTitle("Measurement System")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
    
    private func measurementSystemRow(system: MeasurementSystem) -> some View {
        Button(action: {
            settingsManager.setMeasurementSystem(system)
        }) {
            HStack(spacing: 16) {
                // System Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: system == .imperial ? "ruler" : "ruler.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                // System Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(system.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(system.description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if settingsManager.measurementSystem == system {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(settingsManager.measurementSystem == system ? 1.0 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settingsManager.measurementSystem)
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
                            .stroke(settingsManager.measurementSystem == system ? .accent.opacity(0.5) : 
                                   (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)), 
                                   lineWidth: settingsManager.measurementSystem == system ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        MeasurementSystemSelectionView()
    }
}

#Preview("Dark") {
    NavigationStack {
        MeasurementSystemSelectionView()
            .preferredColorScheme(.dark)
    }
}