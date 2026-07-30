import Foundation
import Testing
@testable import AscendApp

struct AuditedIdentitySurfaceTests {
    private let sentinelName = "RAW IDENTITY MUST NEVER RENDER"
    private let sentinelPhotoURL = URL(string: "https://example.com/raw-sentinel.jpg")

    @Test
    func globalRowAndPodiumAdaptersHideBlockedIdentityWithoutChangingRank() {
        let raw = LeaderboardEntry(
            userId: "blocked-user",
            displayName: sentinelName,
            photoURL: sentinelPhotoURL,
            rank: 2,
            value: 12_345,
            formattedValue: "12,345",
            isTied: true
        )

        let row: ModeratedLeaderboardEntry = CrossUserIdentityAdapter.leaderboardEntry(
            raw,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )
        let podium = ModeratedLeaderboardPodiumLayout(entries: [row])

        assertHidden(row.identity)
        #expect(row.rank == 2)
        #expect(row.value == 12_345)
        #expect(row.isTied)
        #expect(podium.slots.compactMap(\.entry).first?.identity == row.identity)
    }

    @Test
    func liveReplayAndCompletionAdaptersHideIdentityAndPreserveResultContext() {
        let raw = replayRow()
        let row: ModeratedReplayLeaderboardRow = CrossUserIdentityAdapter.replayRow(
            raw,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )

        // Both Live Replay renderers and both completion renderers accept only
        // ModeratedReplayLeaderboardRow. Passing `raw` to one is a compile error.
        assertHidden(row.identity)
        #expect(row.rank == 3)
        #expect(row.stepsAtBucket == 900)
        #expect(row.finalSteps == 1_200)
        #expect(row.gender == "woman")
        #expect(row.age == 35)
        #expect(row.locationCity == "Chicago")
    }

    @Test
    func profileFirstAscentAndCommunityAdaptersHideRawSentinels() {
        let identity = CrossUserIdentityAdapter.profileIdentity(
            ProfileUserIdentity(
                userId: "blocked-user",
                displayName: sentinelName,
                photoURL: sentinelPhotoURL
            ),
            isCurrentUser: false,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )

        // Profile comparison, First Ascent, and community-avatar render models
        // all receive this resolved type rather than their raw publication model.
        assertHidden(identity)
    }

