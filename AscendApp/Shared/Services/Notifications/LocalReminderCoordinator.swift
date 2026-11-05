import Combine
import Foundation
import SwiftData
import UIKit

/// Keeps the weekly-target nudge true to the week the climber is actually having.
///
/// This is the one caller of the weekly reconcile. It reads the climber's target and this week's
/// climbs and hands them to ``LocalReminderScheduler`` on launch, on every foreground, on every
/// change to the workout store and on every write of the notification answer - the primer's TURN ON
/// and Not now and the Settings toggle all land there - so a climber who is back on pace stops being
/// told they are behind, a new week starts from nothing, and an answer takes effect when it is given.
///
/// The read is bounded by the week, never by the climber's history: one fetch of the workouts
/// whose date falls in the current Monday week.
@MainActor
final class LocalReminderCoordinator {
    static let shared = LocalReminderCoordinator()

    private let scheduler: LocalReminderScheduler
    private let store: PreAuthOnboardingStore
    private let now: () -> Date
    private var modelContext: ModelContext?
    private var observers: Set<AnyCancellable> = []
    private var pending: Task<Void, Never>?

    /// - Parameter store: Where the climber's days-a-week target and usual climb length come
    ///   from. Until the profile carries the target after sign-in, it is the answer the onboarding
    ///   flow kept on the device; the profile becomes the source when it lands.
    init(
        scheduler: LocalReminderScheduler = .shared,
        store: PreAuthOnboardingStore = PreAuthOnboardingStore(),
        now: @escaping () -> Date = { .now }
    ) {
        self.scheduler = scheduler
        self.store = store
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
            NotificationCenter.default.publisher(for: .climbDropNotificationPreferenceDidChange)
                .sink { [weak self] _ in self?.reconcileSoon() }
                .store(in: &observers)
        }

        reconcileSoon()
    }

    /// A session ended: the climber who set the target has left the phone. Forgets their target, so
    /// no later reconcile re-arms the nudge for nobody and the next account does not inherit it,
    /// and clears what is pending. The follow-up reconcile catches a schedule already in flight.
    func sessionEnded() {
        store.update { $0.weeklyTargetDays = nil }
        scheduler.cancelAll()
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
        let answers = store.answers()
        let climbDates = Self.climbDates(
            inWeekOf: current,
            calendar: calendar,
            modelContext: modelContext
        )

        await scheduler.reconcileWeeklyTarget(
            targetDays: answers.weeklyTargetDays,
            climbDates: climbDates,
            usualClimbMinutes: answers.usualClimbMinutes,
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
