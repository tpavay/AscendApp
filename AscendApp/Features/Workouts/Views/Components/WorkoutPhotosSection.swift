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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photos) { photo in
                        LoadablePhotoView(
                            photo: photo,
                            size: CGSize(width: 110, height: 110),
                            cornerRadius: 10
                        ) {
                            selectedPhoto = photo
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenPhotoView(photo: photo) {
                selectedPhoto = nil
            }
        }
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
