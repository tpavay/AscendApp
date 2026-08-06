import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

@Suite(.serialized, .hostsAWindow)
@MainActor
struct PostAuthNameInputTests {
    @Test("Name onboarding renders separate first and last name fields", .bug(id: 394))
    func nameOnboardingRendersSeparateFields() async throws {
        let size = CGSize(width: 402, height: 874)
        let controller = UIHostingController(
            rootView: PostAuthOnboardingFlowView(
                stage: .displayName,
                onBack: {},
                onContinue: {}
            )
            .frame(width: size.width, height: size.height)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<8 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        let text = try await recognizedText(in: image)

        #expect(text.contains("what's your name"))
        #expect(text.contains("first name"))
        #expect(text.contains("last name"))

        try writeEvidence(image: image, named: "onboarding-first-last-name.png")
    }

    @Test("Continue requires both name fields", .bug(id: 394))
    func continueRequiresBothNameFields() {
        #expect(PostAuthNameInput().canContinue == false)
        #expect(PostAuthNameInput(firstName: "Maya", lastName: "").canContinue == false)
        #expect(PostAuthNameInput(firstName: "", lastName: "Chen").canContinue == false)
        #expect(PostAuthNameInput(firstName: "Maya", lastName: "   ").canContinue == false)
        #expect(PostAuthNameInput(firstName: " Maya ", lastName: " Chen ").canContinue)
    }

    @Test("Continue gates on the same policy Edit Profile saves behind", .bug(id: 394))
    func continueGatesOnTheSharedDisplayNamePolicy() {
        let overlongPart = String(repeating: "Ab", count: DisplayNamePolicy.maximumLength / 2)
        #expect(
            PostAuthNameInput(firstName: overlongPart, lastName: overlongPart)
                .canContinue == false
        )
        #expect(
            PostAuthNameInput(firstName: "Maya", lastName: "Fucker").canContinue == false
        )
        #expect(PostAuthNameInput(firstName: "Maya", lastName: "Chen").canContinue)
    }

    @Test("Rejected names read in onboarding's own words", .bug(id: 394))
    func validationMessagesNeverNameTheDisplayNameField() {
        let overlongPart = String(repeating: "Ab", count: DisplayNamePolicy.maximumLength / 2)

        #expect(PostAuthNameInput().validationMessage == "Enter both a first and last name.")
        #expect(
            PostAuthNameInput(firstName: "Maya", lastName: "").validationMessage ==
                "Enter both a first and last name."
        )
        #expect(
            PostAuthNameInput(firstName: overlongPart, lastName: overlongPart).validationMessage ==
                "That name is too long"
        )
        #expect(
            PostAuthNameInput(firstName: "Maya", lastName: "Fucker").validationMessage ==
                "That name cannot be used"
        )
        #expect(PostAuthNameInput(firstName: "Maya", lastName: "Chen").validationMessage == nil)
    }

    @Test("Completed onboarding resolves the stored first and last name", .bug(id: 394))
    func completedOnboardingResolvesStoredName() {
        let storedProfile = UserDisplayNameData([
            "firstName": "Maya",
            "lastName": "Chen",
            "displayName": "Stale Name"
        ])
        let identity = PublicClimberIdentity.resolve(
            userId: "maya-chen",
            storedDisplayName: storedProfile.resolvedDisplayName,
            storedPhotoURL: nil,
            isCurrentUser: true
        )

        #expect(storedProfile.resolvedDisplayName == "Maya Chen")
        #expect(identity.displayName == "Maya Chen")
        #expect(identity.avatarToken == "MC")
    }

    @Test("Legacy display names survive without splitting or inference", .bug(id: 394))
    func legacyDisplayNameSurvivesUnmodified() {
        let storedProfile = UserDisplayNameData([
            "displayName": "Legacy Climber"
        ])

        #expect(storedProfile.firstName == nil)
        #expect(storedProfile.lastName == nil)
        #expect(storedProfile.displayName == "Legacy Climber")
        #expect(storedProfile.resolvedDisplayName == "Legacy Climber")
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
