import Foundation
import Photos
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The album + date filter, photographed on the shipping controls.
///
/// `ShareCameraRollScopeTests` pins the ordering rules as arithmetic; nothing there shows the row a
/// climber reads, the album grid, the earned back item, or what the date sheet's primary button
/// says. These suites host the real views in a phone-sized window and read the pixels back.
///
/// The photo library itself is not reachable from a test host: PhotoKit answers `notDetermined` and
/// every fetch returns nothing until a person taps the system permission alert, which is presented
/// out of process and cannot be reached from in-process automation. So the album list is supplied,
/// and the *scope* is driven through the shipping `SharePhotoLibrary`, whose scope machine needs no
/// authorization.

// MARK: - Shared hosting

@MainActor
enum ShareScopeEvidence {
    nonisolated static let screenSize = CGSize(width: 393, height: 852)

    nonisolated static let climbs = ShareAlbum(
        id: "climbs",
        title: "Ascend Climbs",
        count: 128,
        newestAssetDate: .now,
        kind: .user
    )
    nonisolated static let trip = ShareAlbum(
        id: "trip",
        title: "Summer 2026 Colorado Trip With Everyone",
        count: 41,
        newestAssetDate: .now.addingTimeInterval(-30 * 86_400),
        kind: .user
    )
    nonisolated static let favorites = ShareAlbum(
        id: "favorites",
        title: "Favorites",
        count: 62,
        newestAssetDate: .now.addingTimeInterval(-2 * 86_400),
        kind: .smart(.favorites)
    )
    nonisolated static let videos = ShareAlbum(
        id: "videos",
        title: "Videos",
        count: 9,
        newestAssetDate: .now.addingTimeInterval(-9 * 86_400),
        kind: .smart(.videos)
    )
    /// An album with nothing in it, which the grid keeps and dims rather than hiding.
    nonisolated static let raceDay = ShareAlbum(
        id: "race-day",
        title: "Race Day",
        count: 0,
        newestAssetDate: nil,
        kind: .user
    )

    nonisolated static var albums: [ShareAlbum] { [climbs, trip, favorites, videos, raceDay] }

    static func host<Content: View>(
        _ view: Content,
        _ body: (UIWindow) async throws -> Void
    ) async throws {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: screenSize)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: screenSize))
        window.frame = CGRect(origin: .zero, size: screenSize)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        try await body(window)
    }

    /// Every accessibility label the hosted screen publishes, in tree order, read once the screen
    /// has settled into the state the caller is waiting for.
    static func labels(
        in window: UIWindow,
        until isReady: ([String]) -> Bool
    ) async throws -> [String] {
        let elements = try await settledAccessibilityElements(under: window) { elements in
            isReady(elements.compactMap(\.accessibilityLabel))
        }
        let read = elements.compactMap(\.accessibilityLabel)
        #expect(isReady(read), "the screen never settled. Read: \(read.prefix(24))")
        return read
    }

    /// Taps the control a climber taps, once it is actually on screen.
    ///
    /// Photographing the window re-renders it, and the accessibility tree is momentarily empty
    /// while SwiftUI rebuilds - so an activation straight after a capture can miss a control that
    /// is plainly there.
    static func tap(_ label: String, in window: UIWindow) async throws {
        _ = try await labels(in: window) { $0.contains(label) }
        try activateAccessibilityElement(labelled: label, in: window)
    }

    static func photograph(_ window: UIWindow, named name: String, size: CGSize? = nil) throws {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size ?? window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("evidence: \(url.path())")
    }
}

// MARK: - The walk

