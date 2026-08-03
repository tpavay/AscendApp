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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
        }
    }

    @Test
    func aCatalogTemplateIsNotUploaded() {
        let routine = Routine(name: "Pyramid Climb", source: .remoteTemplate, templateId: "pyramid")
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.notUserAuthored) {
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
        }
    }

    @Test
    func aRoutineAtTheIntervalCeilingIsUploaded() throws {
        let routine = Routine(name: "Twenty rounds", source: .userCreated)
        routine.ownerUserId = Self.userId
        routine.intervals = (0..<FirestoreUserRoutineDocument.maxIntervals).map { index in
            RoutineInterval(duration: 30, intensityValue: 5, order: index)
        }

        let document = try RoutineRemoteSyncMapper.build(for: routine).document

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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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

        let document = try RoutineRemoteSyncMapper.build(for: routine).document

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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
        }
    }

    /// The metadata a climber never types. `routine_templates` is server-authored
    /// and nothing bounds what it publishes (issue #364), so an out-of-range
    /// difficulty walks straight into the climber's own routines the moment they
    /// tap Copy. Refusing the whole routine over it would leave a name and
    /// intervals that are perfectly valid permanently unbacked because of a number
    /// we shipped - so the number is repaired and the routine goes up. Nothing
    /// looks a routine up by its difficulty, which is what puts it on the
    /// converged side of the rule.
    @Test("A copied template's out-of-range difficulty is clamped, not fatal", .bug(id: 304))
    func aCopiedTemplateWithAnOutOfRangeDifficultyIsClampedAndUploaded() throws {
        let template = Routine(
            name: "Pyramid Climb",
            source: .remoteTemplate,
            templateId: "pyramid_climb",
            difficulty: FirestoreUserRoutineDocument.maxDifficulty + 5
        )
        let copy = template.createUserCopy()
        copy.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: copy)

        #expect(build.document.difficulty == FirestoreUserRoutineDocument.maxDifficulty)
        #expect(
            build.repairs == [
                .difficultyClamped(
                    from: FirestoreUserRoutineDocument.maxDifficulty + 5,
                    to: FirestoreUserRoutineDocument.maxDifficulty,
                    minimum: FirestoreUserRoutineDocument.minDifficulty,
                    maximum: FirestoreUserRoutineDocument.maxDifficulty
                )
            ]
        )
        // The climber's own work is untouched by the repair.
        #expect(build.document.name == copy.name)
        #expect(build.document.intervals.count == copy.intervals.count)
    }

    @Test
    func aNegativeDifficultyIsClampedUpAndConverged() throws {
        let routine = Routine(name: "Below zero", source: .userCreated, difficulty: -3)
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)
        RoutineRemoteSyncMapper.applyRepairs(build.repairs, to: routine)

        #expect(build.document.difficulty == FirestoreUserRoutineDocument.minDifficulty)
        #expect(build.repairs.count == 1)
        #expect(routine.difficulty == FirestoreUserRoutineDocument.minDifficulty)
    }

    @Test
    func aRoutineAtTheDifficultyCeilingIsUploadedUnrepaired() throws {
        let routine = Routine(
            name: "Everest",
            source: .userCreated,
            difficulty: FirestoreUserRoutineDocument.maxDifficulty
        )
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)

        #expect(build.document.difficulty == FirestoreUserRoutineDocument.maxDifficulty)
        #expect(build.repairs.isEmpty)
    }

    /// The repaired-on-the-way-out side of the rule. Dropped rather than
    /// truncated, because an id cut to fit can name a different template and
    /// wrong provenance is worse than none - and dropped from the document only,
    /// because `savedCopy(templateId:)` matches on the local id.
    @Test
    func anOverlongTemplateIdIsDroppedFromTheDocumentOnly() throws {
        let overlongId = String(
            repeating: "t",
            count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1
        )
        let routine = Routine(name: "Copied", source: .copiedFromBuiltin, templateId: overlongId)
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)

        #expect(build.document.templateId == nil)
        #expect(
            build.repairs == [
                .templateIdDropped(
                    count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1,
                    limit: FirestoreUserRoutineDocument.maxTemplateIdLength
                )
            ]
        )
        #expect(routine.templateId == overlongId)
    }

    /// The Save toggle reads `savedCopy(templateId:)`, which matches on the local
    /// id. Converging the drop onto the record would make the toggle read unsaved
    /// after every backup, so each tap would mint another copy and un-saving
    /// would become unreachable.
    @Test("A dropped templateId leaves the Save toggle working", .bug(id: 304))
    func aDroppedTemplateIdIsNeverConvergedOntoTheLocalRecord() throws {
        let overlongId = String(
            repeating: "t",
            count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1
        )
        let routine = Routine(name: "Copied", source: .copiedFromBuiltin, templateId: overlongId)
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)
        RoutineRemoteSyncMapper.applyRepairs(build.repairs, to: routine)

        #expect(routine.templateId == overlongId)
    }

    @Test
    func anEmptyTemplateIdIsDroppedFromTheDocumentOnly() throws {
        let routine = Routine(name: "Copied", source: .copiedFromBuiltin, templateId: "")
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)
        RoutineRemoteSyncMapper.applyRepairs(build.repairs, to: routine)

        #expect(build.document.templateId == nil)
        #expect(
            build.repairs == [
                .templateIdDropped(
                    count: 0,
                    limit: FirestoreUserRoutineDocument.maxTemplateIdLength
                )
            ]
        )
        #expect(routine.templateId == "")
    }

    /// Clamped on the way out and left alone in the store: no local reader has
    /// been ruled out, and the round that converged by pattern-matching on
    /// "server authored" got it wrong twice.
    @Test
    func aNegativeTemplateVersionIsClampedOnTheDocumentOnly() throws {
        let routine = Routine(
            name: "Copied",
            source: .copiedFromBuiltin,
            templateId: "pyramid_climb",
            templateVersion: -2
        )
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)
        RoutineRemoteSyncMapper.applyRepairs(build.repairs, to: routine)

        #expect(build.document.templateVersion == 0)
        #expect(build.repairs == [.templateVersionClamped(from: -2, to: 0)])
        #expect(routine.templateVersion == -2)
    }

    /// The converged side of the rule: nothing looks a routine up by its calorie
    /// estimate, so the local record is brought into line and the repair stops
    /// being one.
    @Test
    func aNegativeCalorieEstimateIsClampedAndConverged() throws {
        let routine = Routine(name: "Impossible", source: .userCreated, estimatedCalories: -40)
        routine.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: routine)
        RoutineRemoteSyncMapper.applyRepairs(build.repairs, to: routine)

        #expect(build.document.estimatedCalories == 0)
        #expect(build.repairs == [.estimatedCaloriesClamped(from: -40, to: 0)])
        #expect(routine.estimatedCalories == 0)
    }

    /// A repair never rescues a routine whose own content is out of bounds - the
    /// climber's name still costs the backup, and that is the line the policy
    /// draws.
    @Test
    func aRepairableFieldDoesNotRescueAnOverlongName() {
        let routine = Routine(
            name: String(repeating: "A", count: FirestoreUserRoutineDocument.maxNameLength + 1),
            source: .userCreated,
            difficulty: FirestoreUserRoutineDocument.maxDifficulty + 5
        )
        routine.ownerUserId = Self.userId

        #expect(
            throws: RoutineSyncError.nameTooLong(
                count: FirestoreUserRoutineDocument.maxNameLength + 1,
                limit: FirestoreUserRoutineDocument.maxNameLength
            )
        ) {
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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
            _ = try RoutineRemoteSyncMapper.build(for: routine)
        }
    }

    @Test
    func aNamelessRecordIsNotUploaded() {
        let routine = Routine(name: "", source: .userCreated)
        routine.ownerUserId = Self.userId

        #expect(throws: RoutineSyncError.emptyName) {
            _ = try RoutineRemoteSyncMapper.build(for: routine)
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
            _ = try RoutineRemoteSyncMapper.build(for: folder)
        }
    }

    /// The validated-never-repaired side of the rule. A folder colour is copied
    /// out of no catalog document - `createFolder` takes whatever its caller
    /// hands it - so it is the climber's pick, and dropping or rewriting it would
    /// silently discard a choice they can see. It costs the folder its backup,
    /// exactly like an over-long folder name.
    @Test("A folder colour the rules refuse is rejected, never rewritten", .bug(id: 304))
    func aFolderColourTheRulesRefuseIsRejectedRatherThanRepaired() {
        for unusable in ["lime", "86D30A", "#86D30AFF", "#86D30", "#86d30ag"] {
            let folder = RoutineFolder(name: "Race prep", colorHex: unusable)
            folder.ownerUserId = Self.userId

            #expect(
                throws: RoutineSyncError.unusableFolderColor(
                    pattern: FirestoreRoutineFolderDocument.colorHexPattern
                )
            ) {
                _ = try RoutineRemoteSyncMapper.build(for: folder)
            }
            #expect(folder.colorHex == unusable)
        }
    }

    @Test
    func aFolderColourTheRulesAcceptSurvivesInEitherCase() throws {
        for usable in ["#86D30A", "#86d30a"] {
            let folder = RoutineFolder(name: "Race prep", colorHex: usable)
            folder.ownerUserId = Self.userId

            let build = try RoutineRemoteSyncMapper.build(for: folder)

            #expect(build.document.colorHex == usable)
            #expect(build.repairs.isEmpty)
        }
    }

    @Test
    func aFolderWithNoColourIsUploadedUnrepaired() throws {
        let folder = RoutineFolder(name: "Race prep")
        folder.ownerUserId = Self.userId

        let build = try RoutineRemoteSyncMapper.build(for: folder)

        #expect(build.document.colorHex == nil)
        #expect(build.repairs.isEmpty)
    }

    /// Rules measure a string in Unicode scalars, so the client has to. Swift's
    /// `count` reads this as one character where the server reads four, which is
    /// the difference between a name the client passes and the server denies.
    @Test
    func stringLengthIsMeasuredTheWayTheRulesMeasureIt() {
        #expect(RoutineRemoteSyncMapper.length(of: "👨‍👩‍👧") == 5)
    }

    /// Every bound the client enforces - whether it refuses the record or repairs
    /// it - and the one `firestore.rules` enforces must be the same number. If
    /// they drift apart, either the client refuses writes the server would accept,
    /// or it retries writes the server will always reject, and a permanently
    /// denied write that keeps being retried is a routine that is never backed up
    /// and never says so.
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
        #expect(
            rules.contains(
                "request.resource.data.colorHex.matches(" +
                    "\"\(FirestoreRoutineFolderDocument.colorHexPattern)\")"
            )
        )
    }

    @Test
    func aFolderWithNoOwnerIsNotUploaded() {
        #expect(throws: RoutineSyncError.missingOwner) {
            _ = try RoutineRemoteSyncMapper.build(for: RoutineFolder(name: "Orphan"))
        }
    }

    @Test
    func anUneditedFolderBacksUpItsCreationDateAsItsUpdatedAt() throws {
        let folder = RoutineFolder(name: "Race prep")
        folder.ownerUserId = Self.userId
        folder.updatedAt = nil

        let document = try RoutineRemoteSyncMapper.build(for: folder).document

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
