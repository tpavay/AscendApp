import SwiftUI
import AVKit

/// Renders a `ShareBackgroundSource` as a full-bleed backing layer. Reused by
/// both the editing canvas and the export renderer so the background is
/// pixel-consistent between preview and output.
struct ShareBackgroundView: View {
    let source: ShareBackgroundSource
    /// When true (export), video falls back to a poster frame since the export
    /// pipeline composites video separately.
    var isStatic: Bool = false

    var body: some View {
        switch source {
        case .photo(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()

        case .video(let url):
            if isStatic {
                // Export path composites video frames elsewhere; show black here.
                Color.black
            } else {
                LoopingVideoView(url: url)
            }

        case .preset(let preset):
            presetView(preset)
        }
    }

    @ViewBuilder
    private func presetView(_ preset: ShareComposerPreset) -> some View {
        switch preset {
        case .climbImage(let climb, let variant):
            ZStack {
                ClimbArtworkView(climb: climb, variant: variant)
                LinearGradient(
                    colors: [.black.opacity(0.15), .clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

/// Minimal muted looping video player for background preview during editing.
private struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(with: url)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    final class PlayerContainerView: UIView {
        private var looper: AVPlayerLooper?
        private var queuePlayer: AVQueuePlayer?

        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func configure(with url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            queuePlayer = player
            player.play()
        }
    }
}
