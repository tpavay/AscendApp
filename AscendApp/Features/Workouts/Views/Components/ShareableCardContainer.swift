//
//  ShareableCardContainer.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import SwiftUI

/// Base container for all shareable cards providing consistent structure and styling
struct ShareableCardContainer<Content: View>: View {
    let theme: ShareCardTheme
    let showBranding: Bool
    let displayName: String
    @ViewBuilder let content: () -> Content
    
    private let cornerRadius: CGFloat = 32
    
    init(
        theme: ShareCardTheme = .dark,
        showBranding: Bool = true,
        displayName: String = "",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.theme = theme
        self.showBranding = showBranding
        self.displayName = displayName
        self.content = content
    }
    
    private var brandingColor: Color {
        theme == .dark ? .white.opacity(0.9) : .black.opacity(0.7)
    }
    
    var body: some View {
        ZStack {
            // Background
            cardBackground
            
            // Content
            content()
        }
        .overlay(alignment: .bottom) {
            if showBranding {
                HStack {
                    AscendBadge(color: brandingColor)
                    Spacer()
                    if !displayName.isEmpty {
                        Text("@\(displayName)")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(brandingColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WorkoutShareCarouselViewModel.displayCardHeight,
            maxHeight: WorkoutShareCarouselViewModel.displayCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        switch theme {
        case .dark:
            LinearGradient(
                colors: [.night, .jetLighter],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        case .light:
            Color.white
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

/// Ascend branding badge for share cards
struct AscendBadge: View {
    var color: Color = .white.opacity(0.9)
    var iconSize: CGFloat = 30
    
    var body: some View {
        HStack(spacing: 8) {
            Image("AppIconInternal")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(color)
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            Text("Ascend")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(color)
        }
    }
}

#Preview("Dark Theme") {
    ShareableCardContainer(theme: .dark) {
        VStack {
            Text("Dark Theme Card")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
        }
    }
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Light Theme") {
    ShareableCardContainer(theme: .light) {
        VStack {
            Text("Light Theme Card")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.black)
        }
    }
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

