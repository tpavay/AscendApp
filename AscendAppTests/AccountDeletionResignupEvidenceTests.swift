import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for #389: a climber deletes an Ascend account and signs up again on the
/// same installation.
///
/// The transcript walks the four checkpoints the staging reproduction used - before deletion, the
/// same session immediately after it, a relaunch over the same defaults, and the genuine
/// different-climber control - reading the live SwiftData schema, the real `SettingsManager`, and
/// the shipped ownership guard rather than a narrowed copy of any of them.
///
/// The PNG is the other half: the wall the replacement account must never see, photographed from
/// the real `AccountDataConflictView` so its copy and its one action are visible rather than
/// asserted.
///
/// Both artifacts are written only when `ASCEND_EVIDENCE_DIR` is set (`RenderedScreen`).
@MainActor
struct AccountDeletionResignupEvidenceTests {

    private static let deletedUserId = "deleted-climber-uid"
    private static let replacementUserId = "replacement-climber-uid"

    @Test("Transcript: delete, re-sign-up same session, relaunch, and the different-climber control", .bug(id: 389))
    func writesTheDeleteThenResignupTranscript() async throws {
        var transcript = Transcript()
        transcript.title("ASCEND #389 - delete an account, sign up again on the same device")
        transcript.line(
            "Fixture: live SwiftData schema (in-memory), isolated UserDefaults suite, the real",
            "AccountDeletionService driving the real AppAccountDeletionLocalCleanup, SettingsManager,",
            "and AuthenticatedBootstrapCoordinator. Only the remote gateway and the two host-global",
            "side effects (pending-upload files, shared image cache) are stubbed."
        )

        let suiteName = "AccountDeletionResignupEvidence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(userDefaults: defaults)
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        let modelContext = try AscendLocalStoreFixture.makeModelContext()

        // ── Checkpoint 1: the deleted account's installation ──────────────────────────────────
        try AscendLocalStoreFixture.insertOneOfEach(into: modelContext)
        let manualClimb = Workout(
            name: "Evening Stairs",
            duration: 1_800,
            steps: 2_400,
            floors: 150,
            source: .headphoneMotion
        )
        manualClimb.markPendingRemoteUpsert(ownerUserId: Self.deletedUserId)
        modelContext.insert(manualClimb)
        try modelContext.save()

        settings.measurementSystem = .metric
        settings.fitnessLevel = .advanced
        defaults.set(true, forKey: Self.notificationsKey)
        sessionStore.recordLocalDataOwner(userId: Self.deletedUserId)

        transcript.section("1. BEFORE DELETION - signed in as \(Self.deletedUserId)")
        let beforeCounts = try AscendLocalStoreFixture.storedCountsByModelName(in: modelContext)
        transcript.storeSummary(beforeCounts)
        transcript.preferences(settings: settings, defaults: defaults)
        transcript.field("remembered local data owner", sessionStore.localDataOwnerUserId ?? "(none)")
        transcript.field(
            "manual climb",
            "\"Evening Stairs\" owned by \(manualClimb.ownerUserId ?? "(none)"), "
                + "sync \(manualClimb.remoteSyncStatus.rawValue)"
        )

        #expect(beforeCounts.values.contains { $0 > 0 })
        #expect(settings.measurementSystem == .metric)
        #expect(settings.fitnessLevel == .advanced)

        // ── The deletion itself ───────────────────────────────────────────────────────────────
        let gateway = TranscriptDeletionGateway(currentUserId: Self.deletedUserId)
        let cleanup = TranscriptLocalCleanup(
            real: AppAccountDeletionLocalCleanup(
                userDefaults: defaults,
                persistentDomainName: suiteName,
                settingsManager: settings,
                bootstrapCoordinator: AuthenticatedBootstrapCoordinator(),
                autonomousSessionWorkers: []
            )
        )
        let service = AccountDeletionService(gateway: gateway, localCleanup: cleanup)

        var lastProgress: AccountDeletionService.DeletionProgress?
        try await service.deleteAccount(modelContext: modelContext) { lastProgress = $0 }

        transcript.section("2. DELETE ACCOUNT RUNS")
        transcript.field("remote steps", gateway.steps.map(\.rawValue).joined(separator: " -> "))
        transcript.field("local session work", cleanup.steps.joined(separator: " -> "))
        let progress = try #require(lastProgress)
        transcript.field(
            "progress reported to the climber",
            "\(progress.completedSteps)/\(progress.totalSteps) - \(progress.currentStep)"
        )
        #expect(progress.completedSteps == progress.totalSteps)

        // ── Checkpoint 2: same session, no relaunch ───────────────────────────────────────────
        transcript.section("3. IMMEDIATELY AFTER DELETION - same session, no relaunch")
        let afterCounts = try AscendLocalStoreFixture.storedCountsByModelName(in: modelContext)
        transcript.storeSummary(afterCounts)
        transcript.preferences(settings: settings, defaults: defaults)
        transcript.field(
            "remembered local data owner",
            sessionStore.localDataOwnerUserId ?? "(cleared)"
        )

        let sameSessionDecision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: Self.replacementUserId,
            sessionStore: sessionStore
        )
        transcript.field(
            "ownership guard for \(Self.replacementUserId)",
            Transcript.describe(sameSessionDecision)
        )
        transcript.line("=> The replacement account reaches onboarding. No Account data mismatch wall.")

