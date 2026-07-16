//
//  ThumbnailPhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI

struct ThumbnailPhotoView: View {
    private let thumbnailSize: CGFloat = 120
    private let cornerRadius: CGFloat = 12

    let photoItem: SelectedPhotoItem
    let isHighlighted: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button { onTap() } label: {
        ZStack(alignment: .topLeading) {
            photoItem.image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // Video overlay
            if photoItem.isVideo {
                ZStack {
                    // Semi-transparent background
                    Color.black.opacity(0.3)

                    VStack(spacing: 4) {
                        // Play icon
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)

                        // Duration label
                        if let duration = photoItem.duration {
                            Text(formatDuration(duration))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            
            if isHighlighted {
                MediaTileHighlightBadge()
                    .padding(6)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            MediaTileDeleteButton(action: onDelete)
                .padding(6)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
