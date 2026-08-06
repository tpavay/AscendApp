import Foundation
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Motion & Fitness permission alert (#322).
///
/// The message is the only part of that alert Ascend owns, and it is read straight from
/// `Bundle.main` here - the built app bundle - so the PNG cannot drift from the string iOS will
/// actually show. The surrounding chrome is a real `UIAlertController`, the same component the
/// system alert is drawn with; its title and buttons are supplied by iOS on device and are
/// reproduced here so the message can be reviewed at its real width and line breaks.
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
    func rendersTheMotionPermissionAlertTheClimberWillSee() async throws {
        let shipped = try Self.shippedUsageDescription()

        let shippedAlert = try await Self.renderAlert(
            message: shipped,
            fileName: "motion-permission-alert-shipped.png"
        )
        let previousAlert = try await Self.renderAlert(
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
    private static func renderAlert(message: String, fileName: String) async throws -> Data {
        // The alert has to be in a window the simulator is actually drawing, or
        // `drawHierarchy(afterScreenUpdates:)` captures nothing.
        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "The test host has no window scene to render into"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark

        let host = UIViewController()
        host.view.backgroundColor = UIColor(white: 0.06, alpha: 1)
        window.rootViewController = host
        window.makeKeyAndVisible()

        let alert = UIAlertController(title: alertTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Don\u{2019}t Allow", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        await withCheckedContinuation { continuation in
            host.present(alert, animated: false) {
                continuation.resume()
            }
        }

        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: fileName))

        #expect(png.count > 5_000, "\(fileName) rendered an implausibly small image")
        // A window that never reached the screen renders blank white, which is
        // still a valid PNG - the dark alert is the proof that it did.
        #expect(
            averageLuminance(of: image) < 0.5,
            "\(fileName) rendered blank instead of the alert"
        )

        await withCheckedContinuation { continuation in
            alert.dismiss(animated: false) { continuation.resume() }
        }
        window.isHidden = true

        return png
    }

    private static func averageLuminance(of image: UIImage) -> Double {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let context, let cgImage = image.cgImage else {
            return 1
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2]))
            / 255
    }
}