        #expect(afterCounts.values.allSatisfy { $0 == 0 })
        #expect(sameSessionDecision == .allowed)
        #expect(settings.measurementSystem == .imperial)
        #expect(settings.fitnessLevel == .intermediate)
        #expect(defaults.object(forKey: Self.notificationsKey) == nil)
        #expect(sessionStore.localDataOwnerUserId == nil)

        // The replacement account's first preference write must not flush the deleted account's
        // values back into the domain deletion just emptied.
        settings.hasCompletedBaseLevelOnboarding = true
        #expect(defaults.string(forKey: "measurementSystem") == nil)
        #expect(defaults.object(forKey: "userFitnessLevel") == nil)
        transcript.line(
            "=> The replacement account then completes base-level onboarding. That write persists its",
            "   own value and nothing else: units and fitness level stay absent from the domain."
        )

        // ── Checkpoint 3: after relaunch ──────────────────────────────────────────────────────
        transcript.section("4. AFTER APP RELAUNCH - a fresh SettingsManager over the same defaults")
        let relaunchedSettings = SettingsManager(userDefaults: defaults)
        transcript.preferences(settings: relaunchedSettings, defaults: defaults)
        let relaunchDecision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: Self.replacementUserId,
            sessionStore: AccountSessionStore(userDefaults: defaults)
        )
        transcript.field(
            "ownership guard for \(Self.replacementUserId)",
            Transcript.describe(relaunchDecision)
        )

        #expect(relaunchedSettings.measurementSystem == .imperial)
        #expect(relaunchedSettings.fitnessLevel == .intermediate)
        #expect(relaunchDecision == .allowed)

        // ── Checkpoint 4: the control the fix must not weaken ─────────────────────────────────
        transcript.section("5. CONTROL - a genuinely different climber signs in on a device with unsynced work")
        let sharedDeviceContext = try AscendLocalStoreFixture.makeModelContext()
        let sharedSuiteName = "AccountDeletionResignupEvidence-shared-\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: sharedSuiteName))
        defer { sharedDefaults.removePersistentDomain(forName: sharedSuiteName) }
        let sharedSessionStore = AccountSessionStore(userDefaults: sharedDefaults)
        sharedSessionStore.recordLocalDataOwner(userId: "climber-a")

        let climberAWork = Workout(name: "Climber A's Stairs", duration: 1_200, steps: 1_000, floors: 63, source: .headphoneMotion)
        climberAWork.markPendingRemoteUpsert(ownerUserId: "climber-a")
        sharedDeviceContext.insert(climberAWork)
        try sharedDeviceContext.save()

        transcript.field(
            "on device",
            "1 Workout owned by climber-a, sync \(climberAWork.remoteSyncStatus.rawValue)"
        )
        let blockedDecision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: sharedDeviceContext,
            signedInUserId: "climber-b",
            sessionStore: sharedSessionStore
        )
        transcript.field("ownership guard for climber-b", Transcript.describe(blockedDecision))

        let survivingWork = try sharedDeviceContext.fetch(FetchDescriptor<Workout>())
        transcript.field(
            "climber-a's work after the block",
            "\(survivingWork.count) Workout row(s), owner \(survivingWork.first?.ownerUserId ?? "(none)"), "
                + "sync \(survivingWork.first?.remoteSyncStatus.rawValue ?? "(none)")"
        )
        transcript.line(
            "=> The wall still stands for a real second climber, and the action it offers -",
            "   \"Sign Out and Keep Data\" - resolves it without touching climber-a's climbs."
        )

        guard case .blocked = blockedDecision else {
            Issue.record("Expected the ownership guard to block a genuinely different climber.")
            return
        }
        #expect(survivingWork.count == 1)
        #expect(survivingWork.first?.ownerUserId == "climber-a")
        #expect(survivingWork.first?.remoteSyncStatus == .pendingUpsert)

        if let url = try transcript.write(named: "account-deletion-resignup-transcript.txt") {
            #expect(FileManager.default.fileExists(atPath: url.path()))
        }
    }

    @Test("The blocking wall's copy and its one resolving action", .bug(id: 389))
    func rendersTheAccountDataMismatchWall() throws {
        let modelContext = try AscendLocalStoreFixture.makeModelContext()
        let workout = Workout(name: "Climber A's Stairs", duration: 1_200, steps: 1_000, floors: 63, source: .headphoneMotion)
        workout.markPendingRemoteUpsert(ownerUserId: "climber-a")
        modelContext.insert(workout)
        try modelContext.save()

        let defaults = try #require(
            UserDefaults(suiteName: "AccountDataConflictWall-\(UUID().uuidString)")
        )
        let sessionStore = AccountSessionStore(userDefaults: defaults)
        sessionStore.recordLocalDataOwner(userId: "climber-a")

        let decision = try AccountDataOwnershipService.evaluateAccess(
            modelContext: modelContext,
            signedInUserId: "climber-b",
            sessionStore: sessionStore
        )
        guard case .blocked(let conflict) = decision else {
            Issue.record("Expected a blocked decision to render the wall from.")
            return
        }

        // The real view, driven by a real conflict, so the PNG is the surface a blocked climber
        // actually sees rather than a re-typed copy of its markup. Its size is a 1x fact; the
        // photograph is taken only under `ASCEND_EVIDENCE_DIR`.
        let proof = AccountDataConflictWallProof(conflict: conflict)
        try RenderedScreen.withOffscreenPixels(of: proof) { pixels in
            #expect(pixels.size.width > 0)
        }
        try RenderedScreen.photograph(proof, named: "account-data-mismatch-wall", scale: 2)
    }

    private static let notificationsKey = "climbDropNotificationsEnabled.v1"
}

