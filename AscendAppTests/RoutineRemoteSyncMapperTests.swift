import Foundation
import Testing
@testable import AscendApp

/// Field-by-field proof that the backup carries what the climber built.
///
/// A dropped field here is exactly the failure the backup exists to prevent,
/// and it is invisible until somebody reinstalls - a restored routine missing
/// its weight overrides reads like a routine that never had any.
@MainActor
struct RoutineRemoteSyncMapperTests {
    private static let userId = "user-304"

    @Test
    func everyIntervalModifierSurvivesTheRoundTrip() throws {
        let interval = RoutineInterval(
            duration: 90,
            intensityType: .stepsPerMinute,
            intensityValue: 96,
            modifiers: IntervalModifiers(
                sidewaysDirection: .right,
                skipStep: true,
                backwardStep: true,
                holdingBars: true,
                weightOverride: IntervalWeightOverride(
                    enabledEquipmentTypes: [.weightedVest, .ankleWeights]
                )
            ),
            order: 3
        )

        let restored = try #require(
            RoutineRemoteSyncMapper.interval(from: RoutineRemoteSyncMapper.interval(from: interval))
        )

        #expect(restored == interval)
    }

    @Test("An interval weight override keeps all three of its meanings", .bug(id: 304))
    func weightOverrideDistinguishesInheritFromNoWeights() throws {
        // nil = inherit the routine defaults; empty = no weights on this
        // interval. Collapsing them silently adds weight to an interval the
        // climber deliberately stripped it from.
        let inheriting = RoutineInterval(
            duration: 60,
            intensityValue: 8,
            modifiers: IntervalModifiers(weightOverride: nil),
            order: 0
        )
        let noWeights = RoutineInterval(
            duration: 60,
            intensityValue: 8,
            modifiers: IntervalModifiers(weightOverride: .noWeights),
            order: 1
        )

        let inheritingDocument = RoutineRemoteSyncMapper.interval(from: inheriting)
        let noWeightsDocument = RoutineRemoteSyncMapper.interval(from: noWeights)

        #expect(inheritingDocument.weightOverrideEquipmentTypes == nil)
        #expect(noWeightsDocument.weightOverrideEquipmentTypes == [])

        let restoredInheriting = try #require(RoutineRemoteSyncMapper.interval(from: inheritingDocument))
        let restoredNoWeights = try #require(RoutineRemoteSyncMapper.interval(from: noWeightsDocument))

        #expect(restoredInheriting.modifiers.weightOverride == nil)
        #expect(restoredNoWeights.modifiers.weightOverride?.enabledEquipmentTypes == [])
    }

    @Test
    func aRoutineWithNoOwnerIsNotUploaded() {
        let routine = Routine(name: "Orphan", source: .userCreated)

        #expect(throws: RoutineSyncError.missingOwner) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aCatalogTemplateIsNotUploaded() {
        let routine = Routine(name: "Pyramid Climb", source: .remoteTemplate, templateId: "pyramid")
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.notUserAuthored) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutinePastTheIntervalCeilingIsNotUploaded() {
        let routine = Routine(name: "Marathon", source: .userCreated)
        routine.ownerUserId = Self.userId
        routine.intervals = (0..<(FirestoreUserRoutineDocument.maxIntervals + 1)).map { index in
            RoutineInterval(duration: 30, intensityValue: 5, order: index)
        }

        #expect(
            throws: RoutineSyncError.tooManyIntervals(
                count: FirestoreUserRoutineDocument.maxIntervals + 1,
                limit: FirestoreUserRoutineDocument.maxIntervals
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutineAtTheIntervalCeilingIsUploaded() throws {
        let routine = Routine(name: "Twenty rounds", source: .userCreated)
        routine.ownerUserId = Self.userId
        routine.intervals = (0..<FirestoreUserRoutineDocument.maxIntervals).map { index in
            RoutineInterval(duration: 30, intensityValue: 5, order: index)
        }

        let document = try RoutineRemoteSyncMapper.document(for: routine)

        #expect(document.intervals.count == FirestoreUserRoutineDocument.maxIntervals)
    }

    /// The ceiling the client enforces and the one `firestore.rules` enforces
    /// must be the same number. If they drift apart, either the client refuses
    /// writes the server would accept, or it retries writes the server will
    /// always reject.
    @Test
    func theClientIntervalCeilingMatchesTheRule() throws {
        let rules = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "firestore.rules"),
            encoding: .utf8
        )

        #expect(rules.contains("return \(FirestoreUserRoutineDocument.maxIntervals);"))
    }

    @Test
    func aFolderWithNoOwnerIsNotUploaded() {
        #expect(throws: RoutineSyncError.missingOwner) {
            _ = try RoutineRemoteSyncMapper.document(for: RoutineFolder(name: "Orphan"))
        }
    }

    @Test
    func anUneditedFolderBacksUpItsCreationDateAsItsUpdatedAt() throws {
        let folder = RoutineFolder(name: "Race prep")
        folder.ownerUserId = Self.userId
        folder.updatedAt = nil

        let document = try RoutineRemoteSyncMapper.document(for: folder)

        #expect(document.updatedAt == folder.createdAt)
    }

    @Test
    func anUnreadableIntervalIsDroppedRatherThanFailingTheWholeRoutine() {
        let unreadable = FirestoreRoutineInterval(
            id: "not-a-uuid",
            durationSeconds: 60,
            intensityType: "level",
            intensityValue: 8,
            order: 0
        )

        #expect(RoutineRemoteSyncMapper.interval(from: unreadable) == nil)
    }
}
