import Foundation

/// What the sign-in hand-off runs for 07a's ADD TO MY HISTORY: brings in the workouts the climber
/// was shown, and says whether they landed.
///
/// It is the hand-off's `importHealthHistory` seam, kept here so the one thing it has to get right
/// - nothing runs without the climber's yes, and nothing is dropped until the climb exists - has a
/// home and a test.
@MainActor
enum OnboardingHealthHistoryImport {
    /// - Returns: True when there was nothing to bring in or every workout landed, so the hand-off
    ///   may drop the identifiers. False keeps them for the next run.
    static func run(
        _ answers: PreAuthOnboardingAnswers,
        service: AppleHealthImportService = .shared,
        joinDate: Date? = AccountJoinDate.current()
    ) async -> Bool {
        guard !answers.foundHealthWorkoutIDs.isEmpty else { return true }
        // No account date is no account: the import has nothing to be before.
        guard let joinDate else { return false }

        return await service.importHistory(
            before: joinDate,
            matching: Set(answers.foundHealthWorkoutIDs)
        )
    }
}
