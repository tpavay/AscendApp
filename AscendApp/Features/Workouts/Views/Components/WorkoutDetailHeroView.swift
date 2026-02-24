//
//  WorkoutDetailHeroView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI
import AVKit

/// Custom video player that fills its container (aspect fill)
struct FillVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
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

        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

/// Full-screen photo/video hero view with carousel support
struct WorkoutDetailHeroView: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    let sheetPosition: SheetPosition
    let onPhotoTap: (Photo) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Photo/Video Carousel
                if photos.isEmpty {
                    placeholderView
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            HeroMediaItem(
                                photo: photo,
                                isVisible: sheetPosition != .expanded && index == currentIndex,
                                geometry: geometry,
                                onTap: { onPhotoTap(photo) }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }

                // Gradient overlay at bottom for smooth transition to sheet
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)

                // Page indicator (only show if multiple photos)
                if photos.count > 1 {
                    pageIndicator
                        .padding(.bottom, 20)
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - View Components

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.gray)
            }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<photos.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }
}

/// Individual media item (photo or video) in the hero carousel
private struct HeroMediaItem: View {
    let photo: Photo
    let isVisible: Bool
    let geometry: GeometryProxy
    let onTap: () -> Void

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?

    var body: some View {
        Button { onTap() } label: {
        ZStack {
            if photo.isVideo {
                videoContent
            } else {
                photoContent
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            await loadMedia()
        }
        .onChange(of: isVisible) { _, visible in
            if photo.isVideo {
                if visible {
                    player?.play()
                } else {
                    player?.pause()
                }
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - Photo Content

    @ViewBuilder
    private var photoContent: some View {
        if let image = loadedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if isLoading {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private var videoContent: some View {
        if let player = player {
            FillVideoPlayer(player: player)
                .overlay(alignment: .topTrailing) {
                    // Duration badge
                    if let duration = photo.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(12)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Muted indicator
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.5))
                        )
                        .padding(12)
                }
        } else if isLoading {
            ZStack {
                // Show thumbnail while loading video
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                ProgressView()
                    .tint(.white)
            }
        } else {
            Image(systemName: "video.slash")
                .font(.system(size: 32))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Media Loading

    private func loadMedia() async {
        if photo.isVideo {
            await loadVideoThumbnail()
            await loadVideo()
        } else {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
                self.isLoading = false
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: photo.url)

            await MainActor.run {
                if let image = UIImage(data: data) {
                    ImageCache.shared.store(image, for: photo.url)
                    self.loadedImage = image
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func loadVideoThumbnail() async {
        // Check cache first
        if let cached = ImageCache.shared.image(for: photo.url) {
            await MainActor.run {
                self.loadedImage = cached
            }
            return
        }

        do {
            let asset = AVURLAsset(url: photo.url)
            try await asset.load(.isReadable, .tracks)

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            let cgImage = try await imageGenerator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)

            await MainActor.run {
                ImageCache.shared.store(image, for: photo.url)
                self.loadedImage = image
            }
        } catch {
            // Thumbnail failed, video player will still try to load
        }
    }

    private func loadVideo() async {
        let asset = AVURLAsset(url: photo.url)
        try? await asset.load(.isPlayable)

        let playerItem = AVPlayerItem(asset: asset)

        await MainActor.run {
            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.isMuted = true // Muted by default in hero view

            // Loop video
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }

            self.player = newPlayer
            self.isLoading = false

            // Auto-play if visible (slight delay to ensure view is ready)
            if isVisible {
                Task {
                    try await Task.sleep(for: .milliseconds(100))
                    newPlayer.play()
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
