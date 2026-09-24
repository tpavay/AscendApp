import CoreGraphics
import Foundation

/// A landmark cut-out that reveals in colour, bottom to top, as a live climb progresses.
///
/// Content, not code: each catalog entry carries its own (`Climb.progressArtwork`), the image
/// lives in Storage at `path` beside the climb's other artwork, and adding or replacing one is a
/// catalog and bucket change with no app release. A new image goes to a new `path`, because the
/// disk cache keys on it and treats it as immutable.
///
/// The PNG canvases carry transparent padding, so every geometric question is answered from
/// the measured bounds rather than the canvas: the displayed frame is the visible landmark
/// alone, and the reveal line runs between `progressBottomY` (the base) and `progressTopY` (the
/// tip). Both are fractions of the canvas height, origin top-left.
struct ClimbProgressArtwork: Codable, Hashable, Sendable {
    struct PixelBounds: Codable, Hashable, Sendable {
        /// Inclusive.
        let left: Int
        /// Inclusive.
        let top: Int
        /// Exclusive.
        let right: Int
        /// Exclusive.
        let bottom: Int

        var width: Int { right - left }
        var height: Int { bottom - top }
    }

    /// The Storage object path, e.g. `climb-images/charminar/progress/v1.png`.
    let path: String
    let canvasWidth: Int
    let canvasHeight: Int
    let visibleBoundsPixels: PixelBounds
    let progressTopY: Double
    let progressBottomY: Double
    /// The catalog's optional `layout` pin, verbatim. Anything but a recognised
    /// `ClimbProgressLayout` value is ignored and the aspect rule decides.
    var layoutOverride: String?
    /// The PNG's SHA-256, hex. A download that does not match is discarded, never cached.
    let sha256: String?

    private enum CodingKeys: String, CodingKey {
        case path, canvasWidth, canvasHeight, visibleBoundsPixels, progressTopY, progressBottomY, sha256
        case layoutOverride = "layout"
    }

    init(
        path: String,
        canvasWidth: Int,
        canvasHeight: Int,
        visibleBoundsPixels: PixelBounds,
        progressTopY: Double,
        progressBottomY: Double,
        layoutOverride: String? = nil,
        sha256: String? = nil
    ) {
        self.path = path
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.visibleBoundsPixels = visibleBoundsPixels
        self.progressTopY = progressTopY
        self.progressBottomY = progressBottomY
        self.layoutOverride = layoutOverride
        self.sha256 = sha256
    }

    /// Whether this entry can be drawn for `climbID`: sound geometry, and an image path inside
    /// that climb's own artwork folder - a catalog typo can never point one climb at another's
    /// art, or at anything outside the climb imagery.
    func isUsable(forClimbID climbID: String) -> Bool {
        isGeometricallyValid
            && path.hasPrefix("climb-images/\(climbID)/")
            && !path.contains("..")
    }

    /// Width over height of the visible landmark, which is the only shape it is ever drawn at.
    var visibleAspectRatio: CGFloat {
        CGFloat(max(visibleBoundsPixels.width, 1)) / CGFloat(max(visibleBoundsPixels.height, 1))
    }

    /// Landmarks at least this wide for their height (Charminar 0.61, stadiums, castles)
    /// run across the full width above the metrics; narrower ones (the Empire State Building
    /// 0.24, the Eiffel Tower 0.56) stand beside them. Eiffel and Charminar sit only 8% apart,
    /// so a re-crop can carry a landmark across this line - which is what `layoutOverride` is for.
    static let stackedLayoutMinimumAspectRatio: CGFloat = 0.58

    /// The Just Me layout this landmark gets: the manifest's pin when it names a real layout,
    /// otherwise the aspect rule.
    var layout: ClimbProgressLayout {
        if let layoutOverride, let pinned = ClimbProgressLayout(rawValue: layoutOverride) {
            return pinned
        }
        return visibleAspectRatio >= Self.stackedLayoutMinimumAspectRatio ? .stacked : .sideBySide
    }

