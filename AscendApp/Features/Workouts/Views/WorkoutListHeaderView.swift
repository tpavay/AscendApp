//
//  WorkoutListHeaderView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutListHeaderView: View {
    let isInDeleteMode: Bool
    let totalCount: Int
    let effectiveColorScheme: ColorScheme
    let pendingImportCount: Int
    let workouts: [Workout]
    @Bindable var filterState: WorkoutListFilterState
    let onCancelDelete: () -> Void
    let onImportTapped: () -> Void
    let onEnterDeleteMode: () -> Void

    @State private var isSearchExpanded = false
    @State private var activeSheet: FilterSheet?
    @State private var showingSortSheet = false
    @FocusState private var isSearchFocused: Bool
    @State private var settingsManager = SettingsManager.shared

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    enum FilterSheet: Identifiable {
        case source
        case steps
        case dates
        case duration

        var id: String {
            switch self {
            case .source: return "source"
            case .steps: return "steps"
            case .dates: return "dates"
            case .duration: return "duration"
            }
        }

        var presentationDetents: Set<PresentationDetent> {
            switch self {
            case .source:
                return [.height(CGFloat(480))]
            case .steps, .duration:
                return [.height(CGFloat(260))]
            case .dates:
                return [.fraction(0.85)]
            }
        }
    }

    enum FilterChip: String, CaseIterable, Identifiable {
        case source
        case steps
        case dates
        case duration

        var id: String { rawValue }

        func label(for metric: WorkoutMetric) -> String {
            switch self {
            case .source: return "Source"
            case .steps: return metric.displayName
            case .dates: return "Dates"
            case .duration: return "Duration"
            }
        }

        var associatedSheet: FilterSheet {
            switch self {
            case .source: return .source
            case .steps: return .steps
            case .dates: return .dates
            case .duration: return .duration
            }
        }
    }

    private var stepsBounds: ClosedRange<Double> {
        let maxValue = workouts.map { $0.metricValue(for: preferredMetric) }.max() ?? 0
        let upper = maxValue > 0 ? Double(maxValue) : 1000
        return 0...max(upper, 1)
    }

    private var durationBounds: ClosedRange<Double> {
        let maxDuration = workouts.map(\.duration).max() ?? 0
        let fallback: Double = maxDuration > 0 ? maxDuration : 3600
        return 0...fallback
    }

    private var dateBounds: ClosedRange<Date> {
        guard let earliest = workouts.map(\.date).min(),
              let latest = workouts.map(\.date).max() else {
            let today = Date()
            return today...today
        }
        return earliest...latest
    }

    private static let stepsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, isSearchExpanded ? 12 : 16)

            // Expandable search and filter section
            if isSearchExpanded && !isInDeleteMode && totalCount > 0 {
                VStack(spacing: 12) {
                    searchField
                    filterChipStrip
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)
        }
        .background(
            (effectiveColorScheme == .dark ? Color.jet : Color.white)
                .opacity(0.95)
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isSearchFocused = false
                } label: {
                    Text("Done")
                        .font(.montserratSemiBold(size: 16))
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .source:
                WorkoutSourceFilterSheet(filterState: filterState, effectiveColorScheme: effectiveColorScheme)
                    .presentationDetents(sheet.presentationDetents)
                    .presentationDragIndicator(.visible)
            case .steps:
                StepsFilterSheet(
                    filterState: filterState,
                    bounds: stepsBounds,
                    formatter: Self.stepsFormatter,
                    preferredMetric: preferredMetric,
                    effectiveColorScheme: effectiveColorScheme
                )
                .presentationDetents(sheet.presentationDetents)
                .presentationDragIndicator(.visible)
            case .dates:
                DatesFilterSheet(filterState: filterState, bounds: dateBounds, effectiveColorScheme: effectiveColorScheme)
                    .presentationDetents(sheet.presentationDetents)
                    .presentationDragIndicator(.visible)
            case .duration:
                DurationFilterSheet(filterState: filterState, bounds: durationBounds, effectiveColorScheme: effectiveColorScheme)
                    .presentationDetents(sheet.presentationDetents)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingSortSheet) {
            SortOptionSheet(
                filterState: filterState,
                effectiveColorScheme: effectiveColorScheme,
                preferredMetric: preferredMetric
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            if isInDeleteMode {
                Text("Select Workouts")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Button("Cancel", action: onCancelDelete)
                    .foregroundStyle(.accent)
                    .font(.montserratMedium(size: 16))
            } else {
                // Normal mode - compact header like leaderboard
                Text("Workouts")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                if totalCount > 0 {
                    // Search button
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearchExpanded.toggle()
                            if !isSearchExpanded {
                                // Reset filters when collapsing
                                filterState.resetAll()
                            }
                        }
                        HapticsManager.shared.trigger(.lightImpact)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }

                    // Sort button
                    Button {
                        showingSortSheet = true
                        HapticsManager.shared.trigger(.lightImpact)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(filterState.sortOption != .dateNewest ? .accent : (effectiveColorScheme == .dark ? .white : .black))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }

                    // Overflow menu
                    overflowMenu
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $filterState.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.montserratRegular(size: 14))
                .focused($isSearchFocused)

            if !filterState.searchText.isEmpty {
                Button {
                    filterState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchExpanded = false
                    filterState.resetAll()
                }
                isSearchFocused = false
            } label: {
                Text("Cancel")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.08))
        )
    }

    private var filterChipStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(FilterChip.allCases) { chip in
                    Button {
                        HapticsManager.shared.trigger(.lightImpact)
                        isSearchFocused = false
                        activeSheet = chip.associatedSheet
                    } label: {
                        FilterChipView(
                            title: chip.label(for: preferredMetric),
                            isActive: isActive(chip),
                            colorScheme: effectiveColorScheme
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func isActive(_ chip: FilterChip) -> Bool {
        switch chip {
        case .source:
            return !filterState.selectedSources.isEmpty
        case .steps:
            return filterState.stepsRange != nil
        case .dates:
            return filterState.dateFilter != nil
        case .duration:
            return filterState.durationRange != nil
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onImportTapped) {
                HStack {
                    Label("Import Workouts", systemImage: "square.and.arrow.down")
                    if pendingImportCount > 0 {
                        Text("(\(pendingImportCount))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Button(action: onEnterDeleteMode) {
                Label("Delete Workouts", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
    }
}

// MARK: - Filter Chip View

private struct FilterChipView: View {
    let title: String
    let isActive: Bool
    let colorScheme: ColorScheme

    private var activeBackground: Color {
        isActive ? .accent.opacity(0.15) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.12))
    }

    private var activeBorder: Color {
        isActive ? .accent : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.3))
    }

    private var activeTextColor: Color {
        isActive ? .accent : (colorScheme == .dark ? .white : .black)
    }

    var body: some View {
        Text(title)
            .font(.montserratSemiBold(size: 13))
            .foregroundStyle(activeTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(activeBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(activeBorder, lineWidth: isActive ? 1.5 : 1)
            )
    }
}

// MARK: - Filter Sheets

private struct WorkoutSourceFilterSheet: View {
    var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    let effectiveColorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Workout Source")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Choose the sources you want to include.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(WorkoutSource.allCases, id: \.self) { source in
                    Button {
                        toggleSelection(for: source)
                    } label: {
                        HStack {
                            Text(source.displayName)
                                .font(.montserratMedium(size: 16))
                            Spacer()
                            Image(systemName: filterState.selectedSources.contains(source) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(filterState.selectedSources.contains(source) ? .accent : .gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !filterState.selectedSources.isEmpty {
                Button("Clear Selection") {
                    HapticsManager.shared.trigger(.lightImpact)
                    withAnimation(.easeInOut) {
                        filterState.selectedSources.removeAll()
                    }
                }
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.accent)
            }
        }
        .padding(20)
        .padding(.bottom, 12)
        .themedBackground()
    }

    private func toggleSelection(for source: WorkoutSource) {
        HapticsManager.shared.trigger(.selection)
        withAnimation(.easeInOut) {
            if filterState.selectedSources.contains(source) {
                filterState.selectedSources.remove(source)
            } else {
                filterState.selectedSources.insert(source)
            }
        }
    }
}

private struct StepsFilterSheet: View {
    var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    let bounds: ClosedRange<Double>
    let formatter: NumberFormatter
    let preferredMetric: WorkoutMetric
    let effectiveColorScheme: ColorScheme

    @State private var minValue: Double = 0
    @State private var maxValue: Double = 0

    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Double>, formatter: NumberFormatter, preferredMetric: WorkoutMetric, effectiveColorScheme: ColorScheme) {
        self.filterState = filterState
        self.bounds = bounds
        self.formatter = formatter
        self.preferredMetric = preferredMetric
        self.effectiveColorScheme = effectiveColorScheme
        let initialRange = filterState.stepsRange ?? bounds
        let clampedLower = max(bounds.lowerBound, min(initialRange.lowerBound, bounds.upperBound))
        let clampedUpper = max(clampedLower, min(initialRange.upperBound, bounds.upperBound))
        _minValue = State(initialValue: clampedLower)
        _maxValue = State(initialValue: clampedUpper)
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("\(preferredMetric.displayName) Range")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Filter workouts by the recorded \(preferredMetric.unit).")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                HStack {
                    valueSummary(title: "Min", value: formattedSteps(minValue))
                    Spacer()
                    valueSummary(title: "Max", value: formattedSteps(maxValue))
                }

                WorkoutFilterRangeSlider(
                    lowerValue: $minValue,
                    upperValue: $maxValue,
                    bounds: bounds,
                    step: sliderStep(for: bounds.upperBound)
                )
            }

            if filterState.stepsRange != nil {
                Button("Clear Filter") {
                    HapticsManager.shared.trigger(.lightImpact)
                    minValue = bounds.lowerBound
                    maxValue = bounds.upperBound
                    filterState.stepsRange = nil
                }
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.accent)
            }
        }
        .padding(20)
        .padding(.bottom, 12)
        .themedBackground()
        .onChange(of: minValue) { _, newValue in
            updateFilter()
        }
        .onChange(of: maxValue) { _, newValue in
            updateFilter()
        }
    }

    private func updateFilter() {
        let selectedRange = minValue...maxValue
        filterState.stepsRange = selectedRange == bounds ? nil : selectedRange
    }

    private func formattedSteps(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
    }

    private func sliderStep(for upperBound: Double) -> Double {
        guard upperBound > 0 else { return 1 }
        let approx = floor(upperBound / 50)
        return max(1, approx)
    }

    private func valueSummary(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.accent)
        }
    }
}

