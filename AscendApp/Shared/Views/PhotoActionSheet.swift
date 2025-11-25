//
//  PhotoActionSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import SwiftUI

struct PhotoActionSheet: View {
    let photo: Photo
    let isHighlighted: Bool
    let onMakeHighlighted: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text(photo.isVideo ? "Video Options" : "Photo Options")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            
            // Actions
            VStack(spacing: 12) {
                // Make Highlighted button (only show if not already highlighted)
                if !isHighlighted {
                    Button(action: {
                        onMakeHighlighted()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.accent)
                            
                            Text(photo.isVideo ? "Make Highlighted Video" : "Make Highlighted Photo")
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        )
                    }
                } else {
                    // Show that this is currently highlighted
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.accent)
                        
                        Text("Currently Highlighted")
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(.accent)
                        
                        Spacer()
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.accent.opacity(0.15))
                    )
                }
                
                // Delete button
                Button(action: {
                    onDelete()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                        
                        Text(photo.isVideo ? "Delete Video" : "Delete Photo")
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(.red)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                    )
                }
            }
            
            // Cancel button
            Button(action: {
                onCancel()
            }) {
                Text("Cancel")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.05))
                    )
            }
        }
        .padding(20)
        .themedBackground()
    }
}

#Preview("Not Highlighted") {
    PhotoActionSheet(
        photo: Photo(url: URL(string: "https://example.com/photo.jpg")!),
        isHighlighted: false,
        onMakeHighlighted: { print("Make highlighted") },
        onDelete: { print("Delete") },
        onCancel: { print("Cancel") }
    )
}

#Preview("Highlighted") {
    PhotoActionSheet(
        photo: Photo(url: URL(string: "https://example.com/photo.jpg")!),
        isHighlighted: true,
        onMakeHighlighted: { print("Make highlighted") },
        onDelete: { print("Delete") },
        onCancel: { print("Cancel") }
    )
    .preferredColorScheme(.dark)
}

#Preview("Video") {
    PhotoActionSheet(
        photo: Photo(url: URL(string: "https://example.com/video.mp4")!, type: .video, duration: 12.5),
        isHighlighted: false,
        onMakeHighlighted: { print("Make highlighted") },
        onDelete: { print("Delete") },
        onCancel: { print("Cancel") }
    )
}