// MARK: - Rendered proof

private struct AccountDataConflictWallProof: View {
    let conflict: AccountDataOwnershipConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account data mismatch wall - the screen a blocked climber sees")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)

            Text(
                "Signed in as \(conflict.signedInUserId) · device data owned by "
                    + "\(conflict.rememberedOwnerUserId ?? "unknown")"
            )
            .font(.montserratMedium(size: 12))
            .foregroundStyle(Color.ascendAccent.opacity(0.9))

            AccountDataConflictView(conflict: conflict, onSignOut: {})
                .frame(width: 390, height: 700)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(28)
        .background(Color.black)
    }
}

// MARK: - Transcript

private struct Transcript {
    private var lines: [String] = []

    mutating func title(_ text: String) {
        lines.append(text)
        lines.append(String(repeating: "=", count: text.count))
    }

    mutating func section(_ text: String) {
        lines.append("")
        lines.append(text)
        lines.append(String(repeating: "-", count: text.count))
    }

    mutating func line(_ parts: String...) {
        lines.append(contentsOf: parts)
    }

    mutating func field(_ label: String, _ value: String) {
        let padded = label.padding(toLength: max(label.count, 34), withPad: ".", startingAt: 0)
        lines.append("  \(padded) \(value)")
    }

    mutating func storeSummary(_ counts: [String: Int]) {
        let total = counts.values.reduce(0, +)
        let populated = counts.filter { $0.value > 0 }.keys.sorted()
        field("local store rows", "\(total) across \(counts.count) models in the live schema")
        field(
            "models holding rows",
            populated.isEmpty ? "none - every table is empty" : populated.joined(separator: ", ")
        )
    }

