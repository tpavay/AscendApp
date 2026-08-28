import SwiftUI

/// Scope the camera roll to a year, or a month inside a year.
///
/// A wheel picker will happily let you choose a combination that holds nothing and only tell you
/// afterwards, so the primary button *is* the live count: it re-reads as the wheels move and
/// refuses to apply an empty window. That makes the empty-result state nearly unreachable rather
/// than a state to design and hope nobody sees.
struct ShareDateFilterSheet: View {
    /// Newest first, spanning only the years the roll actually covers.
    let availableYears: [Int]
    let current: ShareDateWindow?
    /// How many photos a candidate window would leave in the album already selected.
    let countProvider: (ShareDateWindow?) async -> Int
    let onApply: (ShareDateWindow?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// `nil` is the "Any year" row. Month is meaningless without it.
    @State private var selectedYear: Int?
    @State private var selectedMonth: Int?
    @State private var count: Int?
    @State private var isCounting = false

    private var candidate: ShareDateWindow? {
        guard let selectedYear else { return nil }
        return ShareDateWindow(year: selectedYear, month: selectedMonth)
    }

    private var canApply: Bool {
        // "Any time" always applies - it is how the filter is cleared.
        candidate == nil || (count ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            wheels
            applyButton
            note
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            selectedYear = current?.year
            selectedMonth = current?.month
        }
        .task(id: candidate) {
            await refreshCount()
        }
    }

    private var header: some View {
        ZStack {
            Text("Filter by date")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)

            HStack {
                Spacer()
                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    selectedYear = nil
                    selectedMonth = nil
                } label: {
                    Text("Clear")
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(selectedYear == nil
                            ? Color.white.opacity(0.28)
                            : Color.ascendAccent)
                }
                .buttonStyle(.plain)
                .disabled(selectedYear == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var wheels: some View {
        HStack(spacing: 10) {
            wheelColumn(title: "Year") {
                Picker("Year", selection: $selectedYear) {
                    Text("Any year").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
                .pickerStyle(.wheel)
                .onChange(of: selectedYear) { _, newValue in
                    // A month with no year is not a window.
                    if newValue == nil { selectedMonth = nil }
                }
            }

            wheelColumn(title: "Month") {
                Picker("Month", selection: $selectedMonth) {
                    Text("All months").tag(Int?.none)
                    ForEach(1...12, id: \.self) { month in
                        Text(Self.monthName(month)).tag(Int?.some(month))
                    }
                }
                .pickerStyle(.wheel)
                .disabled(selectedYear == nil)
                .opacity(selectedYear == nil ? 0.34 : 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private func wheelColumn<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 11))
                .tracking(1.4)
                .foregroundStyle(Color.customGray)

            content()
                .frame(height: 168)
                // Only the row content is ours - `.wheel` draws its own selection band and does not
                // allow restyling it.
                .tint(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var applyButton: some View {
        Button {
            guard canApply else { return }
            HapticsManager.shared.trigger(.lightImpact)
            onApply(candidate)
            dismiss()
        } label: {
            Text(buttonTitle.uppercased())
                .font(.montserratBold(size: 14))
                .tracking(1)
                .foregroundStyle(canApply ? .black.opacity(0.86) : .white.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canApply ? Color.ascendAccent : .white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(canApply ? .clear : .white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canApply)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var buttonTitle: String {
        guard let candidate else { return "Show all photos" }
        guard !isCounting, let count else { return "Checking \(candidate.displayName())" }
        guard count > 0 else { return "No photos in \(candidate.displayName())" }
        return "Show \(count.formatted(.number.grouping(.automatic))) photos"
    }

    private var note: some View {
        Text("Counts inside the album you already picked.")
            .font(.montserratRegular(size: 12))
            .foregroundStyle(Color.customGray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }

    private func refreshCount() async {
        guard candidate != nil else {
            count = nil
            isCounting = false
            return
        }
        isCounting = true
        let resolved = await countProvider(candidate)
        // The wheels may have moved on while this was in flight; `.task(id:)` cancels the stale one.
        guard !Task.isCancelled else { return }
        count = resolved
        isCounting = false
    }

    private static func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return String(month) }
        return date.formatted(.dateTime.month(.wide))
    }
}
