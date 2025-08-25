//
//  ThemeSelectionView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct ThemeSelectionView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    
    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.accent)
                    .padding(.top, 20)
                
                Text("Appearance")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Choose how the app looks")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            // Theme Options
            VStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    themeOptionRow(theme: theme)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .themedBackground()
        .preferredColorScheme(effectiveColorScheme)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
    
    private func themeOptionRow(theme: AppTheme) -> some View {
        Button(action: {
            themeManager.setTheme(theme)
        }) {
            HStack(spacing: 16) {
                // Theme Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: theme.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.accent)
                }
                
                // Theme Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text(theme.description)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if themeManager.selectedTheme == theme {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(themeManager.selectedTheme == theme ? 1.0 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: themeManager.selectedTheme)
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
                            .stroke(themeManager.selectedTheme == theme ? .accent.opacity(0.5) : 
                                   (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)), 
                                   lineWidth: themeManager.selectedTheme == theme ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light Theme") {
    NavigationStack {
        ThemeSelectionView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    NavigationStack {
        ThemeSelectionView()
    }
    .preferredColorScheme(.dark)
}