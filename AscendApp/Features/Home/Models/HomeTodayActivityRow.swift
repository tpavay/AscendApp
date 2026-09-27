import Foundation

/// One uploaded climb on Home's ON THE GLOBE TODAY list, as the server projected it.
///
/// Identity travels as an `UnresolvedUserIdentity` and reaches a view only through
/// `CrossUserIdentityAdapter.homeTodayRow`, like every other row that names a climber.
struct HomeTodayActivityRow: Identifiable, Equatable, Sendable {
    let workoutId: String
    let userId: String
    let kind: HomeTodayActivityKind
    /// The landmark finished; only on a Live Climb row that reached the top.
    let climbId: String?
    /// The landmark a Live Climb that stopped short was climbing. Kept apart from
    /// `climbId` on the wire because 1.1 titles and opens `climbId` as a finish.
    let attemptClimbId: String?
    /// The catalog template run; only on a routine template row.
    let routineTemplateId: String?
    let steps: Int
    let durationSeconds: TimeInterval
    let completedAt: Date
    /// When the server first saw the workout. The feed orders on it, newest first.
    let publishedAt: Date
    let justClimbGoalKind: HomeTodayJustClimbGoalKind?
    /// Minutes for a duration goal, steps for a step goal.
    let justClimbGoalValue: Int?
    /// The session ended before its target: a Live Climb short of the top, a routine
    /// stopped early, a Just Climb stopped before its goal. Absent on the wire means a
    /// finish, which is every row a server before partial sessions ever wrote.
    let isPartial: Bool
    /// The climb's step count, on a Live Climb that stopped short.
    let targetSteps: Int?
    /// The plan's length, on a routine that stopped short.
    let targetDurationSeconds: TimeInterval?
    let unresolvedIdentity: UnresolvedUserIdentity
    let isCurrentUser: Bool

    var id: String { workoutId }

    init(
        workoutId: String,
        userId: String,
        kind: HomeTodayActivityKind,
        climbId: String? = nil,
        attemptClimbId: String? = nil,
        routineTemplateId: String? = nil,
        steps: Int,
        durationSeconds: TimeInterval,
        completedAt: Date,
        publishedAt: Date,
        justClimbGoalKind: HomeTodayJustClimbGoalKind? = nil,
        justClimbGoalValue: Int? = nil,
        isPartial: Bool = false,
        targetSteps: Int? = nil,
        targetDurationSeconds: TimeInterval? = nil,
        displayName: String,
        photoURL: URL?,
        avatarToken: String,
        isSynthetic: Bool,
        isCurrentUser: Bool = false
    ) {
        self.workoutId = workoutId
        self.userId = userId
        self.kind = kind
        self.climbId = climbId
        self.attemptClimbId = attemptClimbId
        self.routineTemplateId = routineTemplateId
        self.steps = max(steps, 0)
        self.durationSeconds = max(durationSeconds, 0)
        self.completedAt = completedAt
        self.publishedAt = publishedAt
        self.justClimbGoalKind = justClimbGoalKind
        self.justClimbGoalValue = justClimbGoalValue
        self.isPartial = isPartial
        self.targetSteps = targetSteps
        self.targetDurationSeconds = targetDurationSeconds
        self.unresolvedIdentity = UnresolvedUserIdentity(
            displayName: displayName,
            photoURL: photoURL,
            avatarToken: avatarToken,
            isSynthetic: isSynthetic
        )
        self.isCurrentUser = isCurrentUser
    }

    private init(source: HomeTodayActivityRow, isCurrentUser: Bool) {
        workoutId = source.workoutId
        userId = source.userId
        kind = source.kind
        climbId = source.climbId
        attemptClimbId = source.attemptClimbId
        routineTemplateId = source.routineTemplateId
        steps = source.steps
        durationSeconds = source.durationSeconds
        completedAt = source.completedAt
        publishedAt = source.publishedAt
        justClimbGoalKind = source.justClimbGoalKind
        justClimbGoalValue = source.justClimbGoalValue
        isPartial = source.isPartial
        targetSteps = source.targetSteps
        targetDurationSeconds = source.targetDurationSeconds
        unresolvedIdentity = source.unresolvedIdentity
        self.isCurrentUser = isCurrentUser
    }

    /// The same row, marked against the signed-in climber. The server does not know
    /// who is reading, so the viewer's own rows are marked on the device.
    func marking(currentUserId: String?) -> HomeTodayActivityRow {
        HomeTodayActivityRow(source: self, isCurrentUser: currentUserId == userId)
    }

    /// The landmark a Live Climb row stands on, finished or not.
    var landmarkClimbId: String? {
        guard kind == .liveClimb else { return nil }
        return climbId ?? attemptClimbId
    }

    /// The goal a Just Climb row can re-open, when the row is one.
    var justClimbGoal: JustClimbGoal? {
        guard kind == .justClimb else { return nil }
        switch justClimbGoalKind {
        case .duration:
            return JustClimbGoal(
                kind: .duration,
                durationMinutes: justClimbGoalValue ?? JustClimbGoal.defaultDurationMinutes
            )
        case .steps:
            return JustClimbGoal(
                kind: .steps,
                stepCount: justClimbGoalValue ?? JustClimbGoal.defaultStepCount
            )
        case .open, nil:
            return JustClimbGoal(kind: .open)
        }
    }
}
