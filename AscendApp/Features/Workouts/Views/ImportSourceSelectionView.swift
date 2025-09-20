//
//  ImportSourceSelectionView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct ImportSourceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var showingHealthKitImport = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(.accent)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    VStack(spacing: 8) {
                        Text("Import Workouts")
                            .font(.montserratBold(size: 32))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        
                        Text("Choose a source to import your stair climbing workouts from")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
                
                // Import Sources
                VStack(spacing: 16) {
                    ImportSourceCard(
                        title: "Apple Health",
                        description: "Import stair stepper workouts from your Apple Health data",
                        icon: "heart.fill",
                        iconColor: .red,
                        isRecommended: true
                    ) {
                        showingHealthKitImport = true
                    }
                    
                    // Placeholder for future import sources
                    ImportSourceCard(
                        title: "Other Sources",
                        description: "More import options coming soon",
                        icon: "plus.circle",
                        iconColor: .gray,
                        isEnabled: false
                    ) {
                        // Future implementation
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .themedBackground()
            .fullScreenCover(isPresented: $showingHealthKitImport) {
                HealthKitImportView(onComplete: {
                    // Dismiss both the HealthKit import view and this source selection view
                    showingHealthKitImport = false
                    dismiss()
                })
            }
        }
    }
}

struct ImportSourceCard: View {
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    var isRecommended: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isEnabled ? iconColor : .gray)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill((isEnabled ? iconColor : .gray).opacity(0.1))
                        )
                    
                    Spacer()
                    
                    if isRecommended {
                        Text("Recommended")
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.accent)
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(isEnabled ? (effectiveColorScheme == .dark ? .white : .black) : .gray)
                    
                    Text(description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(isEnabled ? (effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray) : .gray.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
                
                if !isEnabled {
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isEnabled ? (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)) : .gray.opacity(0.1), 
                                lineWidth: 1
                            )
                    )
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ImportSourceSelectionView()
}