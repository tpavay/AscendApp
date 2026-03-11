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
        AppSheetScaffold(
            title: "Change Workout Metric",
            headerAlignment: .center,
            contentAlignment: .leading
        ) {
            VStack(spacing: 16) {
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
            }
        } footer: {
            Button(action: {
                dismiss()
            }) {
                Text("Got it")
            }
            .appSheetButtonStyle(tone: .primary)
        }
    }
}

#Preview {
    MetricTooltipView()
        .appSheetStyle(.fitted())
}
