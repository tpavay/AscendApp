//
//  FullScreenPhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/26/25.
//

import SwiftUI

struct FullScreenPhotoView: View {
    let photo: Photo
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(
                        x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height
                    )
                    .gesture(
                        SimultaneousGesture(
                            // Pinch to zoom
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(value, 4.0))
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        if scale < 1.2 {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                    }
                                },

                            // Drag to pan
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        dragOffset = value.translation
                                    } else {
                                        // Allow vertical drag to dismiss when not zoomed
                                        if abs(value.translation.height) > abs(value.translation.width) {
                                            dragOffset = CGSize(width: 0, height: value.translation.height)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.0 {
                                        offset.width += dragOffset.width
                                        offset.height += dragOffset.height
                                        dragOffset = .zero

                                        // Constrain pan to keep image visible
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            constrainOffset()
                                        }
                                    } else {
                                        // Dismiss if dragged down enough
                                        if value.translation.height > 100 {
                                            onDismiss()
                                        } else {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                dragOffset = .zero
                                            }
                                        }
                                    }
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        // Double tap to zoom
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }
            } else if isLoading {
                ProgressView("Loading...")
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)

                    Text("Failed to load photo")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Button("Dismiss") {
                        onDismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()
            }

            // Photo info overlay (bottom)
            VStack {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Uploaded \(photo.uploadedAt.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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

    private func constrainOffset() {
        guard let image = loadedImage else { return }

        let imageSize = image.size
        let screenSize = UIScreen.main.bounds.size

        // Calculate maximum offset based on zoom scale
        let maxOffsetX = max(0, (imageSize.width * scale - screenSize.width) / 2)
        let maxOffsetY = max(0, (imageSize.height * scale - screenSize.height) / 2)

        offset.width = max(-maxOffsetX, min(maxOffsetX, offset.width))
        offset.height = max(-maxOffsetY, min(maxOffsetY, offset.height))
    }
}

#Preview {
    FullScreenPhotoView(
        photo: Photo(url: URL(string: "https://picsum.photos/400/600")!)
    ) {
        print("Dismissed")
    }
}
