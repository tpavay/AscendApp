//
//  LoadablePhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/26/25.
//

import SwiftUI

struct LoadablePhotoView: View {
    let photo: Photo
    let size: CGSize
    let cornerRadius: CGFloat
    let onTap: (() -> Void)?

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    init(
        photo: Photo,
        size: CGSize = CGSize(width: 120, height: 120),
        cornerRadius: CGFloat = 8,
        onTap: (() -> Void)? = nil
    ) {
        self.photo = photo
        self.size = size
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                
                // Video overlay
                if photo.isVideo {
                    ZStack {
                        Color.black.opacity(0.3)
                        
                        VStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                            
                            if let duration = photo.duration {
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
            } else if isLoading {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.gray.opacity(0.2))
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.gray.opacity(0.2))
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 16))
                                .foregroundStyle(.gray)
                            Text("Failed to load")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture {
            onTap?()
        }
        .task {
            await loadMedia()
        }
    }

    private func loadMedia() async {
        if photo.isVideo {
            await loadVideoThumbnail()
        } else {
            await loadPhoto()
        }
    }
    
    private func loadPhoto() async {
        let image = await RemoteMediaLoader.shared.loadPhoto(from: photo.url)
        await MainActor.run {
            self.loadedImage = image
            self.isLoading = false
        }
    }

    private func loadVideoThumbnail() async {
        let image = await RemoteMediaLoader.shared.loadVideoThumbnail(from: photo.url)
        await MainActor.run {
            self.loadedImage = image
            self.isLoading = false
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

#Preview {
    LoadablePhotoView(
        photo: Photo(url: URL(string: "https://picsum.photos/200/200")!)
    )
}
