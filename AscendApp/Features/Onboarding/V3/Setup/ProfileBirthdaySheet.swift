import SwiftUI

/// The birthday sheet: a month, day and year wheel. It holds its own working date, opened at about
/// thirty years back or at the stored birthday, and hands a date back only when Done is tapped.
struct ProfileBirthdaySheet: View {
    /// Fixes the clock the wheel's range is counted from.
    var now: Date = .now

    @State private var date: Date
    private let onDone: (Date) -> Void

    init(initial: Date?, now: Date = .now, onDone: @escaping (Date) -> Void) {
        self.now = now
        _date = State(initialValue: initial ?? ProfileSetupDraft.wheelStart(on: now))
        self.onDone = onDone
    }

    var body: some View {
        ProfileSheetFrame(
            title: "Birthday",
            note: "Only your age shows. Never the date.",
            onDone: { onDone(date) }
        ) {
            DatePicker(
                "Birthday",
                selection: $date,
                in: ProfileSetupDraft.birthdayRange(on: now),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
        }
        .appSheetStyle(.height(ProfileSheetHeight.birthday))
    }
}