    @MainActor
    mutating func preferences(settings: SettingsManager, defaults: UserDefaults) {
        field("units", settings.measurementSystem.rawValue)
        field("fitness level", settings.fitnessLevel.rawValue)
        field(
            "climb-drop notifications",
            defaults.object(forKey: "climbDropNotificationsEnabled.v1") == nil
                ? "unset (key absent)"
                : (defaults.bool(forKey: "climbDropNotificationsEnabled.v1") ? "on" : "off")
        )
        field("base-level onboarding completed", settings.hasCompletedBaseLevelOnboarding ? "yes" : "no")
    }

    static func describe(_ decision: AccountDataOwnershipDecision) -> String {
        switch decision {
        case .allowed:
            return "ALLOWED - straight through to onboarding"
        case .blocked(let conflict):
            let rows = conflict.summary.rowCountsByModelName.values.reduce(0, +)
            return "BLOCKED - full-screen \"Account data mismatch\" wall "
                + "(\(rows) row(s) owned by \(conflict.storedOwnerUserIds.joined(separator: ", ")))"
        }
    }

    /// Writes the transcript beside the photograph, and nothing at all when `ASCEND_EVIDENCE_DIR`
    /// is unset - the run's assertions are what CI keeps.
    @MainActor
    func write(named filename: String) throws -> URL? {
        guard let directory = RenderedScreen.evidenceDirectory else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Doubles

/// Records the cleanup steps for the transcript while letting the real cleanup do the work that
/// matters here - quiescing session work, wiping the domain, and resetting the settings singleton.
///
/// The pending-upload sweep and the shared image cache are host-global, so they are recorded rather
/// than executed: running them would reach outside this test's isolated fixture.
@MainActor
private final class TranscriptLocalCleanup: AccountDeletionLocalCleanup {
    private let real: AppAccountDeletionLocalCleanup
    private(set) var steps: [String] = []

    init(real: AppAccountDeletionLocalCleanup) {
        self.real = real
    }

    func suspendAuthenticatedSessionWork() async {
        steps.append("suspend+drain")
        await real.suspendAuthenticatedSessionWork()
    }

    func resumeAuthenticatedSessionWork() {
        steps.append("resume")
        real.resumeAuthenticatedSessionWork()
    }

    func discardAuthenticatedSessionWork() {
        steps.append("discard")
        real.discardAuthenticatedSessionWork()
    }

    func clearPendingUploadFiles() async throws {
        steps.append("clearPendingUploadFiles (stubbed)")
    }

    func clearUserDefaults() {
        steps.append("clearUserDefaults+resetSettings")
        real.clearUserDefaults()
    }

    func clearImageCache() {
        steps.append("clearImageCache (stubbed)")
    }
}

@MainActor
private final class TranscriptDeletionGateway: AccountDeletionGateway {
    enum Step: String {
        case reauthenticate
        case deleteAllUserStorage
        case deleteWorkoutBackups
        case deleteRoutineBackups
        case deleteBlockedClimbers
        case deletePublicProfileMirrors
        case unregisterPushDevice
        case deleteUserDocument
        case revokeAppleToken
        case deleteAuthAccount
    }

    private(set) var steps: [Step] = []
    let currentUserId: String?

    init(currentUserId: String) {
        self.currentUserId = currentUserId
    }

    func reauthenticate() async throws -> ReauthenticationResult {
        steps.append(.reauthenticate)
        return ReauthenticationResult(appleAuthorizationCode: "apple-auth-code")
    }

    func deleteAllUserStorage(userId: String) async throws { steps.append(.deleteAllUserStorage) }
    func deleteWorkoutBackups(userId: String) async throws { steps.append(.deleteWorkoutBackups) }
    func deleteRoutineBackups(userId: String) async throws { steps.append(.deleteRoutineBackups) }
    func deleteBlockedClimbers(userId: String) async throws { steps.append(.deleteBlockedClimbers) }
    func deletePublicProfileMirrors(userId: String) async throws { steps.append(.deletePublicProfileMirrors) }
    func unregisterPushDevice() async { steps.append(.unregisterPushDevice) }
    func deleteUserDocument(userId: String) async throws { steps.append(.deleteUserDocument) }
    func revokeAppleToken(authorizationCode: String) async throws { steps.append(.revokeAppleToken) }
    func deleteAuthAccount() async throws {
        steps.append(.deleteAuthAccount)
    }
}
