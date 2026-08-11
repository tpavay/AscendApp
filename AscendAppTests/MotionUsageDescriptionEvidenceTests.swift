import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Motion & Fitness permission alert (#322).
///
/// The message is the only part of that alert Ascend owns, and it is read straight from
/// `Bundle.main` here - the built app bundle - so the PNG cannot drift from the string iOS will
/// actually show. The chrome around it is a reproduction at the system alert's own metrics: 270pt
/// panel, SF at the alert's title and message sizes, and the title and buttons iOS supplies on
/// device. That reproduction is deliberate - a live `UIAlertController` is presented in its own
/// window and draws through a hierarchy neither `drawHierarchy` nor `layer.render(in:)` can reach
/// in a test host with no screen, so photographing one yields an empty backdrop rather than an
/// alert. Drawing the panel puts the shipped sentence in front of a reviewer at its real width and
/// line breaks, with no screen involved and the same pixels on every machine.
@MainActor
struct MotionUsageDescriptionEvidenceTests {
    /// What the alert said before this fix: two of the three features that read the sensor were
    /// missing from it. Rendered alongside the shipped string so the difference is reviewable.
    private static let previousUsageDescription =
        "Ascend uses motion from compatible headphones to track steps during Live Climbs."

    /// App Review reads this on the alert; past ~140 characters it starts to truncate.
    private static let maximumLength = 140

    private static let alertTitle = "\u{201C}Ascend\u{201D} Would Like to Access Your Motion & Fitness Activity"

    @Test
    func shippedUsageDescriptionNamesEveryFeatureThatReadsHeadphoneMotion() throws {
        let value = try Self.shippedUsageDescription()

        #expect(value.count <= Self.maximumLength)

        for phrase in ["compatible headphones", "steps", "Live Climbs", "Just Climb", "routines"] {
            #expect(value.contains(phrase), "The motion usage description omits \(phrase): \(value)")
        }
    }

    @Test
    func rendersTheMotionPermissionAlertTheClimberWillSee() throws {
        let shipped = try Self.shippedUsageDescription()

        let shippedAlert = try Self.renderAlert(
            message: shipped,
            fileName: "motion-permission-alert-shipped.png"
        )
        let previousAlert = try Self.renderAlert(
            message: Self.previousUsageDescription,
            fileName: "motion-permission-alert-previous.png"
        )

        #expect(shippedAlert != previousAlert, "Both alerts rendered the same pixels")
    }

    private static func shippedUsageDescription() throws -> String {
        try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String,
            "The built app bundle carries no NSMotionUsageDescription"
        )
    }

    @discardableResult
    private static func renderAlert(message: String, fileName: String) throws -> Data {
        let renderer = ImageRenderer(
            content: MotionPermissionAlertProof(title: alertTitle, message: message)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: fileName))

        #expect(png.count > 5_000, "\(fileName) rendered an implausibly small image")
        // A capture that drew no panel is still a valid PNG of the flat backdrop, so the proof
        // that the alert is in the picture is that the picture is not one flat colour.
        #expect(
            luminanceSpread(of: image) > 0.05,
            "\(fileName) rendered the bare backdrop instead of the alert"
        )

        return png
    }

    /// The difference between the brightest and darkest cell of a coarse downsample of the capture.
    /// A backdrop with nothing drawn over it scores zero; the alert's panel and white copy score
    /// far above the threshold.
    private static func luminanceSpread(of image: UIImage) -> Double {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        guard let cgImage = image.cgImage else {
            return 0
        }

        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        var darkest = Double.greatestFiniteMagnitude
        var brightest = -Double.greatestFiniteMagnitude

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            let luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255

            darkest = min(darkest, luminance)
            brightest = max(brightest, luminance)
        }

        return brightest - darkest
    }
}

// MARK: - Views

/// The Motion & Fitness alert at the system's own metrics, in the dark appearance Ascend runs in.
/// Every colour is stated rather than resolved from the environment, so the proof renders the same
/// picture wherever it runs.
private struct MotionPermissionAlertProof: View {
    let title: String
    let message: String

    private static let panelWidth: CGFloat = 270
    private static let separator = Color.white.opacity(0.16)

    var body: some View {
        ZStack {
            Color(white: 0.06)

            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(message)
                        .font(.system(size: 13))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 19)
                .padding(.bottom, 20)

                Self.separator.frame(height: 0.5)

                HStack(spacing: 0) {
                    button("Don\u{2019}t Allow", weight: .regular)
                    Self.separator.frame(width: 0.5)
                    button("OK", weight: .semibold)
                }
                .frame(height: 44)
            }
            .frame(width: Self.panelWidth)
            .background(Color(white: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: 402, height: 420)
    }

    private func button(_ label: String, weight: Font.Weight) -> some View {
        Text(label)
            .font(.system(size: 17, weight: weight))
            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
