//
//  IntegrationCardActionButton.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationCardActionButton: View {
    enum Appearance {
        case text(color: Color)
        case filled(background: Color, foreground: Color)
        case outlined(foreground: Color, border: Color, background: Color = .clear)
    }

    let title: String
    let appearance: Appearance
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        color: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.appearance = .text(color: color)
        self.isLoading = isLoading
        self.action = action
    }

    init(
        _ title: String,
        appearance: Appearance,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.appearance = appearance
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(progressTint)
                    .frame(width: loaderFrameSize, height: loaderFrameSize)
            } else {
                Text(title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(foregroundColor)
            }
        }
        .buttonStyle(.plain)
        .padding(horizontalPadding)
        .padding(verticalPadding)
        .background(backgroundView)
    }

    private var foregroundColor: Color {
        switch appearance {
        case .text(let color), .outlined(let color, _, _):
            color
        case .filled(_, let foreground):
            foreground
        }
    }

    private var progressTint: Color {
        switch appearance {
        case .filled:
            foregroundColor
        case .text, .outlined:
            foregroundColor
        }
    }

    private var loaderFrameSize: CGFloat {
        switch appearance {
        case .text:
            14
        case .filled, .outlined:
            18
        }
    }

    private var horizontalPadding: CGFloat {
        switch appearance {
        case .text:
            0
        case .filled, .outlined:
            11
        }
    }

    private var verticalPadding: CGFloat {
        switch appearance {
        case .text:
            0
        case .filled, .outlined:
            6
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch appearance {
        case .text:
            Color.clear
        case .filled(let background, _):
            Capsule()
                .fill(background)
        case .outlined(_, let border, let background):
            Capsule()
                .fill(background)
                .overlay(
                    Capsule()
                        .stroke(border, lineWidth: 1)
                )
        }
    }
}
