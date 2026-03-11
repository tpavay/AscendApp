//
//  TooltipView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/26/25.
//

import SwiftUI

struct TooltipView: View {
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.accent)

                Text(title)
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
            }

            // Content
            Text(content)
                .font(.montserratRegular(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            // Got It Button
            Button(action: {
                dismiss()
            }) {
                Text("Got It")
                    .font(.montserratSemiBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .appSheetBackground()
    }
}

// Reusable tooltip button component
struct TooltipButton: View {
    let title: String
    let content: String
    @State private var showingTooltip = false

    // Estimate height based on content length
    private var estimatedHeight: CGFloat {
        // Base height: icon (40) + spacing (8) + title (~24) + spacing (24) + button (50) + padding (40) + buffer = ~215
        let baseHeight: CGFloat = 215
        // Estimate ~35 chars per line at 16pt font, ~22pt line height
        let estimatedLines = ceil(CGFloat(content.count) / 35)
        let contentHeight = estimatedLines * 22
        return baseHeight + contentHeight
    }

    var body: some View {
        Button(action: {
            showingTooltip = true
        }) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.accent.opacity(0.8))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTooltip) {
            TooltipView(title: title, content: content)
                .appSheetStyle(.height(estimatedHeight))
        }
    }
}

#Preview {
    TooltipView(
        title: "Step Height",
        content: "This is the height of each individual step on your stair stepper machine. Accurate step height helps calculate your total vertical climb distance."
    )
}

#Preview("Tooltip Button") {
    TooltipButton(
        title: "Step Height",
        content: "This is the height of each individual step on your stair stepper machine. Accurate step height helps calculate your total vertical climb distance."
    )
    .padding()
}
