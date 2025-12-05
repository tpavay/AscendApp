//
//  VideoTrimmerView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/21/25.
//

import SwiftUI
import AVKit

struct VideoTrimmerView: View {
    let videoURL: URL
    let videoDuration: TimeInterval
    let onTrim: (TimeInterval, TimeInterval) async -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var startTime: Double = 0
    @State private var endTime: Double = 15
    @State private var player: AVPlayer?
    @State private var isTrimming = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var trimmedDuration: TimeInterval {
        endTime - startTime
    }
    
    private var isValidTrim: Bool {
        trimmedDuration > 0 && trimmedDuration <= 15
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Video Player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .onAppear {
                            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 300)
                        .cornerRadius(12)
                        .overlay {
                            ProgressView()
                        }
                }
                
                VStack(spacing: 20) {
                    // Duration Display
                    VStack(spacing: 8) {
                        HStack {
                            Text("Trimmed Duration")
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                            
                            Spacer()
                        }
                        
                        HStack {
                            Text(formatDuration(trimmedDuration))
                                .font(.montserratSemiBold(size: 24))
                                .foregroundStyle(isValidTrim ? .accent : .red)
                            
                            Spacer()
                        }
                        
                        if !isValidTrim {
                            HStack {
                                Text("Video must be 15 seconds or less")
                                    .font(.montserratRegular(size: 14))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Range Slider with Time Labels
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start")
                                    .font(.montserratMedium(size: 12))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                                Text(formatDuration(startTime))
                                    .font(.montserratSemiBold(size: 16))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("End")
                                    .font(.montserratMedium(size: 12))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                                Text(formatDuration(endTime))
                                    .font(.montserratSemiBold(size: 16))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            }
                        }
                        
                        RangeSlider(
                            lowValue: $startTime,
                            highValue: $endTime,
                            in: 0...videoDuration,
                            step: 0.1
                        ) { isEditing in
                            if !isEditing {
                                seekToStartTime()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Quick Duration Buttons
                    VStack(spacing: 8) {
                        HStack {
                            Text("Quick Select")
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            ForEach([5.0, 10.0, 15.0], id: \.self) { duration in
                                Button {
                                    setQuickDuration(duration)
                                } label: {
                                    Text("\(Int(duration))s")
                                        .font(.montserratSemiBold(size: 14))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(trimmedDuration == duration ? Color.accent : Color.gray)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding(.vertical, 20)
            .themedBackground()
            .navigationTitle("Trim Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.montserratRegular)
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await trimVideo()
                        }
                    } label: {
                        if isTrimming {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Done")
                                .font(.montserratSemiBold)
                                .foregroundStyle(isValidTrim ? .accent : .gray)
                        }
                    }
                    .disabled(!isValidTrim || isTrimming)
                }
            }
            .onAppear {
                setupPlayer()
                // Initialize end time to min of 15s or video duration
                endTime = min(15, videoDuration)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
    
    private func setupPlayer() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            // Preload essential properties to avoid blocking main thread
            try? await asset.load(.isPlayable, .duration)

            let playerItem = AVPlayerItem(asset: asset)

            await MainActor.run {
                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.seek(to: .zero)
                self.player = newPlayer
            }
        }
    }
    
    private func seekToStartTime() {
        player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
    }
    
    private func setQuickDuration(_ duration: TimeInterval) {
        startTime = 0
        endTime = min(duration, videoDuration)
        seekToStartTime()
    }
    
    private func trimVideo() async {
        isTrimming = true
        await onTrim(startTime, endTime)
        isTrimming = false
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d.%01ds", seconds, milliseconds)
    }
}

#Preview {
    VideoTrimmerView(
        videoURL: URL(string: "https://example.com/video.mov")!,
        videoDuration: 30,
        onTrim: { start, end in
            print("Trim from \(start) to \(end)")
        },
        onCancel: {
            print("Cancel")
        }
    )
}

