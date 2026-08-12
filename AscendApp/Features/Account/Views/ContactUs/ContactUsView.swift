//
//  ContactUsView.swift
//  AscendApp
//
//  Created by Claude on 1/4/26.
//

import SwiftUI

struct ContactUsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 20)

            // Contact Options
            VStack(spacing: 12) {
                ForEach(FeedbackType.allCases) { type in
                    NavigationLink(destination: ContactFormView(feedbackType: type)) {
                        contactOptionRow(type: type)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .themedBackground()
        .preferredColorScheme(effectiveColorScheme)
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .trackOnce(screen: .contactUs)
    }

    private func contactOptionRow(type: FeedbackType) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: type.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(type.iconColor)
            }

            // Title & Description
            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.montserratSemiBold)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text(type.description)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

#Preview("Dark Theme") {
    NavigationStack {
        ContactUsView()
    }
    .preferredColorScheme(.dark)
}
