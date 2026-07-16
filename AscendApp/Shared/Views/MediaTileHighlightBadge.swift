//
//  MediaTileHighlightBadge.swift
//  AscendApp
//
//  Created by Codex on 3/10/26.
//

import SwiftUI

struct MediaTileHighlightBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.9))
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(.accent)
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityLabel("Highlighted media")
    }
}