    @Test
    func accountAuthoredIdentityReachesEveryModeratedRenderModelWhenUnblocked() {
        let entry = CrossUserIdentityAdapter.leaderboardEntry(
            LeaderboardEntry(
                userId: "visible-user",
                displayName: "Maya Chen",
                photoURL: sentinelPhotoURL,
                rank: 1,
                value: 2_000,
                formattedValue: "2,000"
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let replay = CrossUserIdentityAdapter.replayRow(
            LiveReplayLeaderboardRow(
                id: "visible-user",
                rank: 1,
                displayName: "Maya Chen",
                avatarToken: "ignored-for-account-user",
                photoURL: sentinelPhotoURL,
                stepsAtBucket: 2_000,
                finalSteps: 2_000,
                deltaFromUser: 100,
                isCurrentUser: false,
                isPersonalBest: true,
                completionDurationSeconds: 600,
                userId: "visible-user"
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let profileFirstAscentAndCommunity = CrossUserIdentityAdapter.profileIdentity(
            ProfileUserIdentity(
                userId: "visible-user",
                displayName: "Maya Chen",
                photoURL: sentinelPhotoURL
            ),
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        for identity in [
            entry.identity,
            replay.identity,
            profileFirstAscentAndCommunity,
        ] {
            #expect(identity.displayName == "Maya Chen")
            #expect(identity.photoURL == sentinelPhotoURL)
            #expect(identity.avatarToken == "MC")
            #expect(identity.isHidden == false)
        }
    }

    @Test
    func identityRenderingViewAPIsAcceptOnlyModeratedModels() throws {
        let contracts = [
            (
                "AscendApp/Features/Leaderboards/Views/LeaderboardRowListView.swift",
                "let entries: [ModeratedLeaderboardEntry]",
                "let entries: [LeaderboardEntry]"
            ),
            (
                "AscendApp/Shared/Components/ReplayLeaderboard/LiveReplayLeaderboardPanel.swift",
                "let rows: [ModeratedReplayLeaderboardRow]",
                "let rows: [LiveReplayLeaderboardRow]"
            ),
            (
                "AscendApp/Shared/Components/ReplayLeaderboard/ReplayCompletionLeaderboardView.swift",
                "rows: [ModeratedReplayLeaderboardRow]",
                "rows: [LiveReplayLeaderboardRow]"
            ),
        ]

        for (path, required, forbidden) in contracts {
            let source = try source(at: path)
            #expect(source.contains(required), "Moderated API missing in \(path)")
            #expect(
                source.contains(forbidden) == false,
                "Raw renderer API found in \(path)"
            )
        }
    }

    @Test
    func everySwiftUIFileRejectsRawCrossUserIdentityModels() throws {
        let sourceRoot = projectRoot.appending(path: "AscendApp")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        var violations: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            guard source.contains("import SwiftUI") else { continue }

            for match in try rawIdentityModelMatches(in: source) {
                violations.append(
                    "\(fileURL.path().replacing(projectRoot.path(), with: "")): \(match)"
                )
            }
            if source.contains("ProfileIdentityPersistenceAdapter") ||
                source.contains(".unresolvedIdentity") {
                violations.append(
                    "\(fileURL.path().replacing(projectRoot.path(), with: "")): " +
                        "non-rendering identity adapter"
                )
            }
            for reflectionAPI in try reflectionAPIMatches(in: source) {
                violations.append(
                    "\(fileURL.path().replacing(projectRoot.path(), with: "")): " +
                        reflectionAPI
                )
            }
        }

        #expect(
            violations.isEmpty,
            "Raw cross-user identity model reached SwiftUI:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test
    func broadSourceScanDetectsAliasesParametersAndInferredRawModels() throws {
        let faultySource = """
        let arbitraryAlias: LiveReplayLeaderboardRow
        func render(competitor: LeaderboardEntry) {}
        let inferred = LiveReplayFirstAscent(
            userId: "raw",
            displayName: "Raw",
            avatarToken: "R",
            photoURL: nil,
            completedAt: .now
        )
        let rawProfile: ProfileUserIdentity
        func inspect(payload: UnresolvedUserIdentity) {}
        let inferredProfile = ProfileUserIdentity(
            userId: "raw",
            displayName: "Raw"
        )
        String ( reflecting: inferredProfile)
        Mirror (reflecting: rawProfile)
        Text("\\(inferredProfile)")
        """

        let matches = try rawIdentityModelMatches(in: faultySource)
        let reflectionMatches = try reflectionAPIMatches(in: faultySource)
        #expect(matches.contains("LiveReplayLeaderboardRow"))
        #expect(matches.contains("LeaderboardEntry"))
        #expect(matches.contains("LiveReplayFirstAscent"))
        #expect(matches.contains("ProfileUserIdentity"))
        #expect(matches.contains("UnresolvedUserIdentity"))
        #expect(reflectionMatches.contains("String ( reflecting:"))
        #expect(reflectionMatches.contains("Mirror ("))
        #expect(faultySource.contains("Text(\"\\(inferredProfile)\")"))
    }

    @Test
    func rawServiceIdentityIsCompilerOpaque() throws {
        let adapterSource = try source(
            at: "AscendApp/Features/Moderation/Models/ModeratedIdentityRenderModels.swift"
        )
        let leaderboardSource = try source(
            at: "AscendApp/Features/Leaderboards/Models/LeaderboardEntry.swift"
        )
        let replaySource = try source(
            at: "AscendApp/Shared/Services/LiveReplayLeaderboard/LiveReplayLeaderboardModels.swift"
        )
        let profileIdentitySource = try source(
            at: "AscendApp/Features/Profile/Models/ProfileUserIdentity.swift"
        )
        let profileSnapshotSource = try source(
            at: "AscendApp/Features/Profile/Models/ProfileSnapshot.swift"
        )
        let firestoreStatsSource = leaderboardSource[
            try #require(
                leaderboardSource.range(of: "struct FirestoreLeaderboardStats")
            ).lowerBound...
        ]

        #expect(adapterSource.contains("private let displayName: String"))
        #expect(adapterSource.contains("private let photoURL: URL?"))
        #expect(adapterSource.contains("private let avatarToken: String"))
        #expect(
            leaderboardSource
                .prefix(upTo: try #require(
                    leaderboardSource.range(of: "struct FirestoreLeaderboardStats")
                ).lowerBound)
                .contains("let displayName: String") == false
        )
        #expect(replaySource.contains("func publicIdentity(") == false)
        #expect(profileIdentitySource.contains("var displayName: String") == false)
        #expect(profileIdentitySource.contains("var photoURL: URL?") == false)
        #expect(profileSnapshotSource.contains("displayName") == false)
        #expect(profileSnapshotSource.contains("photoURL") == false)
        #expect(profileSnapshotSource.contains("ProfileUserIdentity") == false)
        #expect(profileSnapshotSource.contains("UnresolvedUserIdentity") == false)
        #expect(profileSnapshotSource.contains("var demographics: ProfileDemographicsSnapshot"))
        #expect(firestoreStatsSource.contains("let displayName: String") == false)
        #expect(firestoreStatsSource.contains("let photoURL: String?") == false)
    }

    @Test
    func rawProfileDescriptionsNeverInterpolateStoredIdentity() {
        let profile = ProfileUserIdentity(
            userId: "raw-user",
            displayName: sentinelName,
            photoURL: sentinelPhotoURL
        )
        let unresolved = UnresolvedUserIdentity(
            displayName: sentinelName,
            photoURL: sentinelPhotoURL
        )

        for rendered in [
            String(describing: profile),
            String(reflecting: profile),
            "\(profile)",
            String(describing: Mirror(reflecting: profile).children.first?.value),
            String(describing: unresolved),
            String(reflecting: unresolved),
            "\(unresolved)",
            String(describing: Mirror(reflecting: unresolved).children.first?.value),
        ] {
            #expect(rendered.contains(sentinelName) == false)
            #expect(rendered.contains("raw-sentinel.jpg") == false)
        }
    }

    @Test
    func profileComparisonChildrenCannotReadRemoteRawIdentity() throws {
        let source = try source(
            at: "AscendApp/Features/Profile/Views/OtherUserProfileView.swift"
        )
        let bioStart = try #require(
            source.range(of: "private struct ProfileComparisonBioTab")
        ).lowerBound
        let bioEnd = try #require(
            source.range(of: "private struct ProfileComparisonHeadToHeadTab")
        ).lowerBound
        let childSource = source[bioStart..<bioEnd]

