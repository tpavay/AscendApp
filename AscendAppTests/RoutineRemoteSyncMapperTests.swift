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

    @Test
    func aRoutineWithAnOverlongNameIsNotUploaded() {
        let routine = Routine(
            name: String(repeating: "A", count: FirestoreUserRoutineDocument.maxNameLength + 1),
            source: .userCreated
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.nameTooLong(
                count: FirestoreUserRoutineDocument.maxNameLength + 1,
                limit: FirestoreUserRoutineDocument.maxNameLength
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    /// A name that only the copy suffix pushes over the line is the realistic
    /// way this happens: nothing in the editor caps the field, and
    /// `createUserCopy` appends to whatever is there.
    @Test
    func aRoutineAtTheNameCeilingIsUploaded() throws {
        let routine = Routine(
            name: String(repeating: "A", count: FirestoreUserRoutineDocument.maxNameLength),
            source: .userCreated
        )
        routine.ownerUserId = Self.userId

        let document = try RoutineRemoteSyncMapper.document(for: routine)

        #expect(document.name.count == FirestoreUserRoutineDocument.maxNameLength)
    }

    @Test
    func aRoutineWithAnOverlongDescriptionIsNotUploaded() {
        let routine = Routine(
            name: "Tuesday Pyramid",
            routineDescription: String(
                repeating: "b",
                count: FirestoreUserRoutineDocument.maxDescriptionLength + 1
            ),
            source: .userCreated
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.descriptionTooLong(
                count: FirestoreUserRoutineDocument.maxDescriptionLength + 1,
                limit: FirestoreUserRoutineDocument.maxDescriptionLength
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    /// The realistic way a routine breaches a numeric bound: `routine_templates`
    /// is server-authored and no client rule bounds what it publishes, so a
    /// template with an out-of-range difficulty walks straight into the climber's
    /// own routines the moment they tap Copy. Rejecting it client-side is the
    /// difference between one terminal diagnostic and a PERMISSION_DENIED retried
    /// on every launch forever.
    @Test("A copied template past the difficulty ceiling is rejected, not retried", .bug(id: 304))
    func aCopiedTemplateWithAnOutOfRangeDifficultyIsNotUploaded() {
        let template = Routine(
            name: "Pyramid Climb",
            source: .remoteTemplate,
            templateId: "pyramid_climb",
            difficulty: FirestoreUserRoutineDocument.maxDifficulty + 5
        )
        let copy = template.createUserCopy()
        copy.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.difficultyOutOfRange(
                value: FirestoreUserRoutineDocument.maxDifficulty + 5,
                minimum: FirestoreUserRoutineDocument.minDifficulty,
                maximum: FirestoreUserRoutineDocument.maxDifficulty
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: copy)
        }
    }

    @Test
    func aRoutineAtTheDifficultyCeilingIsUploaded() throws {
        let routine = Routine(
            name: "Everest",
            source: .userCreated,
            difficulty: FirestoreUserRoutineDocument.maxDifficulty
        )
        routine.ownerUserId = Self.userId

        let document = try RoutineRemoteSyncMapper.document(for: routine)

        #expect(document.difficulty == FirestoreUserRoutineDocument.maxDifficulty)
    }

    @Test
    func aRoutineWithAnOverlongTemplateIdIsNotUploaded() {
        let routine = Routine(
            name: "Copied",
            source: .copiedFromBuiltin,
            templateId: String(
                repeating: "t",
                count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1
            )
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.templateIdTooLong(
                count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1,
                limit: FirestoreUserRoutineDocument.maxTemplateIdLength
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutineWithANegativeCalorieEstimateIsNotUploaded() {
        let routine = Routine(name: "Impossible", source: .userCreated, estimatedCalories: -40)
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.negativeEstimatedCalories(value: -40)) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutineCarryingTooManyWeightEntriesIsNotUploaded() {
        let allTypes = WeightEquipmentType.allCases
        let entries = (0...FirestoreWorkoutWeightConfiguration.maxEntries).map { index in
            WeightEntry(equipmentType: allTypes[index % allTypes.count], weightValue: 10)
        }

        let routine = Routine(
            name: "Loaded",
            source: .userCreated,
            defaultWeightConfiguration: WeightConfiguration(entries: entries)
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.tooManyWeightEntries(
                count: FirestoreWorkoutWeightConfiguration.maxEntries + 1,
                limit: FirestoreWorkoutWeightConfiguration.maxEntries
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutineRepeatingAnEquipmentTypeIsNotUploaded() {
        let routine = Routine(
            name: "Double vest",
            source: .userCreated,
            defaultWeightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20),
                WeightEntry(equipmentType: .weightedVest, weightValue: 30)
            ])
        )
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.duplicateWeightEquipmentTypes(count: 2, distinct: 1)) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aRoutineCarryingANegativeWeightIsNotUploaded() {
        let routine = Routine(
            name: "Antigravity",
            source: .userCreated,
            defaultWeightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: -5)
            ])
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.negativeWeightValue(
                equipmentType: WeightEquipmentType.weightedVest.rawValue
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aNamelessRecordIsNotUploaded() {
        let routine = Routine(name: "", source: .userCreated)
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.emptyName) {
            _ = try RoutineRemoteSyncMapper.document(for: routine)
        }
    }

    @Test
    func aFolderWithAnOverlongNameIsNotUploaded() {
        let folder = RoutineFolder(
            name: String(repeating: "A", count: FirestoreRoutineFolderDocument.maxNameLength + 1)
        )
        folder.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.nameTooLong(
                count: FirestoreRoutineFolderDocument.maxNameLength + 1,
                limit: FirestoreRoutineFolderDocument.maxNameLength
            )
        ) {
            _ = try RoutineRemoteSyncMapper.document(for: folder)
        }
    }

    /// Rules measure a string in Unicode scalars, so the client has to. Swift's
    /// `count` reads this as one character where the server reads four, which is
    /// the difference between a name the client passes and the server denies.
    @Test
    func stringLengthIsMeasuredTheWayTheRulesMeasureIt() {
        #expect(RoutineRemoteSyncMapper.length(of: "👨‍👩‍👧") == 5)
    }

    /// Every bound the client enforces and the one `firestore.rules` enforces
    /// must be the same number. If they drift apart, either the client refuses
    /// writes the server would accept, or it retries writes the server will
    /// always reject - and a permanently denied write that keeps being retried
    /// is a routine that is never backed up and never says so.
    @Test
    func theClientFieldBoundsMatchTheRules() throws {
        let rules = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "firestore.rules"),
            encoding: .utf8
        )

        #expect(rules.contains("return \(FirestoreUserRoutineDocument.maxIntervals);"))
        #expect(
            rules.contains(
                "request.resource.data.name.size() <= \(FirestoreUserRoutineDocument.maxNameLength)"
            )
        )
        #expect(
            rules.contains(
                "request.resource.data.description.size() <= " +
                    "\(FirestoreUserRoutineDocument.maxDescriptionLength)"
            )
        )
        #expect(
            rules.contains(
                "request.resource.data.name.size() <= \(FirestoreRoutineFolderDocument.maxNameLength)"
            )
        )
        #expect(
            rules.contains(
                "request.resource.data.templateId.size() <= " +
                    "\(FirestoreUserRoutineDocument.maxTemplateIdLength)"
            )
        )
        #expect(
            rules.contains(
                "request.resource.data.difficulty >= \(FirestoreUserRoutineDocument.minDifficulty)"
            )
        )
        #expect(
            rules.contains(
                "request.resource.data.difficulty <= \(FirestoreUserRoutineDocument.maxDifficulty)"
            )
        )
        #expect(rules.contains("request.resource.data.estimatedCalories >= 0"))
        #expect(
            rules.contains("entries.size() <= \(FirestoreWorkoutWeightConfiguration.maxEntries)")
        )
        // The unique-equipment-type half of the entry-list rule has no number to
        // pin, so pin the helper the rule calls instead.
        #expect(rules.contains("hasUniqueWorkoutWeightEquipmentTypes(entries)"))
        #expect(rules.contains("isNonNegativeNumber(entry.weightValue)"))
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
