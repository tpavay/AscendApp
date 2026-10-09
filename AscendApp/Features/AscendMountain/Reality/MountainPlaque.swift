import Foundation
import RealityKit
import UIKit

/// The plaque carrying a marker's words: a gate's lintel number, a trail post's step count, the
/// sign at the climber's best. One drawing for every marker, so the numbers read the same all the
/// way up the mountain.
@MainActor
enum MountainPlaque {
    /// The drawn plaque, in pixels; every face is this image stretched to its own size.
    nonisolated static let imageSize = CGSize(width: 1_024, height: 512)
    /// Stone showing either side of the widest title. A post stands at every hundred steps for
    /// the climber's whole life on the mountain, so its number grows to `100,100` and beyond,
    /// and a number the border clips is a number nobody can read.
    nonisolated static let titleMargin: CGFloat = 72
    /// Ascend lime, the colour of what the climber has earned.
    nonisolated static let earnedAccent = MountainColor(red: 0.53, green: 0.83, blue: 0.04)

    /// A plaque carrying the marker's words. The words are drawn off the main actor - a plaque
    /// image is tens of milliseconds, more than a frame - and a marker appears far up the stairs,
    /// so its face shows plain stone for the moment until they arrive.
    static func face(
        width: Float,
        height: Float,
        cornerRadius: Float,
        title: String,
        subtitle: String?,
        accent: MountainColor = earnedAccent,
        titleSize: CGFloat = 250
    ) -> ModelEntity {
        let face = ModelEntity(
            mesh: .generatePlane(width: width, height: height, cornerRadius: cornerRadius),
            materials: [UnlitMaterial(color: UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1))]
        )
        Task { [weak face] in
            let image = await Task.detached(priority: .utility) {
                Self.image(title: title, subtitle: subtitle, accent: accent, titleSize: titleSize)
            }.value
            guard let image, let face,
                  let texture = try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { return }
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            material.color = .init(tint: .white, texture: .init(texture))
            face.model?.materials = [material]
        }
        return face
    }

    nonisolated static func titleFont(size: CGFloat) -> UIFont {
        UIFont(name: "Montserrat-Bold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }

    /// The largest title size up to `requested` at which the whole title fits between the
    /// margins on one line. A short number keeps the requested size, so neighbouring posts match.
    nonisolated static func fittedTitleSize(for title: String, requested: CGFloat) -> CGFloat {
        let usable = imageSize.width - titleMargin * 2
        let natural = (title as NSString).size(withAttributes: [.font: titleFont(size: requested)]).width
        guard natural > usable, natural > 0 else { return requested }
        return (requested * usable / natural).rounded(.down)
    }

    /// The marker's words on dark stone: the number large, the unit in the accent.
    nonisolated static func image(title: String, subtitle: String?, accent: MountainColor, titleSize: CGFloat) -> CGImage? {
        let size = imageSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 36).fill()
            UIColor(white: 1, alpha: 0.14).setStroke()
            let border = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14), cornerRadius: 26)
            border.lineWidth = 6
            border.stroke()

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byClipping
            let fittedSize = fittedTitleSize(for: title, requested: titleSize)
            let titleFont = titleFont(size: fittedSize)
            let subtitleFont = UIFont(name: "Montserrat-Bold", size: 92) ?? .systemFont(ofSize: 92, weight: .bold)
            let titleHeight: CGFloat = subtitle == nil ? 330 : 290
            (title as NSString).draw(
                // A smaller title sits lower in the same band, so it stays centred over the unit.
                in: CGRect(x: 0, y: (subtitle == nil ? 80 : 30) + (250 - fittedSize) * 0.6, width: size.width, height: titleHeight),
                withAttributes: [.font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: style]
            )
            if let subtitle {
                (subtitle as NSString).draw(
                    in: CGRect(x: 0, y: 330, width: size.width, height: 130),
                    withAttributes: [.font: subtitleFont, .foregroundColor: UIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 1), .kern: 14, .paragraphStyle: style]
                )
            }
        }
        return image.cgImage
    }
}
