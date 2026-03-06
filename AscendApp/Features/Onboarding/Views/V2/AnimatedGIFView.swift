import ImageIO
import SwiftUI
import UIKit

struct AnimatedGIFView: UIViewRepresentable {
    let data: Data
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var zoomScale: CGFloat = 1
    var normalizedCropRect: CGRect? = nil

    final class ContainerView: UIView {
        let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.clipsToBounds = true
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    func makeUIView(context: Context) -> ContainerView {
        let containerView = ContainerView()
        containerView.imageView.contentMode = contentMode
        containerView.imageView.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        configureAnimation(on: containerView.imageView)
        return containerView
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.imageView.contentMode = contentMode
        uiView.imageView.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)

        guard uiView.imageView.animationImages == nil else {
            return
        }

        configureAnimation(on: uiView.imageView)
    }

    private func configureAnimation(on imageView: UIImageView) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            return
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)

        var totalDuration: Double = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            let frameDuration = frameDurationAtIndex(index, source: source)
            totalDuration += frameDuration

            if let croppedImage = croppedFrame(from: cgImage) {
                frames.append(UIImage(cgImage: croppedImage))
            } else {
                frames.append(UIImage(cgImage: cgImage))
            }
        }

        guard !frames.isEmpty else {
            return
        }

        if totalDuration <= 0 {
            totalDuration = Double(frames.count) * 0.1
        }

        imageView.animationImages = frames
        imageView.animationDuration = totalDuration
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
    }

    private func frameDurationAtIndex(_ index: Int, source: CGImageSource) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let duration = unclampedDelay ?? delay ?? 0.1

        return duration < 0.011 ? 0.1 : duration
    }

    private func croppedFrame(from cgImage: CGImage) -> CGImage? {
        guard let normalizedCropRect else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let pixelRect = CGRect(
            x: normalizedCropRect.origin.x * imageWidth,
            y: normalizedCropRect.origin.y * imageHeight,
            width: normalizedCropRect.size.width * imageWidth,
            height: normalizedCropRect.size.height * imageHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard pixelRect.width > 0, pixelRect.height > 0 else {
            return nil
        }

        return cgImage.cropping(to: pixelRect)
    }
}
