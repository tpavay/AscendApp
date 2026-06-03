import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Applies the geometric (Core Image) share filters — zoom blur, motion blur,
/// fisheye — to a source photo. Color grades are handled separately by SwiftUI
/// modifiers (`View.shareBackgroundFilter(_:)`); this only covers effects that
/// must process pixels.
///
/// Pure and `nonisolated` so it can run off the main actor. Results are cached
/// by the caller (the view model) so each filter is computed once per photo.
enum ShareImageFilter {
    /// One GPU-backed context, reused across renders (creating a context is the
    /// expensive part). `CIContext` is safe to use concurrently for rendering.
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

    nonisolated static func apply(_ filter: ShareBackgroundFilter, to image: UIImage) -> UIImage? {
        guard filter.isGeometric, let cgInput = image.cgImage else { return nil }

        let input = CIImage(cgImage: cgInput)
        let extent = input.extent
        let minSide = min(extent.width, extent.height)
        let centerPoint = CGPoint(x: extent.midX, y: extent.midY)

        let output: CIImage?
        switch filter {
        case .zoomBlur:
            let f = CIFilter.zoomBlur()
            f.inputImage = input
            f.center = centerPoint
            f.amount = Float(minSide * 0.035)
            output = f.outputImage

        case .motionBlur:
            let f = CIFilter.motionBlur()
            f.inputImage = input
            f.radius = Float(minSide * 0.02)
            f.angle = 0
            output = f.outputImage

        case .fisheye:
            let f = CIFilter.bumpDistortion()
            f.inputImage = input
            f.center = centerPoint
            f.radius = Float(minSide * 0.6)
            f.scale = 0.55
            output = f.outputImage

        default:
            output = nil
        }

        // Blur/distortion can grow or soften the extent — crop back to the
        // original frame so the result stays the same size as the input.
        guard let cropped = output?.cropped(to: extent),
              let cg = context.createCGImage(cropped, from: extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
