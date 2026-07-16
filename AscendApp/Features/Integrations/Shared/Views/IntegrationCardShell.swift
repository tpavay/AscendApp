//
//  IntegrationCardShell.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationCardShell<Content: View>: View {
    let style: IntegrationCardStyle
    let spacing: CGFloat
    let content: Content

    init(
        style: IntegrationCardStyle,
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: spacing) {
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(style.backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style.backgroundStroke, lineWidth: 1)
                )
        )
    }
}