/// The climber's route through the new scope row, driven by taps on the shipping controls and by
/// the shipping `SharePhotoLibrary`'s own scope machine: Recents, into All Albums, into an album,
/// and back out of it.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareCameraRollScopeWalkEvidenceTests {

    @Test
    func openingAnAlbumFromTheGridTurnsAllAlbumsIntoTheWayBack() async throws {
        let harness = ShareScopeWalkHarness(albums: ShareScopeEvidence.albums)
            .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            try await ShareScopeEvidence.host(harness) { window in
                // 1. Recents. `All Albums` sits directly right of it, the earned album third.
                var labels = try await ShareScopeEvidence.labels(in: window) {
                    $0.contains("All Albums")
                }
                let recents = try #require(labels.firstIndex(of: "Recents"))
                #expect(
                    Array(labels[recents...(recents + 2)]) == ["Recents", "All Albums", "Ascend Climbs"],
                    "row read: \(labels.prefix(6))"
                )
                try ShareScopeEvidence.photograph(window, named: "share-walk-1-recents")

                // 2. Tapping `All Albums` browses albums in place - the row above stays put.
                try await ShareScopeEvidence.tap("All Albums", in: window)
                labels = try await ShareScopeEvidence.labels(in: window) { $0.contains("MY ALBUMS") }
                #expect(labels.contains("Race Day, empty"))
                try ShareScopeEvidence.photograph(window, named: "share-walk-2-all-albums")

                // 3. Opening an album from the grid turns that same slot into the way back, and
                // drops the album from the shortcuts further along so it cannot appear twice.
                try await ShareScopeEvidence.tap("Ascend Climbs, 128 items", in: window)
                labels = try await ShareScopeEvidence.labels(in: window) {
                    $0.contains("Back to all albums, Ascend Climbs")
                }
                let back = try #require(labels.firstIndex(of: "Back to all albums, Ascend Climbs"))
                #expect(labels[back - 1] == "Recents")
                #expect(
                    !labels.contains("Ascend Climbs"),
                    "the opened album is also offered as a shortcut: \(labels.prefix(6))"
                )
                try ShareScopeEvidence.photograph(window, named: "share-walk-3-album-open")

                // 4. Tapping it goes back to the grid rather than to Recents.
                try await ShareScopeEvidence.tap("Back to all albums, Ascend Climbs", in: window)
                labels = try await ShareScopeEvidence.labels(in: window) { $0.contains("MY ALBUMS") }
                #expect(labels.contains("All Albums"))
                try ShareScopeEvidence.photograph(window, named: "share-walk-4-back-to-grid")
            }
        }
    }
}

/// The camera roll tab's own composition, with the album list supplied.
///
/// `ShareBackgroundPickerView.cameraRollContent` is what ships; it cannot be hosted here because its
/// `.task` would sit on the out-of-process permission alert and its library would then fetch
/// nothing. The scope is held here rather than in `SharePhotoLibrary` for the same reason: that
/// class re-resolves an album id against PhotoKit on every selection and correctly falls back to
/// Recents when it no longer resolves, which a fixture album never will. The row, the album grid,
/// the photo grid and the ordering rule underneath them are the shipping ones.
private struct ShareScopeWalkHarness: View {
    let albums: [ShareAlbum]

    @State private var scope = ShareCameraRollScope.recents
    @State private var library = SharePhotoLibrary()

