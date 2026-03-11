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

    private var title: String {
        photo.isVideo ? "Video Options" : "Photo Options"
    }
    
    var body: some View {
        AppSheetScaffold(title: title, layout: .actionMenu) {
            VStack(spacing: 12) {
                if !isHighlighted {
                    Button(action: {
                        onMakeHighlighted()
                    }) {
                        AppSheetOptionRow(
                            systemImage: "star.fill",
                            title: photo.isVideo ? "Make Highlighted Video" : "Make Highlighted Photo",
                            iconTint: .accent,
                            style: .compact
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    AppSheetOptionRow(
                        systemImage: "star.fill",
                        title: "Currently Highlighted",
                        iconTint: .accent,
                        tone: .accent,
                        style: .compact,
                        trailingSymbol: "checkmark",
                        trailingTint: .accent
                    )
                }
                
                Button(action: {
                    onDelete()
                }) {
                    AppSheetOptionRow(
                        systemImage: "trash",
                        title: photo.isVideo ? "Delete Video" : "Delete Photo",
                        iconTint: .red,
                        tone: .destructive,
                        style: .compact
                    )
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Button(action: {
                onCancel()
            }) {
                Text("Cancel")
            }
            .appSheetButtonStyle(tone: .subtle)
        }
        .appSheetStyle(.actionMenu)
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
