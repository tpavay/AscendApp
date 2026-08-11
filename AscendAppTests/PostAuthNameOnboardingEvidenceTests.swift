import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// End-to-end visual evidence for the two-field name step.
///
/// `PostAuthNameInputTests` holds the gate and the resolver in isolation. This
/// holds what the climber actually sees: CONTINUE stays dead until both fields
/// carry a name, and the name they type is the one their profile header reads
/// afterwards - while a legacy account that never supplied two halves keeps
/// rendering the display name it already ranks under.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct PostAuthNameOnboardingEvidenceTests {
    private static let canvas = CGSize(width: 402, height: 874)

    @Test("CONTINUE stays dead until both name fields carry a name", .bug(id: 394))
    func continueUnlocksOnlyAfterBothFieldsAreTyped() async throws {
        let controller = UIHostingController(
            rootView: PostAuthOnboardingFlowView(
                stage: .displayName,
                onBack: {},
                onContinue: {}
            )
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: Self.canvas)

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await settle(controller)
        let empty = capture(controller)

        let fields = textFields(in: controller.view)
        #expect(fields.count == 2, "The name step must show two fields")
        let firstNameField = try #require(fields.first)
        let lastNameField = try #require(fields.last)

        firstNameField.becomeFirstResponder()
        firstNameField.insertText("Maya")
        try await settle(controller)
        let firstOnly = capture(controller)

        lastNameField.becomeFirstResponder()
        lastNameField.insertText("Chen")
        try await settle(controller)
        let bothTyped = capture(controller)

        let emptyContinue = continueButtonIntensity(in: empty)
        let firstOnlyContinue = continueButtonIntensity(in: firstOnly)
        let bothTypedContinue = continueButtonIntensity(in: bothTyped)

        // A live CONTINUE is the lime fill; a dead one is the same fill dimmed.
        #expect(bothTypedContinue > emptyContinue * 2)
        #expect(bothTypedContinue > firstOnlyContinue * 2)

        let typedText = try await recognizedText(in: bothTyped)
        #expect(typedText.contains("maya"))
        #expect(typedText.contains("chen"))

        let firstOnlyText = try await recognizedText(in: firstOnly)
        #expect(firstOnlyText.contains("maya"))
        #expect(firstOnlyText.contains("last name"), "The unfilled half keeps its prompt")

        try writeEvidence(
            image: filmstrip(
                panels: [
                    ("Nothing typed - CONTINUE dead", empty),
                    ("First name only - CONTINUE dead", firstOnly),
                    ("Both names - CONTINUE live", bothTyped)
                ]
            ),
            named: "onboarding-name-continue-gate.png"
        )
    }

    @Test("The profile header reads the composed name, not a placeholder", .bug(id: 394))
    func profileHeaderReadsTheComposedNameAndLeavesLegacyAlone() async throws {
        let onboarded = UserDisplayNameData([
            "firstName": "Maya",
            "lastName": "Chen",
            "displayName": "Maya Chen"
        ])
        let legacy = UserDisplayNameData([
            "displayName": "Legacy Climber"
        ])

        #expect(onboarded.resolvedDisplayName == "Maya Chen")
        #expect(legacy.firstName == nil)
        #expect(legacy.lastName == nil)
        #expect(legacy.resolvedDisplayName == "Legacy Climber")

        let image = try render(
            VStack(spacing: 0) {
                headerPanel(
                    caption: "COMPLETED THE NEW NAME STEP",
                    userId: "maya-chen",
                    storedProfile: onboarded
                )
                headerPanel(
                    caption: "LEGACY ACCOUNT - NEVER SPLIT OR BACKFILLED",
                    userId: "legacy-climber",
                    storedProfile: legacy
                )
            }
            .frame(width: Self.canvas.width)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )

        let text = try await recognizedText(in: image)
        #expect(text.contains("maya chen"))
        #expect(text.contains("legacy climber"))
        #expect(text.contains("you") == false, "The placeholder must be gone")

        try writeEvidence(image: image, named: "profile-header-composed-name.png")
    }

    // MARK: - Rendering helpers

    private func headerPanel(
        caption: String,
        userId: String,
        storedProfile: UserDisplayNameData
    ) -> some View {
        let displayName = storedProfile.resolvedDisplayName ?? ""
        let identity = ResolvedUserIdentity.Resolver.resolve(
            userId: userId,
            displayName: displayName,
            photoURL: nil,
            avatarToken: PublicClimberIdentity.avatarToken(for: displayName),
            isCurrentUser: true,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(Color.ascendAccent)
                .padding(.horizontal, 16)

            IdentityHeroSection(
                snapshot: Self.emptySnapshot(userId: userId),
                identity: identity
            )
        }
        .padding(.vertical, 16)
    }

    private static func emptySnapshot(userId: String) -> ProfileSnapshot {
        ProfileSnapshot(
            demographics: ProfileDemographicsSnapshot(
                userId: userId,
                joinedAt: Date(timeIntervalSince1970: 1_754_000_000)
            ),
            stats: .empty,
            standings: [],
            activityWorkouts: [],
            collection: ProfileCollectionSummary(
                collectedCount: 0,
                catalogCount: 0,
                previewCards: [],
                launchedCards: [],
                comingSoonClimbs: []
            ),
            achievements: .empty,
            firstAscentsHeld: [],
            openFirstAscents: [],
            records: ProfileRecordSummary(personalRecords: [], featuredBestEffort: nil),
            trends: ProfileTrendSummary(currentSteps: 0, previousSteps: 0, daysWithData: 0),
            recentWorkouts: []
        )
    }

    private func render(_ content: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    private func settle(_ controller: UIHostingController<some View>) async throws {
        for _ in 0..<8 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func capture(_ controller: UIHostingController<some View>) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        return UIGraphicsImageRenderer(size: Self.canvas, format: format).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
    }

    private func textFields(in view: UIView) -> [UITextField] {
        var found: [UITextField] = []
        if let field = view as? UITextField {
            found.append(field)
        }
        for subview in view.subviews {
            found.append(contentsOf: textFields(in: subview))
        }
        return found.sorted {
            $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY
        }
    }

    private func filmstrip(panels: [(String, UIImage)]) -> UIImage {
        let captionHeight: CGFloat = 26
        let gutter: CGFloat = 12
        let panelWidth = Self.canvas.width
        let size = CGSize(
            width: panelWidth * CGFloat(panels.count) + gutter * CGFloat(panels.count + 1),
            height: Self.canvas.height + captionHeight + gutter * 2
        )

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for (index, panel) in panels.enumerated() {
                let originX = gutter + (panelWidth + gutter) * CGFloat(index)
                (panel.0 as NSString).draw(
                    at: CGPoint(x: originX, y: gutter),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: UIColor.white
                    ]
                )
                panel.1.draw(
                    in: CGRect(
                        x: originX,
                        y: gutter + captionHeight,
                        width: panelWidth,
                        height: Self.canvas.height
                    )
                )
            }
        }
    }

    // MARK: - Reading the rendered pixels back

    /// Mean green channel across the CONTINUE button's fill. The button sits at
    /// a fixed fraction of the screen it owns, so the sample needs no layout
    /// introspection to find it.
    private func continueButtonIntensity(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let sample = CGRect(
            x: Double(cgImage.width) * 0.40,
            y: Double(cgImage.height) * 0.875,
            width: Double(cgImage.width) * 0.20,
            height: Double(cgImage.height) * 0.02
        )
        guard let cropped = cgImage.cropping(to: sample) else { return 0 }

        let width = cropped.width
        let height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        let greenTotal = stride(from: 1, to: pixels.count, by: 4)
            .reduce(0.0) { $0 + Double(pixels[$1]) }
        return greenTotal / Double(width * height)
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let outputURL = URL(filePath: directory).appending(path: name)
        try png.write(to: outputURL)
        #expect(png.count > 5_000)
        print("Rendered onboarding name evidence: \(outputURL.path())")
    }
}
