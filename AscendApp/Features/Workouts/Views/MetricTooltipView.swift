//
//  MetricTooltipView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct MetricTooltipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Handle bar for visual indication
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            VStack(spacing: 16) {
                // Icon and title
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.accent)
                    
                    Text("Change Workout Metric")
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Spacer()
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("1.")
                            .font(.montserratMedium)
                            .foregroundStyle(.accent)
                        
                        Text("Go to Settings tab")
                            .font(.montserratRegular(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    }
                    
                    HStack(spacing: 8) {
                        Text("2.")
                            .font(.montserratMedium)
                            .foregroundStyle(.accent)
                        
                        Text("Tap \"Workout Metric\"")
                            .font(.montserratRegular(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    }
                    
                    HStack(spacing: 8) {
                        Text("3.")
                            .font(.montserratMedium)
                            .foregroundStyle(.accent)
                        
                        Text("Choose Steps or Floors")
                            .font(.montserratRegular(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Got it button
                Button(action: {
                    dismiss()
                }) {
                    Text("Got it")
                        .font(.montserratSemiBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.accent)
                        )
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .themedBackground()
    }
}

#Preview {
    MetricTooltipView()
        .presentationDetents([.fraction(0.25)])
}