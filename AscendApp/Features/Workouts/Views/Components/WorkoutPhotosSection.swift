//
//  WorkoutPhotosSection.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/26/25.
//

import SwiftUI

struct WorkoutPhotosSection: View {
    let photos: [Photo]
    @State private var selectedPhoto: Photo?
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Photos")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("(\(photos.count))")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.gray)

                Spacer()
            }

            // Photos grid
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(photos) { photo in
                    LoadablePhotoView(
                        photo: photo,
                        size: CGSize(width: 100, height: 100),
                        cornerRadius: 8
                    ) {
                        selectedPhoto = photo
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenPhotoView(photo: photo) {
                selectedPhoto = nil
            }
        }
    }

    private var gridColumns: [GridItem] {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 40 // 20 on each side
        let spacing: CGFloat = 12
        let itemSize: CGFloat = 100

        let availableWidth = screenWidth - padding
        let columnsWithSpacing = (availableWidth + spacing) / (itemSize + spacing)
        let columnCount = max(2, Int(columnsWithSpacing.rounded(.down)))

        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }
}

#Preview {
    WorkoutPhotosSection(
        photos: [
            Photo(url: URL(string: "https://picsum.photos/200/200?random=1")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=2")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=3")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=4")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=5")!)
        ]
    )
    .padding()
}