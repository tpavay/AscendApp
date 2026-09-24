import Foundation
import UIKit

@testable import AscendApp

/// Serves progress cut-outs from `TestFixtures/climb-progress/<climb-id>-progress.png` in the
/// repository, standing in for Storage. The app bundles none, so a suite that draws a real
/// landmark reads one of these: the Empire State Building, the Eiffel Tower and Charminar.
final class FixtureClimbProgressImageRepository: ClimbProgressImageRepository, @unchecked Sendable {
    static let fixtureClimbIDs = ["empire-state-building", "eiffel-tower", "charminar"]

    static let fixturesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "TestFixtures/climb-progress")

    static func fixtureURL(forClimbID climbID: String) -> URL {
        fixturesDirectory.appending(path: "\(climbID)-progress.png")
    }

    func prefetch(_ artwork: ClimbProgressArtwork) async {}

    func image(for artwork: ClimbProgressArtwork) async -> UIImage? {
        guard let climbID = Self.climbID(fromPath: artwork.path) else { return nil }
        return StorageClimbProgressImageRepository.decode(Self.fixtureURL(forClimbID: climbID), as: artwork)
    }

    /// `climb-images/<climb-id>/progress/v<n>.png` -> `<climb-id>`.
    static func climbID(fromPath path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count >= 2, components[0] == "climb-images" else { return nil }
        return String(components[1])
    }
}

/// A repository whose answer the test releases by hand: `image(for:)` suspends until `release`
/// hands it an image (or nil, for a failed fetch), so a suite can hold a session in its loading
/// state and then let the cut-out arrive mid-climb.
@MainActor
final class GatedClimbProgressImageRepository: ClimbProgressImageRepository, @unchecked Sendable {
    private var waiters: [CheckedContinuation<UIImage?, Never>] = []
    private(set) var requestCount = 0

    nonisolated func prefetch(_ artwork: ClimbProgressArtwork) async {}

    nonisolated func image(for artwork: ClimbProgressArtwork) async -> UIImage? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.requestCount += 1
                self.waiters.append(continuation)
            }
        }
    }

    var hasPendingRequest: Bool { !waiters.isEmpty }

    func release(with image: UIImage?) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: image)
        }
    }
}
