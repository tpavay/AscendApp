import Foundation

/// One interval of a user-authored routine, as it is stored in Firestore.
///
/// `IntervalModifiers` is flattened rather than nested: the modifiers are a
/// handful of optional scalars, and a nested map would buy nothing but another
/// level for a decoder to get wrong.
struct FirestoreRoutineInterval: Codable, Equatable, Sendable {
    let id: String
    let durationSeconds: Double
    let intensityType: String
    let intensityValue: Int
    let order: Int
    let sidewaysDirection: String?
    let skipStep: Bool?
    let backwardStep: Bool?
    let holdingBars: Bool?

    /// Equipment enabled for this interval specifically.
    ///
    /// Carries three distinct meanings and all three have to survive the round
    /// trip: absent means "inherit the routine defaults", empty means "no
    /// weights on this interval", and populated means "only these".
    let weightOverrideEquipmentTypes: [String]?

    init(
        id: String,
        durationSeconds: Double,
        intensityType: String,
        intensityValue: Int,
        order: Int,
        sidewaysDirection: String? = nil,
        skipStep: Bool? = nil,
        backwardStep: Bool? = nil,
        holdingBars: Bool? = nil,
        weightOverrideEquipmentTypes: [String]? = nil
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.intensityType = intensityType
        self.intensityValue = intensityValue
        self.order = order
        self.sidewaysDirection = sidewaysDirection
        self.skipStep = skipStep
        self.backwardStep = backwardStep
        self.holdingBars = holdingBars
        self.weightOverrideEquipmentTypes = weightOverrideEquipmentTypes
    }
}

/// A routine the climber built themselves, as it is stored at
/// `users/{uid}/routines/{routineId}`.
///
/// Catalog templates never appear here - see `Routine.isUserAuthored`.
struct FirestoreUserRoutineDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    /// The most intervals one routine may back up.
    ///
    /// Mirrors `maxRoutineIntervals()` in `firestore.rules`, which is where it
    /// is actually enforced. Kept here so the client can refuse a write the
    /// server would reject rather than retrying it on every launch forever.
    static let maxIntervals = 40

    /// The longest name and description one routine may back up.
    ///
    /// Mirrors the `name.size()` and `description.size()` bounds in
    /// `firestore.rules` for the same reason `maxIntervals` does: a write past
    /// them comes back as a bare `PERMISSION_DENIED`, which is indistinguishable
    /// from a transient failure and would be retried on every launch forever
    /// while the routine stays unbacked. Counted in Unicode scalars because that
    /// is what `size()` counts in rules.
    static let maxNameLength = 120
    static let maxDescriptionLength = 2000

    /// The longest `templateId` the backup accepts, mirroring the
    /// `templateId.size()` bound in `firestore.rules`.
    static let maxTemplateIdLength = 160

    /// The difficulty range the backup accepts, mirroring the `difficulty`
    /// bounds in `firestore.rules`.
    ///
    /// A copied catalog template carries the published template's difficulty
    /// through unchanged, and nothing bounds what a `routine_templates`
    /// document may publish - so this is the bound a climber reaches by tapping
    /// Copy, not by editing anything.
    static let minDifficulty = 0
    static let maxDifficulty = 25

    let userId: String
    let schemaVersion: Int
    let name: String
    let description: String
    let source: String
    let intervals: [FirestoreRoutineInterval]
    let folderId: String?
    let isArchived: Bool
    let order: Int
    let templateId: String?
    let templateVersion: Int?
    let difficulty: Int?
    let estimatedCalories: Int?
    let defaultWeightConfiguration: FirestoreWorkoutWeightConfiguration?
    let completionCount: Int
    let lastCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        userId: String,
        schemaVersion: Int = FirestoreUserRoutineDocument.currentSchemaVersion,
        name: String,
        description: String,
        source: String,
        intervals: [FirestoreRoutineInterval],
        folderId: String? = nil,
        isArchived: Bool,
        order: Int,
        templateId: String? = nil,
        templateVersion: Int? = nil,
        difficulty: Int? = nil,
        estimatedCalories: Int? = nil,
        defaultWeightConfiguration: FirestoreWorkoutWeightConfiguration? = nil,
        completionCount: Int,
        lastCompletedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.userId = userId
        self.schemaVersion = schemaVersion
        self.name = name
        self.description = description
        self.source = source
        self.intervals = intervals
        self.folderId = folderId
        self.isArchived = isArchived
        self.order = order
        self.templateId = templateId
        self.templateVersion = templateVersion
        self.difficulty = difficulty
        self.estimatedCalories = estimatedCalories
        self.defaultWeightConfiguration = defaultWeightConfiguration
        self.completionCount = completionCount
        self.lastCompletedAt = lastCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A folder the climber organises routines into, as it is stored at
/// `users/{uid}/routine_folders/{folderId}`.
struct FirestoreRoutineFolderDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    /// The longest folder name the backup accepts, mirroring `name.size()` in
    /// `firestore.rules`. Folders get their own bound because the rule does.
    static let maxNameLength = 80

    let userId: String
    let schemaVersion: Int
    let name: String
    let colorHex: String?
    let order: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        userId: String,
        schemaVersion: Int = FirestoreRoutineFolderDocument.currentSchemaVersion,
        name: String,
        colorHex: String? = nil,
        order: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.userId = userId
        self.schemaVersion = schemaVersion
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A backed-up routine paired with the id of the document it came from.
struct RemoteUserRoutineRecord: Equatable, Sendable {
    let routineId: UUID
    let document: FirestoreUserRoutineDocument
}

/// A backed-up folder paired with the id of the document it came from.
struct RemoteRoutineFolderRecord: Equatable, Sendable {
    let folderId: UUID
    let document: FirestoreRoutineFolderDocument
}
