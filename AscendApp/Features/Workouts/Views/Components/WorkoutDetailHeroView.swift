//
//  WorkoutDetailHeroView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI
import AVFoundation

/// Full-screen photo/video hero view with carousel support
struct WorkoutDetailHeroView: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    let sheetPosition: SheetPosition
    let isPlaybackEnabled: Bool
    let onPhotoTap: (Photo) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if photos.isEmpty {
                    placeholderView
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(photos.indices, id: \.self) { index in
                            let photo = photos[index]
                            HeroMediaItem(
                                photo: photo,
                                isVisible: sheetPosition != .expanded && isPlaybackEnabled && index == currentIndex,
                                geometry: geometry,
                                onTap: { onPhotoTap(photo) }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)

                if photos.count > 1 {
                    pageIndicator
                        .padding(.bottom, 20)
                }
            }
        }
        .background(Color.black)
    }

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

    @Environment(NetworkConnectivityService.self) private var connectivityService

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?
    @State private var isMuted = true

    var body: some View {
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
        .onTapGesture {
            onTap()
        }
        .task(id: photo.id) {
            await loadMedia()
        }
        .onChange(of: connectivityService.isConnected) { oldValue, newValue in
            guard oldValue == false, newValue == true else { return }
            retryFailedLoadIfNeeded()
        }
        .onChange(of: isVisible) { _, visible in
            updatePlayback(isVisible: visible)
        }
        .onDisappear {
            player?.pause()
            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
            }
            loopObserver = nil
        }
    }

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

    @ViewBuilder
    private var videoContent: some View {
        if let player {
            VideoPlayerView(player: player)
                .overlay(alignment: .bottomLeading) {
                    if let duration = photo.duration {
                        Text(DurationFormatter.format(duration: duration))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(.leading, 12)
                            .padding(.bottom, 18)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        toggleMute()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
        } else if isLoading {
            ZStack {
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

    private func loadMedia() async {
        if photo.isVideo {
            async let thumbnailLoad = loadCachedVideoThumbnail(from: photo.url)
            await configureVideoPlayer()
            loadedImage = await thumbnailLoad
        } else {
            loadedImage = await loadCachedPhoto(from: photo.url)
            isLoading = false
        }
    }

    private func configureVideoPlayer() async {
        let newPlayer = AVPlayer(url: photo.url)
        newPlayer.isMuted = isMuted
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
            updatePlayback(isVisible: isVisible)
        }
    }

    private func updatePlayback(isVisible: Bool) {
        guard let player else { return }

        player.isMuted = isMuted
        if isVisible {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func retryFailedLoadIfNeeded() {
        guard isLoading == false else { return }

        if photo.isVideo {
            guard player == nil else { return }
        } else {
            guard loadedImage == nil else { return }
        }

        isLoading = true
        Task {
            await loadMedia()
        }
    }
}
