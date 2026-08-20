import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// What the App Review reviewer will actually see on the screen that got 1.0
/// rejected under Guideline 4.
///
/// `SignInSuppliedIdentityTests` holds the decision table. This holds the pixels:
/// when the provider shared only half a name the step opens with that half
/// already filled in, so the climber is asked for the half they withheld and
/// nothing else. When the provider shared a full name this step does not run at
/// all - the name is on the profile before onboarding resolves the stage - and
/// when nothing was supplied the step still carries a real way past.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct SignInNameStepEvidenceTests {
    private static let canvas = CGSize(width: 402, height: 874)
    private static let providerUserID = "000789.apple"

    @Test("The half Apple supplied arrives already filled in")
    func theStepOpensSeededWithWhateverAppleSupplied() async throws {
        let seeded = try await renderNameStep(
            supplied: SignInSuppliedIdentity(
                providerUserID: Self.providerUserID,
                firstName: "Maya",
                lastName: nil,
                email: "8xk2p9qz7t@privaterelay.appleid.com"
            )
        )
        let unseeded = try await renderNameStep(supplied: nil)

        let seededText = try await recognizedText(in: seeded.image)
        #expect(
            seededText.contains("maya"),
            "The name Apple supplied must already be in the field"
        )
        #expect(
            seededText.contains("last name"),
            "Only the half Apple withheld keeps its prompt"
        )

        let seededFields = seeded.fieldValues
        #expect(seededFields.first == "Maya")
        #expect(seededFields.last == "")

        // Nothing supplied means nothing seeded: both fields still start empty.
        #expect(unseeded.fieldValues == ["", ""])
        let unseededText = try await recognizedText(in: unseeded.image)
        #expect(unseededText.contains("first name"))
        #expect(unseededText.contains("last name"))

        try writeEvidence(
            image: filmstrip(
                panels: [
                    ("Nothing supplied - both fields empty, SKIP still offered", unseeded.image),
                    ("Only a first name supplied - only the last name is asked", seeded.image)
                ]
            ),
            named: "sign-in-name-step-seeding.png"
        )
    }

    /// The App Review case. Apple's device has already spent its one first
    /// authorization on Ascend, so the credential carries nothing and there is
    /// nothing to prefill. The step must still have a way forward, and it must
    /// name what skipping costs, or the reviewer sees the screen that got 1.0
    /// rejected.
    @Test("A climber Apple told us nothing about still has a way forward")
    func theNilCredentialStepOffersARealSkip() async throws {
        let reviewer = try await renderNameStep(supplied: nil)

        #expect(reviewer.fieldValues == ["", ""], "Apple supplied nothing to prefill")

        let text = try await recognizedText(in: reviewer.image)
        #expect(
            text.contains("skip"),
            "The step must carry a real skip control, not just a dimmed CONTINUE"
        )
        #expect(
            text.contains("change me"),
            "The climber is told exactly what they race under if they skip"
        )

        try writeEvidence(
            image: reviewer.image,
            named: "sign-in-name-step-nothing-supplied.png"
        )
    }

    /// The rejection case itself. The provider supplied both halves, so nothing
    /// about the name is ever put to the climber.
    @Test("A full name from the provider is never put back to the climber")
    func afullNameFromTheProviderSkipsTheStepEntirely() async throws {
        let supplied = SignInSuppliedIdentity(
            providerUserID: Self.providerUserID,
            firstName: "Maya",
            lastName: "Chen",
            email: "8xk2p9qz7t@privaterelay.appleid.com"
        )

        // The write is what satisfies the step...
        #expect(
            SuppliedNameAdoption.decide(supplied: supplied, storedName: .absent)
                == .write(firstName: "Maya", lastName: "Chen")
        )

        // ...and a profile carrying that name advances the coordinator past the
        // name stage without ever rendering it.
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: "apple-climber")
        #expect(coordinator.phase == .onboarding(.displayName))

        coordinator.completeDisplayNameIfNeeded()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(store.snapshot(for: "apple-climber").completedStages == [.displayName])
    }

    // MARK: - Rendering

    private func renderNameStep(
        supplied: SignInSuppliedIdentity?
    ) async throws -> (image: UIImage, fieldValues: [String]) {
        let identityStore = SignInIdentityStore(userDefaults: makeDefaults())
        if let supplied {
            identityStore.record(supplied)
        }

        let authVM = AuthenticationViewModel(
            signInIdentityStore: identityStore,
            observesFirebaseAuth: false
        )
        authVM.loadSuppliedIdentity(forProviderUserID: supplied?.providerUserID)
        #expect((authVM.suppliedIdentity != nil) == (supplied != nil))

        let controller = UIHostingController(
            rootView: PostAuthOnboardingFlowView(
                stage: .displayName,
                onBack: {},
                onContinue: {}
            )
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .environment(authVM)
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

        return (capture(controller), textFields(in: controller.view).map { $0.text ?? "" })
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
        print("Rendered sign-in name-step evidence: \(outputURL.path())")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SignInNameStepEvidenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
