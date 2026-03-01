//
//  ProfileSectionComponents.swift
//  AscendApp
//
//  Reusable section and card primitives for profile/account screens.
//

import SwiftUI

struct ProfileSection<Content: View>: View {
    let title: String
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 4)

            content
        }
    }
}

struct ProfileCardSurface<Content: View>: View {
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

struct ProfileCardDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Divider()
            .background(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
    }
}

