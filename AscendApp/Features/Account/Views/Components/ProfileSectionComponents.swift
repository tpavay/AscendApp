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
                .accessibilityAddTraits(.isHeader)

            content
        }
    }
}

struct ProfileCardSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.jetLighter.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

struct ProfileCardDivider: View {
    let leadingInset: CGFloat

    init(leadingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
    }

    var body: some View {
        Divider()
            .background(.white.opacity(0.1))
            .padding(.leading, leadingInset)
    }
}
