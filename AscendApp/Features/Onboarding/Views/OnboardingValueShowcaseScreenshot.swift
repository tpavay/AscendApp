import SwiftUI

struct OnboardingValueShowcaseScreenshot: View {
    let imageName: String
    var style: OnboardingValueScreenshotFrameStyle

    var body: some View {
        ZStack(alignment: .top) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: renderedImageWidth, height: renderedImageHeight, alignment: .top)
                .clipped()
                .offset(y: -style.topCrop)
        }
        .frame(width: style.width, height: style.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(style.borderOpacity), lineWidth: style.borderWidth)
        }
        .shadow(
            color: .black.opacity(style.shadowOpacity),
            radius: style.shadowRadius,
            x: 0,
            y: style.shadowYOffset
        )
        .allowsHitTesting(false)
    }

    private var renderedImageHeight: CGFloat {
        max(style.width * style.sourceAspectRatio, style.height + style.topCrop)
    }

    private var renderedImageWidth: CGFloat {
        renderedImageHeight / style.sourceAspectRatio
    }
}
