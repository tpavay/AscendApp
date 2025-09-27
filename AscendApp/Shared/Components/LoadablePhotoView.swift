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
    @State private var loadError: Error?

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
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .onTapGesture {
                        onTap?()
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
        .task {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: photo.url)
            
            await MainActor.run {
                if let image = UIImage(data: data) {
                    self.loadedImage = image
                } else {
                    self.loadError = PhotoLoadError.invalidImageData
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = error
                self.isLoading = false
            }
        }
    }
}

enum PhotoLoadError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        }
    }
}

#Preview {
    LoadablePhotoView(
        photo: Photo(url: URL(string: "https://picsum.photos/200/200")!)
    )
}