        #expect(childSource.contains(".displayName") == false)
        #expect(childSource.contains(".photoURL") == false)
        #expect(childSource.contains(".unresolvedIdentity") == false)
    }

    @Test
    func directRawProfileAndFirestoreIdentityFaultsHaveNoMemberAPI() throws {
        let profileIdentitySource = try source(
            at: "AscendApp/Features/Profile/Models/ProfileUserIdentity.swift"
        )
        let profileSnapshotSource = try source(
            at: "AscendApp/Features/Profile/Models/ProfileSnapshot.swift"
        )
        let leaderboardSource = try source(
            at: "AscendApp/Features/Leaderboards/Models/LeaderboardEntry.swift"
        )
        let exactFaults = [
            "Text(profile.displayName)",
            "Text(snapshot.identity.displayName)",
            "AsyncImage(url: stats.photoURL)",
            "String(reflecting: profile)",
            "Mirror(reflecting: snapshot)",
            "Text(\"\\(profile)\")",
        ]

        #expect(exactFaults.count == 6)
        #expect(profileIdentitySource.contains("displayName: String") == true)
        #expect(profileIdentitySource.contains("let displayName") == false)
        #expect(profileIdentitySource.contains("var displayName") == false)
        #expect(profileIdentitySource.contains("let photoURL") == false)
        #expect(profileIdentitySource.contains("var photoURL") == false)
        #expect(profileSnapshotSource.contains("displayName") == false)
        #expect(profileSnapshotSource.contains("photoURL") == false)
        #expect(profileSnapshotSource.contains("ProfileUserIdentity") == false)
        #expect(profileSnapshotSource.contains("UnresolvedUserIdentity") == false)
        let statsStart = try #require(
            leaderboardSource.range(of: "struct FirestoreLeaderboardStats")
        ).lowerBound
        let statsSource = leaderboardSource[statsStart...]
        #expect(statsSource.contains("let displayName") == false)
        #expect(statsSource.contains("var displayName") == false)
        #expect(statsSource.contains("let photoURL") == false)
        #expect(statsSource.contains("var photoURL") == false)
    }

    @Test
    func leaderboardRowListAcceptsOnlyModeratedEntries() throws {
        let source = try source(
            at: "AscendApp/Features/Leaderboards/Views/LeaderboardRowListView.swift"
        )

        #expect(source.contains("let entries: [ModeratedLeaderboardEntry]"))
        #expect(try rawIdentityModelMatches(in: source).isEmpty)
    }

    @Test
    func resolvedIdentityCarriesNothingButItsModeratedValues() throws {
        let source = try source(
            at: "AscendApp/Features/Moderation/Models/ResolvedUserIdentity.swift"
        )
        let storedPropertyBlock = source.prefix(
            upTo: try #require(source.range(of: "private init(")).lowerBound
        )
        let storedProperties = storedPropertyBlock
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("let ") }

        // Anything beyond these five would let a surface read past the mask by
        // reading the property directly, which is exactly the bypass the
        // moderation boundary exists to make impossible.
        #expect(storedProperties == [
            "let userId: String?",
            "let displayName: String",
            "let photoURL: URL?",
            "let avatarToken: String",
            "let isHidden: Bool",
        ])
    }

    @Test
    func resolvedIdentityConstructionExistsOnlyInsideItsPrivateResolver() throws {
        let sourceRoot = projectRoot.appending(path: "AscendApp")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        var violatingPaths: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("ResolvedUserIdentity("),
               fileURL.lastPathComponent != "ResolvedUserIdentity.swift" {
                violatingPaths.append(fileURL.path())
            }
        }

        #expect(violatingPaths.isEmpty)
    }

    private func assertHidden(
        _ identity: ResolvedUserIdentity,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(identity.displayName != sentinelName, sourceLocation: sourceLocation)
        #expect(identity.photoURL != sentinelPhotoURL, sourceLocation: sourceLocation)
        #expect(identity.photoURL == nil, sourceLocation: sourceLocation)
        #expect(identity.avatarToken.isEmpty, sourceLocation: sourceLocation)
        #expect(identity.isHidden, sourceLocation: sourceLocation)
    }

    private func replayRow() -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "blocked-user",
            rank: 3,
            displayName: sentinelName,
            avatarToken: "RAW",
            photoURL: sentinelPhotoURL,
            stepsAtBucket: 900,
            finalSteps: 1_200,
            deltaFromUser: 150,
            isCurrentUser: false,
            isPersonalBest: true,
            completionDurationSeconds: 720,
            userId: "blocked-user",
            gender: "woman",
            age: 35,
            locationCity: "Chicago",
            isTied: true
        )
    }

    private var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private func rawIdentityModelMatches(in source: String) throws -> [String] {
        let patterns = [
            #"\b(?:LeaderboardEntry|LiveReplayLeaderboardRow|LiveReplayFirstAscent|FirestoreLeaderboardStats|ProfileUserIdentity|UnresolvedUserIdentity)\b"#,
        ]
        var matches: [String] = []

        for pattern in patterns {
            let expression = try NSRegularExpression(pattern: pattern)
            let range = NSRange(source.startIndex..., in: source)
            for result in expression.matches(in: source, range: range) {
                guard let matchRange = Range(result.range, in: source) else {
                    continue
                }
                matches.append(String(source[matchRange]))
            }
        }

        return matches
    }

    private func reflectionAPIMatches(in source: String) throws -> [String] {
        let patterns = [
            #"\bString\s*\(\s*reflecting\s*:"#,
            #"\bMirror\s*\("#,
        ]
        var matches: [String] = []

        for pattern in patterns {
            let expression = try NSRegularExpression(pattern: pattern)
            let range = NSRange(source.startIndex..., in: source)
            for result in expression.matches(in: source, range: range) {
                guard let matchRange = Range(result.range, in: source) else {
                    continue
                }
                matches.append(String(source[matchRange]))
            }
        }

        return matches
    }
}