    /// Whether the numbers describe a drawable landmark. An entry that fails this is ignored,
    /// so its climb keeps the ordinary Just Me layout instead of a misaligned reveal.
    var isGeometricallyValid: Bool {
        let bounds = visibleBoundsPixels
        guard canvasWidth > 0, canvasHeight > 0,
              bounds.left >= 0, bounds.top >= 0,
              bounds.right <= canvasWidth, bounds.bottom <= canvasHeight,
              bounds.width > 0, bounds.height > 0,
              progressTopY.isFinite, progressBottomY.isFinite,
              progressTopY >= 0, progressBottomY <= 1,
              progressTopY < progressBottomY else {
            return false
        }

        // The reveal line has to travel inside the visible landmark, or it would start or stop
        // in empty padding. Half a pixel of slack absorbs the manifest's rounding.
        let topPixel = progressTopY * Double(canvasHeight)
        let bottomPixel = progressBottomY * Double(canvasHeight)
        return topPixel >= Double(bounds.top) - 0.5 && bottomPixel <= Double(bounds.bottom) + 0.5
    }
}

/// How the Just Me tab arranges a landmark and its metrics. The raw values are the manifest's
/// `layout` vocabulary.
enum ClimbProgressLayout: String, Sendable {
    /// Landmark on the left, metrics in a column beside it - for tall, narrow landmarks.
    case sideBySide = "side-by-side"
    /// Landmark across the full width, metrics in a grid below it - for wide, stocky ones.
    case stacked
}

/// Where the landmark sits once fitted into the space a screen offers it, and where the reveal
/// line falls for a given progress. Pure geometry, so alignment is testable without a view.
struct ClimbProgressArtworkLayout: Equatable {
    /// Points per canvas pixel. One scale for both axes: the landmark is never stretched.
    let scale: CGFloat
    /// The visible landmark, cropped from its padding and scaled.
    let displaySize: CGSize
    /// Where the full canvas's top-left corner sits relative to the displayed landmark's.
    let canvasOrigin: CGPoint
    /// The whole canvas at `scale`, which the image layers are drawn at before cropping.
    let canvasSize: CGSize

    private let progressTopInDisplay: CGFloat
    private let progressBottomInDisplay: CGFloat

    init(artwork: ClimbProgressArtwork, fitting available: CGSize) {
        let bounds = artwork.visibleBoundsPixels
        let visibleWidth = CGFloat(max(bounds.width, 1))
        let visibleHeight = CGFloat(max(bounds.height, 1))
        let widthScale = max(available.width, 0) / visibleWidth
        let heightScale = max(available.height, 0) / visibleHeight
        let scale = max(min(widthScale, heightScale), 0)

        self.scale = scale
        displaySize = CGSize(width: visibleWidth * scale, height: visibleHeight * scale)
        canvasOrigin = CGPoint(x: -CGFloat(bounds.left) * scale, y: -CGFloat(bounds.top) * scale)
        canvasSize = CGSize(
            width: CGFloat(artwork.canvasWidth) * scale,
            height: CGFloat(artwork.canvasHeight) * scale
        )
        progressTopInDisplay = (artwork.progressTopY * CGFloat(artwork.canvasHeight) - CGFloat(bounds.top)) * scale
        progressBottomInDisplay = (artwork.progressBottomY * CGFloat(artwork.canvasHeight) - CGFloat(bounds.top)) * scale
    }

    /// The reveal boundary's y, measured down from the top of the displayed landmark.
    /// `progress` is clamped, so 0 sits on the base and 1 on the tip.
    func markerY(progress: Double) -> CGFloat {
        let clamped = ClimbProgressFraction.clamped(progress)
        return progressBottomInDisplay - CGFloat(clamped) * (progressBottomInDisplay - progressTopInDisplay)
    }

    /// The top of the coloured region. It is the marker until the climb is done, and then the
    /// whole image, so a tip drawn above `progressTopY` never stays grey on a finished climb.
    func revealTop(progress: Double) -> CGFloat {
        ClimbProgressFraction.clamped(progress) >= 1 ? 0 : markerY(progress: progress)
    }
}

/// Completed steps as a fraction of the summit, safe against every input a session can hand it.
enum ClimbProgressFraction {
    static func resolve(completedSteps: Int, totalSteps: Int?) -> Double {
        guard let totalSteps, totalSteps > 0 else { return 0 }
        return clamped(Double(completedSteps) / Double(totalSteps))
    }

    static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}