private struct DatesFilterSheet: View {
    var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    let bounds: ClosedRange<Date>
    let effectiveColorScheme: ColorScheme

    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isRangeEnabled: Bool = true
    @State private var focusedField: DateField = .start

    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Date>, effectiveColorScheme: ColorScheme) {
        self.filterState = filterState
        self.bounds = bounds
        self.effectiveColorScheme = effectiveColorScheme
        let storedFilter = filterState.dateFilter
        let startSeed = storedFilter?.start ?? bounds.lowerBound
        let clampedStart = max(bounds.lowerBound, min(startSeed, bounds.upperBound))
        let endSeed: Date
        if let explicitEnd = storedFilter?.end {
            endSeed = explicitEnd
        } else if storedFilter == nil {
            endSeed = bounds.upperBound
        } else {
            endSeed = clampedStart
        }
        let clampedEnd = max(clampedStart, min(endSeed, bounds.upperBound))
        _startDate = State(initialValue: clampedStart)
        _endDate = State(initialValue: clampedEnd)
        _isRangeEnabled = State(initialValue: storedFilter?.isRange ?? true)
        _focusedField = State(initialValue: .start)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Date Range")
                        .font(.montserratSemiBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    Text("Only show workouts completed between these dates.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    toggleRow

                    dateField(title: "Start", date: startDate, isActive: focusedField == .start) {
                        focusedField = .start
                    }

                    if isRangeEnabled {
                        dateField(title: "End", date: endDate, isActive: focusedField == .end) {
                            focusedField = .end
                        }
                    }

                    DatePicker("", selection: activeDateBinding, in: activePickerBounds, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .id(focusedField)
                }

                if filterState.dateFilter != nil {
                    Button("Clear Filter") {
                        HapticsManager.shared.trigger(.lightImpact)
                        isRangeEnabled = true
                        startDate = bounds.lowerBound
                        endDate = bounds.upperBound
                        focusedField = .start
                        filterState.dateFilter = nil
                    }
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.accent)
                }
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .themedBackground()
        .onChange(of: startDate) { _, _ in updateFilter() }
        .onChange(of: endDate) { _, _ in updateFilter() }
        .onChange(of: isRangeEnabled) { _, _ in updateFilter() }
    }

    private func updateFilter() {
        filterState.dateFilter = resolvedFilter()
    }

    private var toggleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Date Range")
                    .font(.montserratMedium(size: 16))
                Spacer()
                Toggle("", isOn: $isRangeEnabled)
                    .labelsHidden()
                    .tint(.accent)
                    .onChange(of: isRangeEnabled) { _, enabled in
                        HapticsManager.shared.trigger(.selection)
                        if !enabled {
                            focusedField = .start
                            endDate = startDate
                        }
                    }
            }
            Text(isRangeEnabled ? "Filter between a start and end date." : "Filter workouts on or after the selected start date.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func dateField(title: String, date: Date, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticsManager.shared.trigger(.selection)
            action()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(.secondary)
                    Text(dateFormatter.string(from: date))
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : (effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.08)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.accentColor : (effectiveColorScheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.2)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func resolvedFilter() -> WorkoutDateFilter? {
        if isRangeEnabled {
            let start = min(startDate, endDate)
            let end = max(startDate, endDate)
            let matchesBounds = start == bounds.lowerBound && end == bounds.upperBound
            return matchesBounds ? nil : WorkoutDateFilter(start: start, end: end)
        } else {
            let normalizedStart = max(bounds.lowerBound, min(startDate, bounds.upperBound))
            return normalizedStart == bounds.lowerBound ? nil : WorkoutDateFilter(start: normalizedStart, end: nil)
        }
    }

    private var activeDateBinding: Binding<Date> {
        Binding {
            focusedField == .start ? startDate : endDate
        } set: { newValue in
            switch focusedField {
            case .start:
                startDate = max(bounds.lowerBound, min(newValue, bounds.upperBound))
                if endDate < startDate {
                    endDate = startDate
                }
            case .end:
                endDate = max(startDate, min(newValue, bounds.upperBound))
            }
        }
    }

    private var activePickerBounds: ClosedRange<Date> {
        switch focusedField {
        case .start:
            return bounds
        case .end:
            return startDate...bounds.upperBound
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }

    private enum DateField {
        case start, end
    }
}

private struct DurationFilterSheet: View {
    var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    let bounds: ClosedRange<Double>
    let effectiveColorScheme: ColorScheme

    @State private var minValue: Double = 0
    @State private var maxValue: Double = 0

    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Double>, effectiveColorScheme: ColorScheme) {
        self.filterState = filterState
        self.bounds = bounds
        self.effectiveColorScheme = effectiveColorScheme
        let initialRange = filterState.durationRange ?? bounds
        let clampedLower = max(bounds.lowerBound, min(initialRange.lowerBound, bounds.upperBound))
        let clampedUpper = max(clampedLower, min(initialRange.upperBound, bounds.upperBound))
        _minValue = State(initialValue: clampedLower)
        _maxValue = State(initialValue: clampedUpper)
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Duration")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Filter workouts by duration.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                HStack {
                    valueSummary(title: "Min", value: formattedDuration(minValue))
                    Spacer()
                    valueSummary(title: "Max", value: formattedDuration(maxValue))
                }

                WorkoutFilterRangeSlider(
                    lowerValue: $minValue,
                    upperValue: $maxValue,
                    bounds: bounds,
                    step: 60
                )
            }

            if filterState.durationRange != nil {
                Button("Clear Filter") {
                    HapticsManager.shared.trigger(.lightImpact)
                    minValue = bounds.lowerBound
                    maxValue = bounds.upperBound
                    filterState.durationRange = nil
                }
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.accent)
            }
        }
        .padding(20)
        .padding(.bottom, 12)
        .themedBackground()
        .onChange(of: minValue) { _, _ in updateFilter() }
        .onChange(of: maxValue) { _, _ in updateFilter() }
    }

    private func updateFilter() {
        let selectedRange = minValue...maxValue
        filterState.durationRange = selectedRange == bounds ? nil : selectedRange
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let interval = Int(seconds)
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func valueSummary(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.accent)
        }
    }
}

