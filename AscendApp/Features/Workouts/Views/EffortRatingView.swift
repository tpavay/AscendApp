//
//  EffortRatingView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/19/25.
//

import SwiftUI

struct EffortRatingView: View {
    @Binding var effortRating: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var tempRating: Double
    
    init(effortRating: Binding<Double?>) {
        self._effortRating = effortRating
        self._tempRating = State(initialValue: effortRating.wrappedValue ?? 3.0)
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private func effortDescription(for rating: Double) -> String {
        switch Int(rating) {
        case 1:
            return "Minimal"
        case 2:
            return "Light"
        case 3:
            return "Moderate"
        case 4:
            return "High"
        case 5:
            return "Maximum"
        default:
            return "Moderate"
        }
    }
    
    var body: some View {
        AppSheetScaffold(title: "How much effort did you put in?") {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text(effortDescription(for: tempRating))
                        .font(.montserratMedium(size: 24))
                        .foregroundStyle(.accent)
                    
                    HStack {
                        Text("1")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        
                        Slider(value: $tempRating, in: 1...5, step: 1)
                            .accentColor(.accent)
                            .onChange(of: tempRating) { _, _ in
                                HapticsManager.shared.trigger(.selection)
                            }
                        
                        Text("5")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                    
                    Text("\(Int(tempRating))/5")
                        .font(.montserratBold(size: 32))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Cancel")
                }
                .appSheetButtonStyle(tone: .secondary)
                
                Button(action: {
                    effortRating = tempRating
                    dismiss()
                }) {
                    Text("Done")
                }
                .appSheetButtonStyle(tone: .primary)
            }
        }
    }
}
