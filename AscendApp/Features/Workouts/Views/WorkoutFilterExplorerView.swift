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
                    .presentationDetents([.fraction(0.55)])
                    .presentationDragIndicator(.visible)
            case .steps:
                StepsFilterSheet(
                    filterState: filterState,
                    bounds: stepsBounds,
                    formatter: Self.stepsFormatter
                )
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.visible)
            case .dates:
                DatesFilterSheet(filterState: filterState, bounds: dateBounds)
                    .presentationDetents([.fraction(0.6)])
                    .presentationDragIndicator(.visible)
            case .duration:
                DurationFilterSheet(filterState: filterState, bounds: durationBounds)
                    .presentationDetents([.fraction(0.6)])
                    .presentationDragIndicator(.visible)
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
            return filterState.dateRange != nil
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
            SheetHandle()
            
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
            SheetHandle()
            
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
                
                VStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { minValue },
                            set: { newValue in
                                minValue = min(newValue, maxValue)
                            }
                        ),
                        in: bounds.lowerBound...maxValue,
                        step: sliderStep(for: bounds.upperBound)
                    )
                    .tint(.accent)
                    
                    Slider(
                        value: Binding(
                            get: { maxValue },
                            set: { newValue in
                                maxValue = max(newValue, minValue)
                            }
                        ),
                        in: minValue...bounds.upperBound,
                        step: sliderStep(for: bounds.upperBound)
                    )
                    .tint(.accent)
                }
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
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    init(filterState: WorkoutListFilterState, bounds: ClosedRange<Date>) {
        self._filterState = ObservedObject(wrappedValue: filterState)
        self.bounds = bounds
        let initialRange = filterState.dateRange ?? bounds
        let clampedStart = max(bounds.lowerBound, min(initialRange.lowerBound, bounds.upperBound))
        let clampedEnd = max(clampedStart, min(initialRange.upperBound, bounds.upperBound))
        _startDate = State(initialValue: clampedStart)
        _endDate = State(initialValue: clampedEnd)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            SheetHandle()
            
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
                DatePicker("Start Date", selection: $startDate, in: bounds, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                
                DatePicker("End Date", selection: $endDate, in: bounds, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
            }
            
            HStack(spacing: 12) {
                Button("Reset") {
                    startDate = bounds.lowerBound
                    endDate = bounds.upperBound
                }
                .buttonStyle(SecondaryFilterButtonStyle(colorScheme: effectiveColorScheme))
                
                Button("Apply") {
                    let normalizedRange = normalizedDateRange()
                    withAnimation(.easeInOut) {
                        filterState.dateRange = normalizedRange == bounds ? nil : normalizedRange
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryFilterButtonStyle())
            }
        }
        .padding(20)
        .themedBackground()
    }
    
    private func normalizedDateRange() -> ClosedRange<Date> {
        let start = min(startDate, endDate)
        let end = max(startDate, endDate)
        return start...end
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
            SheetHandle()
            
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
                
                VStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { minValue },
                            set: { newValue in
                                minValue = min(newValue, maxValue)
                            }
                        ),
                        in: bounds.lowerBound...maxValue,
                        step: 60
                    )
                    .tint(.accent)
                    
                    Slider(
                        value: Binding(
                            get: { maxValue },
                            set: { newValue in
                                maxValue = max(newValue, minValue)
                            }
                        ),
                        in: minValue...bounds.upperBound,
                        step: 60
                    )
                    .tint(.accent)
                }
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

private struct SheetHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 5)
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
