//
//  WorkoutShareCardDivider.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import SwiftUI

struct WorkoutShareCardDivider: View {
    let color: Color
    let diamondSize: CGFloat
    let diamondOpacity: Double
    let lineWidth: CGFloat
    let lineHeight: CGFloat
    let lineOpacity: Double
    let spacing: CGFloat
    let topPadding: CGFloat

    init(
        color: Color = .white,
        diamondSize: CGFloat = 4,
        diamondOpacity: Double = 0.18,
        lineWidth: CGFloat = 0.8,
        lineHeight: CGFloat = 22,
        lineOpacity: Double = 0.14,
        spacing: CGFloat = 2,
        topPadding: CGFloat = 2
    ) {
        self.color = color
        self.diamondSize = diamondSize
        self.diamondOpacity = diamondOpacity
        self.lineWidth = lineWidth
        self.lineHeight = lineHeight
        self.lineOpacity = lineOpacity
        self.spacing = spacing
        self.topPadding = topPadding
    }

    var body: some View {
        VStack(spacing: spacing) {
            Rectangle()
                .fill(color.opacity(diamondOpacity))
                .frame(width: diamondSize, height: diamondSize)
                .rotationEffect(.degrees(45))

            Rectangle()
                .fill(color.opacity(lineOpacity))
                .frame(width: lineWidth, height: lineHeight)
        }
        .padding(.top, topPadding)
    }
}

#Preview {
    WorkoutShareCardDivider(diamondSize: 6, lineWidth: 1.2, lineHeight: 30)
        .padding()
        .background(.black)
}
