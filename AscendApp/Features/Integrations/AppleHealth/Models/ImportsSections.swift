import Foundation

/// One row on the Imports screen, with everything it draws and nothing it does not.
struct ImportsRow: Identifiable, Equatable, Sendable {
    /// The HealthKit workout UUID string, which is also the ledger row's key.
    let id: String
    let startDate: Date
    let duration: TimeInterval
    /// Exact steps, or nil where Health recorded none.
    let steps: Int?
    /// The climb this workout became. Nil while it is still waiting.
    let climbID: UUID?

    var isImported: Bool { climbID != nil }
}

/// Where the Imports screen puts each row: waiting workouts first, then the imported ones under
/// "This week" and "Earlier".
struct ImportsSections: Equatable, Sendable {
    var notImported: [ImportsRow] = []
    var thisWeek: [ImportsRow] = []
    var earlier: [ImportsRow] = []

    var isEmpty: Bool { notImported.isEmpty && thisWeek.isEmpty && earlier.isEmpty }
    var hasImported: Bool { !thisWeek.isEmpty || !earlier.isEmpty }

    /// Sections for the ledger rows the screen holds, newest first within each.
    ///
    /// "This week" is the Monday-to-Sunday week `now` falls in, the week every board and the
    /// weekly target use. An imported row shows the climb's own steps and time when the climb is
    /// still there, so an edit to either shows on the next draw.
    static func make(
        records: [HealthWorkoutRecord],
        climbs: [UUID: (steps: Int, duration: TimeInterval)],
        now: Date,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> ImportsSections {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast
        var sections = ImportsSections()

        for record in records.sorted(by: { $0.startDate > $1.startDate }) {
            switch record.state {
            case .notImported:
                sections.notImported.append(
                    ImportsRow(
                        id: record.workoutUUID,
                        startDate: record.startDate,
                        duration: record.durationSeconds,
                        steps: record.steps,
                        climbID: nil
                    )
                )
            case .imported:
                guard let climbID = record.importedWorkoutID else { continue }
                let climb = climbs[climbID]
                let row = ImportsRow(
                    id: record.workoutUUID,
                    startDate: record.startDate,
                    duration: climb?.duration ?? record.durationSeconds,
                    steps: climb.map { $0.steps > 0 ? $0.steps : nil } ?? record.steps,
                    climbID: climbID
                )
                if record.startDate >= weekStart {
                    sections.thisWeek.append(row)
                } else {
                    sections.earlier.append(row)
                }
            case .skipped, .overlapsLiveClimb:
                continue
            }
        }
        return sections
    }
}

/// How an Imports row words itself.
enum ImportsRowFormat {
    /// `4,912 steps` or `— steps` where Health recorded none.
    static func stepsText(_ steps: Int?) -> String {
        guard let steps else { return "— steps" }
        return "\(steps.formatted()) steps"
    }

    /// `1:02:50`, or `41:12` under an hour.
    static func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// `Today · 7:44 AM`, `Yesterday · 6:10 PM`, `Tue, Oct 27 · 6:10 PM`.
    static func whenText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today · \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday · \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(time)"
    }
}
