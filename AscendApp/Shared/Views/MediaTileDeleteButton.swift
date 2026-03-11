//
//  MediaTileDeleteButton.swift
//  AscendApp
//
//  Created by Codex on 3/10/26.
//

import SwiftUI

struct MediaTileDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.6))
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Remove media")
    }
}
