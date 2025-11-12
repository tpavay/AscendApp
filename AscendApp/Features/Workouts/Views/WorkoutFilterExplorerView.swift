//
//  WorkoutFilterExplorerView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutFilterExplorerView: View {
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
                return [.height(CGFloat(520))]
            case .steps, .duration:
                return [.height(CGFloat(360))]
            case .dates:
                return [.fraction(0.92)]
            }
        }

        var dragIndicatorVisibility: Visibility {
            .visible
        }
    }
    
    enum FilterChip: String, CaseIterable, Identifiable {
        case source
        case steps
        case dates
        case duration
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .source: return "Workout Source"
            case .steps: return "Steps"
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
    
    let workouts: [Workout]
    @ObservedObject var filterState: WorkoutListFilterState
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var activeSheet: FilterSheet?
    @FocusState private var isSearchFocused: Bool
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var filteredWorkouts: [Workout] {
        filterState.applyFilters(to: workouts)
    }
    
    private var stepsBounds: ClosedRange<Double> {
        let maxSteps = workouts.compactMap { $0.steps ?? $0.primaryMetricValue }.max() ?? 0
        let upper = maxSteps > 0 ? Double(maxSteps) : 1000
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
            VStack(spacing: 12) {
                searchField
                filterChipStrip
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredWorkouts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.accent)
                            
                            Text("No workouts match your filters")
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                    } else {
                        Text("Showing \(filteredWorkouts.count) workout\(filteredWorkouts.count == 1 ? "" : "s")")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(filteredWorkouts) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Search Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if filterState.hasActiveFilters {
                    Button("Reset All") {
                        withAnimation(.easeInOut) {
                            filterState.resetAll()
                        }
                    }
                }
            }
        }
        .themedBackground()
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .source:
                WorkoutSourceFilterSheet(filterState: filterState)
                    .filterSheetPresentation(for: sheet)
            case .steps:
                StepsFilterSheet(
                    filterState: filterState,
                    bounds: stepsBounds,
                    formatter: Self.stepsFormatter
                )
                .filterSheetPresentation(for: sheet)
            case .dates:
                DatesFilterSheet(filterState: filterState, bounds: dateBounds)
                    .filterSheetPresentation(for: sheet)
            case .duration:
                DurationFilterSheet(filterState: filterState, bounds: durationBounds)
                    .filterSheetPresentation(for: sheet)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if filterState.searchText.isEmpty {
                    isSearchFocused = true
                }
            }
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.accent)
            
            TextField("Search By Keyword", text: $filterState.searchText)
                .font(.montserratMedium(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
            
            if !filterState.searchText.isEmpty {
                Button {
                    filterState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(effectiveColorScheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var filterChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FilterChip.allCases) { chip in
                    Button {
                        activeSheet = chip.associatedSheet
                    } label: {
                        FilterChipView(
                            title: chip.label,
                            isActive: isActive(chip),
                            colorScheme: effectiveColorScheme
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
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
}

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

private struct WorkoutSourceFilterSheet: View {
    @ObservedObject var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var tempSelection: Set<WorkoutSource> = []
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(filterState: WorkoutListFilterState) {
        self._filterState = ObservedObject(wrappedValue: filterState)
        _tempSelection = State(initialValue: filterState.selectedSources)
    }
    
    var body: some View {
        VStack(spacing: 24) {
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
                                Image(systemName: tempSelection.contains(source) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(tempSelection.contains(source) ? .accent : .gray)
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
            }
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                Button("Reset") {
                    tempSelection.removeAll()
                }
                .buttonStyle(SecondaryFilterButtonStyle(colorScheme: effectiveColorScheme))

                Button("Apply") {
                    withAnimation(.easeInOut) {
                        filterState.selectedSources = tempSelection
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryFilterButtonStyle())
            }
            .padding(.bottom, 24)
        }
        .padding(20)
        .themedBackground()
    }
    
    private func toggleSelection(for source: WorkoutSource) {
        if tempSelection.contains(source) {
            tempSelection.remove(source)
        } else {
            tempSelection.insert(source)
        }
    }
}

private struct StepsFilterSheet: View {
    @ObservedObject var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    let bounds: ClosedRange<Double>
    let formatter: NumberFormatter
    
    @State private var minValue: Double = 0
    @State private var maxValue: Double = 0
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Double>, formatter: NumberFormatter) {
        self._filterState = ObservedObject(wrappedValue: filterState)
        self.bounds = bounds
        self.formatter = formatter
        let initialRange = filterState.stepsRange ?? bounds
        let clampedLower = max(bounds.lowerBound, min(initialRange.lowerBound, bounds.upperBound))
        let clampedUpper = max(clampedLower, min(initialRange.upperBound, bounds.upperBound))
        _minValue = State(initialValue: clampedLower)
        _maxValue = State(initialValue: clampedUpper)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Steps Range")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Text("Filter workouts by the recorded steps.")
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
            
            HStack(spacing: 12) {
                Button("Reset") {
                    minValue = bounds.lowerBound
                    maxValue = bounds.upperBound
                }
                .buttonStyle(SecondaryFilterButtonStyle(colorScheme: effectiveColorScheme))
                
                Button("Apply") {
                    withAnimation(.easeInOut) {
                        let selectedRange = minValue...maxValue
                        filterState.stepsRange = selectedRange == bounds ? nil : selectedRange
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryFilterButtonStyle())
            }
        }
        .padding(20)
        .themedBackground()
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
    @ObservedObject var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    let bounds: ClosedRange<Date>
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isRangeEnabled: Bool = true
    @State private var focusedField: DateField = .start
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Date>) {
        self._filterState = ObservedObject(wrappedValue: filterState)
        self.bounds = bounds
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
            
            HStack(spacing: 12) {
                Button("Reset") {
                    isRangeEnabled = true
                    startDate = bounds.lowerBound
                    endDate = bounds.upperBound
                    focusedField = .start
                }
                .buttonStyle(SecondaryFilterButtonStyle(colorScheme: effectiveColorScheme))
                
                Button("Apply") {
                    let newFilter = resolvedFilter()
                    withAnimation(.easeInOut) {
                        filterState.dateFilter = newFilter
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryFilterButtonStyle())
            }
        }
        .padding(20)
        .themedBackground()
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
                    .onChange(of: isRangeEnabled) { enabled in
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
        Button(action: action) {
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
    @ObservedObject var filterState: WorkoutListFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    let bounds: ClosedRange<Double>
    @State private var minValue: Double = 0
    @State private var maxValue: Double = 0
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Double>) {
        self._filterState = ObservedObject(wrappedValue: filterState)
        self.bounds = bounds
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
                Text("Limit workouts by the time spent in each session.")
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
            
            HStack(spacing: 12) {
                Button("Reset") {
                    minValue = bounds.lowerBound
                    maxValue = bounds.upperBound
                }
                .buttonStyle(SecondaryFilterButtonStyle(colorScheme: effectiveColorScheme))
                
                Button("Apply") {
                    withAnimation(.easeInOut) {
                        let selectedRange = minValue...maxValue
                        filterState.durationRange = selectedRange == bounds ? nil : selectedRange
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryFilterButtonStyle())
            }
        }
        .padding(20)
        .themedBackground()
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

private struct WorkoutFilterRangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    let step: Double?
    
    private let handleSize: CGFloat = 28
    
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
        if isLowerHandle {
            lowerValue = min(max(bounds.lowerBound, newValue), upperValue)
        } else {
            upperValue = max(min(bounds.upperBound, newValue), lowerValue)
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

private struct PrimaryFilterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.montserratSemiBold(size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.accent.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
    }
}

private struct SecondaryFilterButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.montserratSemiBold(size: 16))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.5), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.clear)
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

private extension View {
    func filterSheetPresentation(for sheet: WorkoutFilterExplorerView.FilterSheet) -> some View {
        self
            .presentationDetents(sheet.presentationDetents)
            .presentationDragIndicator(sheet.dragIndicatorVisibility)
    }
}
