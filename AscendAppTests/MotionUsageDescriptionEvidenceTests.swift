import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Visual evidence for the Motion & Fitness permission alert (#322).
///
/// The message is the only part of that alert Ascend owns, and it is read straight from
/// `Bundle.main` here - the built app bundle - so the photograph cannot drift from the string iOS
/// will actually show. The chrome around it is a reproduction at the system alert's own metrics: 270pt
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
            fileName: "motion-permission-alert-shipped"
        )
        let previousAlert = try Self.renderAlert(
            message: Self.previousUsageDescription,
            fileName: "motion-permission-alert-previous"
        )

        #expect(shippedAlert != previousAlert, "Both alerts rendered the same pixels")
    }

    private static func shippedUsageDescription() throws -> String {
        try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String,
            "The built app bundle carries no NSMotionUsageDescription"
        )
    }

    /// The alert's pixels at 1x - a message that changed reads differently at any scale - with
    /// the 3x photograph written only under `ASCEND_EVIDENCE_DIR`.
    private static func renderAlert(message: String, fileName: String) throws -> [RGBA] {
        let proof = MotionPermissionAlertProof(title: alertTitle, message: message)

        let pixels = try RenderedScreen.withOffscreenPixels(of: proof) { pixels -> [RGBA] in
            // A capture that drew no panel is still a valid bitmap of the flat backdrop, so the
            // proof that the alert is in the picture is that the picture is not one flat colour.
            #expect(
                luminanceSpread(of: pixels) > 0.05,
                "\(fileName) rendered the bare backdrop instead of the alert"
            )
            return pixels.pixels(in: CGRect(origin: .zero, size: pixels.size))
        }
        try RenderedScreen.photograph(proof, named: fileName)

        return pixels
    }

    /// The difference between the brightest and darkest pixel of the capture, on a 0...1 scale.
    /// A backdrop with nothing drawn over it scores zero; the alert's panel and white copy score
    /// far above the threshold.
    private static func luminanceSpread(of pixels: PixelSampler) -> Double {
        let range = pixels.luminanceRange()
        return (range.upperBound - range.lowerBound) / 255
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
