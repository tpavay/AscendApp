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
        List {
            Section {
                ForEach(MeasurementSystem.allCases) { system in
                    Button(action: {
                        settingsManager.setMeasurementSystem(system)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(system.displayName)
                                    .font(.montserratMedium)
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                                
                                Text(system.description)
                                    .font(.montserratRegular(size: 14))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                            }
                            
                            Spacer()
                            
                            if settingsManager.measurementSystem == system {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Choose your preferred measurement system")
                    .font(.montserratRegular(size: 14))
                    .textCase(.none)
            } footer: {
                Text("This affects step height measurements, distance calculations, and other metrics throughout the app.")
                    .font(.montserratRegular(size: 12))
                    .textCase(.none)
            }
        }
        .themedBackground()
        .navigationTitle("Measurement System")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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