// MARK: - Sort Option Sheet

private struct SortOptionSheet: View {
    var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    let effectiveColorScheme: ColorScheme
    let preferredMetric: WorkoutMetric

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Sort By")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Choose how to order your workouts")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(WorkoutSortOption.allCases) { option in
                    Button {
                        HapticsManager.shared.trigger(.selection)
                        filterState.sortOption = option
                    } label: {
                        HStack {
                            Image(systemName: option.iconName)
                                .font(.system(size: 16))
                                .frame(width: 24)
                                .foregroundStyle(filterState.sortOption == option ? .accent : .secondary)
                            Text(option.displayName(for: preferredMetric))
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            Spacer()
                            if filterState.sortOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(filterState.sortOption == option
                                    ? Color.accent.opacity(0.15)
                                    : (effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.08)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .padding(.bottom, 12)
        .themedBackground()
    }
}

// MARK: - Range Slider

private struct WorkoutFilterRangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    let step: Double?

    private let handleSize: CGFloat = 28
    @State private var lastLowerStep: Int = -1
    @State private var lastUpperStep: Int = -1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackWidth = max(width - handleSize, 1)

            let lowerRatio = normalizedValue(lowerValue)
            let upperRatio = normalizedValue(upperValue)
            let lowerPosition = handleSize / 2 + CGFloat(lowerRatio) * trackWidth
            let upperPosition = handleSize / 2 + CGFloat(upperRatio) * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: trackWidth, height: 4)
                    .offset(x: handleSize / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(upperPosition - lowerPosition, 2), height: 4)
                    .offset(x: lowerPosition)

                sliderHandle(at: lowerPosition, width: width, isLowerHandle: true)
                sliderHandle(at: upperPosition, width: width, isLowerHandle: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: handleSize)
    }

    private func sliderHandle(at position: CGFloat, width: CGFloat, isLowerHandle: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .position(x: position, y: handleSize / 2)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateValue(for: value.location.x, width: width, isLowerHandle: isLowerHandle)
                    }
            )
            .accessibilityLabel(isLowerHandle ? "Minimum value" : "Maximum value")
            .accessibilityValue("\(Int(isLowerHandle ? lowerValue : upperValue))")
    }

    private func updateValue(for locationX: CGFloat, width: CGFloat, isLowerHandle: Bool) {
        let newValue = snappedValue(from: locationX, width: width)
        let effectiveStep = step ?? 1

        if isLowerHandle {
            let clampedValue = min(max(bounds.lowerBound, newValue), upperValue)
            let currentStep = Int(round((clampedValue - bounds.lowerBound) / effectiveStep))
            if currentStep != lastLowerStep {
                lastLowerStep = currentStep
                if clampedValue == bounds.lowerBound || clampedValue >= upperValue {
                    HapticsManager.shared.trigger(.mediumImpact)
                } else {
                    HapticsManager.shared.trigger(.selection)
                }
            }
            lowerValue = clampedValue
        } else {
            let clampedValue = max(min(bounds.upperBound, newValue), lowerValue)
            let currentStep = Int(round((clampedValue - bounds.lowerBound) / effectiveStep))
            if currentStep != lastUpperStep {
                lastUpperStep = currentStep
                if clampedValue == bounds.upperBound || clampedValue <= lowerValue {
                    HapticsManager.shared.trigger(.mediumImpact)
                } else {
                    HapticsManager.shared.trigger(.selection)
                }
            }
            upperValue = clampedValue
        }
    }

    private func snappedValue(from locationX: CGFloat, width: CGFloat) -> Double {
        let halfHandle = handleSize / 2
        let clampedX = min(max(locationX, halfHandle), width - halfHandle)
        let trackWidth = max(width - handleSize, 1)
        let progress = Double((clampedX - halfHandle) / trackWidth)
        let rawValue = bounds.lowerBound + progress * (bounds.upperBound - bounds.lowerBound)
        guard let step, step > 0 else { return rawValue }
        let steps = round((rawValue - bounds.lowerBound) / step)
        return bounds.lowerBound + steps * step
    }

    private func normalizedValue(_ value: Double) -> Double {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        return (clamped - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }
}
