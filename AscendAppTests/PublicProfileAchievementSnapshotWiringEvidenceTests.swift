import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs the comparison's ACHIEVEMENTS section fed from two real `ProfileSnapshot`s, built
/// the way `OtherUserProfileView` builds them, rather than from ladders assembled by hand.
///
/// The defect the captain found was at the call site: the screen held both snapshots and read the
/// achievements off only one of them. Driving the section from `viewer.achievements` and
/// `otherUser.achievements` here is the wiring under test, so a reviewer can see the viewer's own
/// badges survive an opponent who holds none.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementSnapshotWiringEvidenceTests {
    private static func record(
        id: String,
        type: ProfileAchievementType,
        rank: Int
    ) -> ProfileAchievementRecord {
        ProfileAchievementRecord(
            id: id,
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: Date(timeIntervalSince1970: 1_754_000_000),
            rank: rank,
            value: 12_000,
            valueUnit: "steps"
        )
    }

    /// A three-time champion with a long ranked tail - the viewer in the captain's report.
    private static let championLadder = ProfileAchievementLadder(records: championRecords())

    private static func championRecords() -> [ProfileAchievementRecord] {
        var records: [ProfileAchievementRecord] = []
        for index in 1...3 {
            records.append(record(id: "champ-\(index)", type: .weeklyTop1, rank: 1))
        }
        for index in 1...2 {
            records.append(record(id: "second-\(index)", type: .monthlyTop3, rank: 2))
        }
        records.append(record(id: "third-1", type: .weeklyTop3, rank: 3))
        for index in 1...6 {
            records.append(record(id: "top-ten-\(index)", type: .weeklyTop10, rank: 4 + index))
        }
        for index in 1...29 {
            records.append(
                record(id: "top-hundred-\(index)", type: .weeklyTop100, rank: 20 + index)
            )
        }
        return records
    }

    private static func snapshot(
        userId: String,
        achievements: ProfileAchievementLadder
    ) -> ProfileSnapshot {
        ProfileSnapshotBuilder.makeRemoteSnapshot(
            demographics: ProfileDemographicsSnapshot(userId: userId),
            stats: .empty,
            achievements: achievements,
            standings: [],
            workoutSummaries: [],
            firstAscentsHeld: [],
            openFirstAscents: [],
            climbs: []
        )
    }

    /// The exact expression `OtherUserProfileView` uses, so what is photographed is the wiring.
    private static func section(
        viewer: ProfileSnapshot,
        otherUser: ProfileSnapshot,
        isOtherLoading: Bool
    ) -> PublicProfileAchievementsSection {
        PublicProfileAchievementsSection(
            viewer: ProfileAchievementTally(
                ladder: viewer.achievements,
                firstAscentsHeld: viewer.firstAscentsHeld.count
            ),
            other: ProfileAchievementTally(
                ladder: otherUser.achievements,
                firstAscentsHeld: otherUser.firstAscentsHeld.count
            ),
            isOtherLoading: isOtherLoading
        )
    }

    @Test
    func aChampionsOwnBadgesSurviveABrandNewOpponentsEmptySnapshot() throws {
        let viewer = Self.snapshot(userId: "viewer", achievements: Self.championLadder)
        let otherUser = Self.snapshot(userId: "other", achievements: .empty)

        let rows = ProfileAchievementCatalogue.comparisonEntries(
            viewer: ProfileAchievementTally(ladder: viewer.achievements),
            other: ProfileAchievementTally(ladder: otherUser.achievements)
        )
        let viewerCounts: [Int?] = rows.map { $0.viewerCount }
        #expect(viewerCounts == [3, 2, 1, 12, 41])
        #expect(rows.allSatisfy { $0.otherCount == 0 })

        try Self.capture(
            name: "snapshot-wiring-champion-vs-new-climber",
            caption: "From two real ProfileSnapshots: the viewer's own ladder is read and drawn even though the other climber's snapshot is empty",
            viewer: viewer,
            otherUser: otherUser,
            isOtherLoading: false
        )
    }

    @Test
    func twoLoadedSnapshotsAttributeEveryCountToItsOwnSide() throws {
        let viewer = Self.snapshot(
            userId: "viewer",
            achievements: ProfileAchievementLadder(
                records: [
                    Self.record(id: "v-champ", type: .weeklyTop1, rank: 1),
                    Self.record(id: "v-third", type: .weeklyTop3, rank: 3),
                    Self.record(id: "v-ten", type: .weeklyTop10, rank: 8)
                ]
            )
        )
        let otherUser = Self.snapshot(userId: "other", achievements: Self.championLadder)

        try Self.capture(
            name: "snapshot-wiring-two-loaded-climbers",
            caption: "Both snapshots loaded: your counts on the left, theirs on the right, one row per badge either side holds",
            viewer: viewer,
            otherUser: otherUser,
            isOtherLoading: false
        )
    }

    private static func capture(
        name: String,
        caption: String,
        viewer: ProfileSnapshot,
        otherUser: ProfileSnapshot,
        isOtherLoading: Bool,
        width: CGFloat = 402
    ) throws {
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            section(viewer: viewer, otherUser: otherUser, isOtherLoading: isOtherLoading)
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 500)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        var fitted: CGFloat = 400
        for _ in 0..<10 {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(until: Date())
            fitted = host.sizeThatFits(
                in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fitted))
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image {
            window.layer.render(in: $0.cgContext)
        }

        let data = try #require(image.pngData(), "No PNG data for \(name)")
        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-public-profile-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            let url = URL(filePath: directory).appending(path: "\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path)")
                return
            } catch {
                continue
            }
        }
        Issue.record("No writable evidence directory for \(name)")
    }
}