    var body: some View {
        VStack(spacing: 0) {
            ShareScopeFilterRow(
                items: ShareScopeShortcuts.items(
                    albums: albums,
                    scope: scope,
                    rememberedAlbumID: nil
                ),
                selection: scope.selection,
                albumsAreAvailable: true,
                onSelect: { item in
                    scope.selection = item.selection
                    scope.browsedAlbum = nil
                }
            )

            if scope.selection == .allAlbums {
                ShareAlbumGrid(
                    albums: albums,
                    isLoading: false,
                    selectedAlbumID: scope.browsedAlbum?.id,
                    library: library,
                    onSelect: { album in
                        scope.selection = .album(album)
                        scope.browsedAlbum = album
                    }
                )
            } else {
                ShareCameraRollGrid(library: library, onPick: { _ in })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }
}

// MARK: - The chrome

/// The states the row and the date sheet hold, drawn by the shipping views from the shipping
/// ordering rule.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareScopeChromeEvidenceTests {

    @Test
    func theScopeRowIsPhotographedInEveryStateItHolds() async throws {
        let opened = ShareCameraRollScope(
            selection: .album(ShareScopeEvidence.climbs),
            dateWindow: nil,
            browsedAlbum: ShareScopeEvidence.climbs
        )

        let board = VStack(alignment: .leading, spacing: 30) {
            Self.captioned("RECENTS - ALL ALBUMS SITS SECOND, THE EARNED ALBUM THIRD") {
                Self.row(scope: .recents, selection: .recents)
            }
            Self.captioned("BROWSING ALBUMS") {
                Self.row(scope: ShareCameraRollScope(selection: .allAlbums), selection: .allAlbums)
            }
            Self.captioned("OPENED FROM THE GRID - THAT SAME SLOT IS NOW THE WAY BACK") {
                Self.row(scope: opened, selection: .album(ShareScopeEvidence.climbs))
            }
            Self.captioned("LIMITED ACCESS - NO ALBUMS TO REACH") {
                Self.row(scope: .recents, selection: .recents, albumsAreAvailable: false)
            }
        }
        .frame(width: ShareScopeEvidence.screenSize.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            try await ShareScopeEvidence.host(board) { window in
                let labels = try await ShareScopeEvidence.labels(in: window) {
                    $0.contains("Back to all albums, Ascend Climbs")
                }

                let first = try #require(labels.firstIndex(of: "Recents"))
                #expect(
                    Array(labels[first...(first + 2)]) == ["Recents", "All Albums", "Ascend Climbs"]
                )

                // The album items go inert under limited access, where PhotoKit can fetch no
                // albums at all; Recents still works.
                let inert = accessibilityElements(under: window).filter {
                    $0.accessibilityLabel == "All Albums"
                        && $0.accessibilityTraits.contains(.notEnabled)
                }
                #expect(inert.count == 1, "the limited-access row did not go inert")

                try ShareScopeEvidence.photograph(
                    window,
                    named: "share-scope-row-states",
                    size: CGSize(width: 393, height: 470)
                )
            }
        }
    }

    @Test
    func theDateSheetsButtonIsTheCountAndTheRefusal() async throws {
        try await Self.photographDateSheet(
            window: ShareDateWindow(year: 2026, month: 8),
            expecting: "show 312 photos",
            named: "share-date-sheet-count"
        )
        try await Self.photographDateSheet(
            window: ShareDateWindow(year: 2024, month: 3),
            expecting: "no photos in",
            named: "share-date-sheet-empty"
        )
    }

    // MARK: - Support

    /// A stand-in for `SharePhotoLibrary.photoCount(forDateWindow:)`: March 2024 is the month this
    /// climber's roll does not cover, so the button has to refuse it.
    private static func count(for window: ShareDateWindow?) -> Int {
        guard let window else { return 4_180 }
        return window.month == 3 && window.year == 2024 ? 0 : 312
    }

    private static func photographDateSheet(
        window: ShareDateWindow,
        expecting expectedTitle: String,
        named name: String
    ) async throws {
        let sheet = ShareDateFilterSheet(
            availableYears: [2026, 2025, 2024, 2023],
            current: window,
            countProvider: { count(for: $0) },
            onApply: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "121212"))
        .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            try await ShareScopeEvidence.host(sheet) { hosted in
                let labels = try await ShareScopeEvidence.labels(in: hosted) {
                    $0.contains { $0.localizedCaseInsensitiveContains(expectedTitle) }
                }
                #expect(labels.contains { $0.localizedCaseInsensitiveContains(expectedTitle) })

                try ShareScopeEvidence.photograph(
                    hosted,
                    named: name,
                    size: CGSize(width: 393, height: 470)
                )
            }
        }
    }

    private static func row(
        scope: ShareCameraRollScope,
        selection: ShareCameraRollSelection,
        albumsAreAvailable: Bool = true
    ) -> ShareScopeFilterRow {
        ShareScopeFilterRow(
            items: ShareScopeShortcuts.items(
                albums: ShareScopeEvidence.albums,
                scope: scope,
                rememberedAlbumID: nil
            ),
            selection: selection,
            albumsAreAvailable: albumsAreAvailable,
            onSelect: { _ in }
        )
    }

    @ViewBuilder
    private static func captioned<Content: View>(
        _ caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.ascendAccent.opacity(0.55))
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
            content()
        }
    }
}
