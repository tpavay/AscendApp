import SwiftUI

/// A landmark that fills in with its own photographic colour from the base up as a climb
/// progresses: a dim grayscale copy of the cut-out underneath, the full-colour copy masked from
/// the bottom, and a thin line riding the boundary between them.
///
/// Both layers are the one downloaded image (`ClimbProgressImageRepository`); the grayscale is
/// applied at render time. The
/// landmark is fitted by its measured visible bounds (`ClimbProgressArtworkLayout`), bottom
/// centred in whatever space it is offered, at one scale for both axes - a wide landmark comes
/// out shorter at the same width rather than stretched. Give it `artwork.visibleAspectRatio` to
/// make the offered space the landmark exactly. The image never moves; only the mask and the
/// line do, and both are placed from the same progress value in the same transaction, so they
/// animate together (or jump together under Reduce Motion).
struct ClimbProgressArtworkView: View {
    let artwork: ClimbProgressArtwork
    /// The artwork's own image, at the canvas size its bounds were measured on.
    let image: UIImage
    let completedSteps: Int
    let totalSteps: Int?
    /// Where the climber's previous best had reached at this moment, as a fraction of the
    /// summit, or nil when there is none to race.
    var previousBestFraction: Double?
    var markerColor: Color = .accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let markerThickness: CGFloat = 2
    /// How far the line runs past each side of the space it is given, so it still reads as a
    /// level across a slender spire rather than a tick on it.
    private static let markerOverhang: CGFloat = 8

    private var progress: Double {
        ClimbProgressFraction.resolve(completedSteps: completedSteps, totalSteps: totalSteps)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = ClimbProgressArtworkLayout(artwork: artwork, fitting: proxy.size)
            // The landmark stands on the bottom edge of the space it is given, centred across it.
            let landmarkOrigin = CGPoint(
                x: (proxy.size.width - layout.displaySize.width) / 2,
                y: proxy.size.height - layout.displaySize.height
            )

            ZStack(alignment: .topLeading) {
                landmark(layout: layout)
                    .grayscale(1)
                    .brightness(-0.06)
                    .opacity(0.4)
                    .offset(x: landmarkOrigin.x, y: landmarkOrigin.y)

                landmark(layout: layout)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: max(layout.displaySize.height - layout.revealTop(progress: progress), 0))
                    }
                    .offset(x: landmarkOrigin.x, y: landmarkOrigin.y)

                if let previousBestFraction {
                    previousBestMarker(width: proxy.size.width + Self.markerOverhang * 2)
                        .offset(
                            x: -Self.markerOverhang,
                            y: landmarkOrigin.y + layout.markerY(progress: previousBestFraction) - 0.5
                        )
                }

                Rectangle()
                    .fill(markerColor)
                    .frame(width: proxy.size.width + Self.markerOverhang * 2, height: Self.markerThickness)
                    .shadow(color: markerColor.opacity(0.75), radius: 4)
                    .offset(
                        x: -Self.markerOverhang,
                        y: landmarkOrigin.y + layout.markerY(progress: progress) - Self.markerThickness / 2
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Climb progress")
        .accessibilityValue("\(Int((progress * 100).rounded(.down))) percent")
    }

    /// The visible landmark alone: the full canvas drawn at `layout.scale` and shifted so its
    /// transparent padding falls outside a frame the exact size of the landmark. Drawn as an
    /// overlay on a view that takes exactly that size, so the larger canvas never becomes this
    /// view's layout size.
    private func landmark(layout: ClimbProgressArtworkLayout) -> some View {
        Color.clear
            .frame(width: layout.displaySize.width, height: layout.displaySize.height)
            .overlay(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .offset(x: layout.canvasOrigin.x, y: layout.canvasOrigin.y)
            }
            .clipped()
    }

    /// The climber's previous best, drawn as a hairline across the landmark with the word only -
    /// no comparison number, the same rule `LiveReplayPreviousBestMarker` keeps on the bars.
    private func previousBestMarker(width: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.8))
            .frame(width: width, height: 1)
            .overlay(alignment: .bottomLeading) {
                Text("BEST")
                    .font(.montserratBold(size: 8))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .fixedSize()
                    .offset(y: -3)
            }
    }
}

#if DEBUG
/// Previews read the pilot cut-outs the test suites use (`TestFixtures/climb-progress/`); the
/// app bundles none, since every cut-out is fetched from Storage.
private struct ClimbProgressArtworkPreviewGrid: View {
    let climb: Climb

    var body: some View {
        if let artwork = climb.progressArtwork, let image = Self.fixtureImage(for: climb.id) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                    VStack(spacing: 6) {
                        ClimbProgressArtworkView(
                            artwork: artwork,
                            image: image,
                            completedSteps: climb.referenceStepCount * percent / 100,
                            totalSteps: climb.referenceStepCount
                        )
                        .frame(width: 68, height: 220)

                        Text("\(percent)%")
                            .font(.montserratBold(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(16)
            .background(Color.black)
        }
    }

    private static func fixtureImage(for climbID: String) -> UIImage? {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return UIImage(contentsOfFile: repositoryRoot
            .appending(path: "TestFixtures/climb-progress/\(climbID)-progress.png")
            .path(percentEncoded: false))
    }
}

private func previewClimb(_ climbID: String) -> Climb? {
    guard let url = Bundle.main.url(forResource: "climbs", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let climbs = try? JSONDecoder().decode([Climb].self, from: data) else {
        return nil
    }
    return climbs.first { $0.id == climbID }
}

#Preview("Empire State Building 0-100%") {
    if let climb = previewClimb("empire-state-building") {
        ClimbProgressArtworkPreviewGrid(climb: climb)
    }
}

#Preview("Eiffel Tower 0-100%") {
    if let climb = previewClimb("eiffel-tower") {
        ClimbProgressArtworkPreviewGrid(climb: climb)
    }
}

#Preview("Charminar 0-100%") {
    if let climb = previewClimb("charminar") {
        ClimbProgressArtworkPreviewGrid(climb: climb)
    }
}
#endif
