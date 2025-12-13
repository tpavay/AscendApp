//
//  ThumbnailPhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI

struct ThumbnailPhotoView: View {
    let photoItem: SelectedPhotoItem
    let isHighlighted: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            photoItem.image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            if isHighlighted {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(.accent)
                    )
                    .padding(6)
            }
        }
        .frame(width: 120, height: 120)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            onTap()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .shadow(radius: 2)
            }
            .offset(x: 6, y: -6)
            .buttonStyle(.plain)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}
