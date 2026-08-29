import Foundation
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Photographs the live board a repeat climber sees, so the fix to the row that
/// used to read as a stranger can be checked off the pixels.
///
/// The captain's screenshot of his second St Peter's Basilica attempt showed his
/// own earlier climb at rank 1 drawn exactly the way a rival is drawn: initials
/// on a plain circle, a `M · 27 · Chicago` subtitle, no `YOU`, and a tap target
/// into another climber's profile. `FirestoreLiveReplayLeaderboardRepository`
/// had never asked who was signed in, so every published row came back
/// `isCurrentUser: false`.
///
/// Both rows below are his. The board must draw them both as his while keeping
/// the attempt in progress the one that is obviously live.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveReplayOwnHistoryRowRenderEvidenceTests {
    private static let panelSize = CGSize(width: 393, height: 420)
    private static let targetSteps = 551

    @Test
    func theClimbersOwnEarlierAttemptIsDrawnAsTheirsAndNotAsAStranger() async throws {
        let image = try screenshot(of: RepeatClimberBoardProof(), size: Self.panelSize)
        // The panel header carries the climb's own step target, so the rows are
        // read back without it: otherwise "551" is on the page whether or not a
        // row holds it.
        let rows = try crop(
            image,
            to: CGRect(
                x: 0,
                y: 64,
                width: Self.panelSize.width,
                height: Self.panelSize.height - 64
            )
        )
        let text = try await recognizedText(in: rows)

        // Two rows, both his, both saying so.
        #expect(text.components(separatedBy: "tyler pavay").count - 1 == 2)
        #expect(text.components(separatedBy: "you").count - 1 == 2)

        // A stranger's demographic subtitle is what made his own record read as
        // somebody else's row.
        #expect(!text.contains("chicago"))

        // The record he is chasing is still first, and the run on the machine
        // is second.
        #expect(appearsBefore("551", "497", in: text))

        try writeEvidence(image: image, named: "repeat-climber-live-board.png")
    }

    @Test
    func onlyTheAttemptInProgressIsDrawnAsTheLiveRow() async throws {
        // Both rows are the climber's, so `isCurrentUser` cannot be what selects
        // the anchored treatment. Only the live attempt carries the lime
        // progress bar, and it is the widest lime band on the panel.
        let image = try screenshot(of: RepeatClimberBoardProof(), size: Self.panelSize)
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")

        let historyRowAccent = try accentCoverage(in: cgImage, rowFraction: 0.30)
        let liveRowAccent = try accentCoverage(in: cgImage, rowFraction: 0.52)

        #expect(liveRowAccent > historyRowAccent * 3)
    }

    // MARK: - Reading the pixels

    /// The share of one horizontal band that is painted in the accent lime, used
    /// to tell the anchored live row from the finished row above it without
    /// asserting an exact colour a designer may still tune.
    private func accentCoverage(
        in image: CGImage,
        rowFraction: Double
    ) throws -> Double {
        let y = Int(Double(image.height) * rowFraction)
        let width = image.width
        var pixels = [UInt8](repeating: 0, count: width * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            "Could not open a one-row bitmap context"
        )
        context.draw(
            image,
            in: CGRect(x: 0, y: -y, width: width, height: image.height)
        )

        // Lime is the only token on this panel where green leads red and blue by
        // a wide margin.
        let limePixels = stride(from: 0, to: width * 4, by: 4).filter { offset in
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            return green > red + 20 && green > blue + 40 && green > 40
        }

        return Double(limePixels.count) / Double(width)
    }

    // MARK: - Capture

    private func screenshot(of view: some View, size: CGSize) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark

        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private func crop(_ image: UIImage, to rect: CGRect) throws -> UIImage {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        let scale = image.scale
        let scaled = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let cropped = try #require(cgImage.cropping(to: scaled), "Crop fell outside the image")
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
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

    private func appearsBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let firstRange = text.range(of: first),
              let secondRange = text.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        #expect(png.count > 5_000)

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: URL(filePath: directory),
            withIntermediateDirectories: true
        )
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        print("ASCEND_EVIDENCE_PNG \(url.path())")
    }

    /// The rows the repository now returns at bucket 35: his finished record,
    /// held at the target, and the run still on the machine.
    fileprivate static func rows() -> [ModeratedReplayLeaderboardRow] {
        let history = LiveReplayLeaderboardRow(
            id: "first-attempt",
            rank: 1,
            displayName: "Tyler Pavay",
            avatarToken: "TP",
            photoURL: nil,
            stepsAtBucket: targetSteps,
            finalSteps: targetSteps,
            deltaFromUser: 54,
            isCurrentUser: true,
            isPersonalBest: true,
            completionDurationSeconds: 346.66342401504517,
            userId: "kC8GSV7hCDZY9waZhIS9CimQ70y2",
            gender: "man",
            age: 27,
            locationCity: "Chicago"
        )
        let live = LiveReplayLeaderboardRow.currentUser(
            rank: 2,
            steps: 497,
            displayName: "Tyler Pavay"
        )

        return [history, live].map {
            CrossUserIdentityAdapter.replayRow(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
    }
}

/// The live race panel exactly as `LiveClimbSessionView` configures it.
private struct RepeatClimberBoardProof: View {
    var body: some View {
        NavigationStack {
            LiveReplayLeaderboardPanel(
                rows: LiveReplayOwnHistoryRowRenderEvidenceTests.rows(),
                progressScaleSteps: 551,
                targetStepGoal: 551,
                progress: 0.9,
                currentUserPhotoURL: nil,
                fetchFailed: false,
                field: LiveReplayFieldSize(population: .climbers, count: 1),
                tint: .accent,
                effectiveColorScheme: .dark,
                showsFilter: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
    }
}
