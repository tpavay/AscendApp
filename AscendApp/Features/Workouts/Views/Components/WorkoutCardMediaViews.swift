//
//  WorkoutCardMediaViews.swift
//  AscendApp
//
//  Extracted from WorkoutListView.swift. Consolidates duplicated media loading
//  and duration formatting logic into shared helpers.
//

import SwiftUI
import AVFoundation

// MARK: - Shared Helpers

/// Formats a video duration as "m:ss" (e.g. "1:04", "0:32").
/// Consolidates 3 duplicate implementations that existed in the original WorkoutListView.
func formatVideoDuration(_ duration: TimeInterval) -> String {
    DurationFormatter.format(duration: duration)
}

/// Loads a remote photo with ImageCache support.
/// Consolidates 3 duplicate `loadPhoto()` implementations.
func loadCachedPhoto(from url: URL) async -> UIImage? {
    await RemoteMediaLoader.shared.loadPhoto(from: url)
}

/// Generates a video thumbnail with ImageCache support.
/// Consolidates 3 duplicate `loadVideoThumbnail()` implementations.
func loadCachedVideoThumbnail(from url: URL) async -> UIImage? {
    await RemoteMediaLoader.shared.loadVideoThumbnail(from: url)
}

// MARK: - WorkoutCardMediaSection

/// Media section for workout cards - handles single full-width or carousel for multiple
struct WorkoutCardMediaSection: View {
    let workout: Workout

    private var sortedPhotos: [Photo] {
        workout.orderedPhotosForDisplay
    }

    var body: some View {
        if workout.photos.count == 1, let photo = workout.photos.first {
            SingleMediaView(photo: photo)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sortedPhotos) { photo in
                        CarouselMediaThumbnail(photo: photo)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - SingleMediaView

/// Full-width single media view with autoplay video support
struct SingleMediaView: View {
    let photo: Photo

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if photo.isVideo {
                    AutoPlayVideoView(photo: photo, isVisible: $isVisible)
                } else if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.gray)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
        }
        .frame(height: 220)
        .task {
            if !photo.isVideo {
                loadedImage = await loadCachedPhoto(from: photo.url)
                isLoading = false
            }
        }
    }
}

// MARK: - AutoPlayVideoView

/// Auto-playing video view that plays when visible and resets when not
struct AutoPlayVideoView: View {
    let photo: Photo
    @Binding var isVisible: Bool

    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    VideoPlayerView(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onChange(of: isVisible) { _, visible in
                            if visible {
                                player.seek(to: .zero)
                                player.play()
                            } else {
                                player.pause()
                                player.seek(to: .zero)
                            }
                        }
                } else if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }

                // Duration badge
                if let duration = photo.duration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatVideoDuration(duration))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                                .padding(8)
                        }
                    }
                }
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            loopObserver = nil
            player = nil
        }
    }

    private func loadVideo() async {
        async let thumbnailLoad = loadCachedVideoThumbnail(from: photo.url)

        let newPlayer = AVPlayer(url: photo.url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        await MainActor.run {
            self.loopObserver = observer
            self.player = newPlayer
            self.isLoading = false
            if isVisible {
                newPlayer.play()
            }
        }

        thumbnail = await thumbnailLoad
    }
}

// MARK: - VideoPlayerView

/// Simple AVPlayer wrapper view.
///
/// The frames are the climber's own footage and reach Sentry unmasked without
/// `sentryMasked()`: `maskAllImages` covers `UIImageView`, not an
/// `AVPlayerLayer` drawing straight into its host view.
struct VideoPlayerView: View {
    let player: AVPlayer

    var body: some View {
        PlayerRepresentable(player: player)
            .sentryMasked()
    }
}

private struct PlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let playerView = uiView as? PlayerUIView else { return }
        playerView.player = player
    }

    class PlayerUIView: UIView {
        var player: AVPlayer? {
            didSet {
                playerLayer.player = player
            }
        }

        private var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}

// MARK: - CarouselMediaThumbnail

/// Carousel thumbnail for multiple media
struct CarouselMediaThumbnail: View {
    let photo: Photo

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 140)
                    .clipped()

                if photo.isVideo {
                    ZStack {
                        Color.black.opacity(0.2)

                        VStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)

                            if let duration = photo.duration {
                                Text(formatVideoDuration(duration))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.6))
                                    )
                            }
                        }
                    }
                }
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.gray)
                    }
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            if photo.isVideo {
                loadedImage = await loadCachedVideoThumbnail(from: photo.url)
            } else {
                loadedImage = await loadCachedPhoto(from: photo.url)
            }
            isLoading = false
        }
    }
}

// MARK: - HighlightedPhotoThumbnail

/// A compact thumbnail view for displaying the highlighted photo/video on workout cards
struct HighlightedPhotoThumbnail: View {
    let photo: Photo

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    if photo.isVideo {
                        ZStack {
                            Color.black.opacity(0.2)

                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)

                                if let duration = photo.duration {
                                    Text(formatVideoDuration(duration))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                }
                            }
                        }
                    }
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.gray)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 260)
        .task {
            if photo.isVideo {
                loadedImage = await loadCachedVideoThumbnail(from: photo.url)
            } else {
                loadedImage = await loadCachedPhoto(from: photo.url)
            }
            isLoading = false
        }
    }
}
