import Combine
import Foundation
import SwiftData
import UIKit

/// Keeps the weekly-target nudge true to the week the climber is actually having.
///
/// The primer schedules the nudge once, from the target and no climbs, which is right only until the
/// first climb. This reads the climber's target and this week's climbs and hands them to
/// ``LocalReminderScheduler`` on launch, on every foreground, and on every change to the workout
/// store, so a climber who is back on pace stops being told they are behind and a new week starts
/// from nothing.
///
/// The read is bounded by the week, never by the climber's history: one fetch of the workouts
/// whose date falls in the current Monday week.
@MainActor
final class LocalReminderCoordinator {
    static let shared = LocalReminderCoordinator()

    private let scheduler: LocalReminderScheduler
    private let target: @MainActor () -> (days: Int?, usualMinutes: Int?)
    private let now: () -> Date
    private var modelContext: ModelContext?
    private var observers: Set<AnyCancellable> = []
    private var pending: Task<Void, Never>?

    /// - Parameter target: Where the climber's days-a-week target and usual climb length come
    ///   from. Until the profile carries the target after sign-in, it is the answer the onboarding
    ///   flow kept on the device; the profile becomes the source when it lands.
    init(
        scheduler: LocalReminderScheduler = .shared,
        target: @escaping @MainActor () -> (days: Int?, usualMinutes: Int?) = {
            let answers = PreAuthOnboardingStore().answers()
            return (answers.weeklyTargetDays, answers.usualClimbMinutes)
        },
        now: @escaping () -> Date = { .now }
    ) {
        self.scheduler = scheduler
        self.target = target
        self.now = now
    }

    /// Starts watching and reconciles once. Safe to call again: the latest context wins and the
    /// observers are installed once.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext

        if observers.isEmpty {
            NotificationCenter.default.publisher(for: .workoutsDidChange)
                .sink { [weak self] _ in self?.reconcileSoon() }
                .store(in: &observers)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in self?.reconcileSoon() }
                .store(in: &observers)
        }

        reconcileSoon()
    }

    /// Coalesces a burst of changes - a save posts several - into one reconcile.
    private func reconcileSoon() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    func reconcile() async {
        guard let modelContext else { return }

        let current = now()
        let calendar = WeekConfiguration.calendar()
        let target = target()
        let climbDates = Self.climbDates(
            inWeekOf: current,
            calendar: calendar,
            modelContext: modelContext
        )

        await scheduler.reconcileWeeklyTarget(
            targetDays: target.days,
            climbDates: climbDates,
            usualClimbMinutes: target.usualMinutes,
            now: current,
            calendar: calendar
        )
    }

    /// When the climber climbed this Monday week, from one predicate fetch bounded by the week.
    static func climbDates(
        inWeekOf date: Date,
        calendar: Calendar,
        modelContext: ModelContext
    ) -> [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let start = week.start
        let end = week.end
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.date >= start && workout.date < end
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.date)
    }
}
