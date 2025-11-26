//
//  BestEffortsProgressView.swift
//  AscendApp
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI
import Charts

struct BestEffortsProgressView: View {
    let workouts: [Workout]
    let initialMetric: BestEffort.MetricType?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var selectedMetric: BestEffort.MetricType = .mostSteps
    @State private var selectedDataPoint: ProgressionDataPoint?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var availableMetrics: [BestEffort.MetricType] {
        BestEffortsBuilder.availableMetricTypes(from: workouts)
    }
    
    private var progressionData: [ProgressionDataPoint] {
        BestEffortsBuilder.progressionData(for: selectedMetric, from: workouts)
    }
    
    /// Computed time range description for the chart
    private var timeRangeDescription: String? {
        guard let first = progressionData.first,
              let last = progressionData.last,
              first.id != last.id else { return nil }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: first.date, to: last.date)
        
        if let months = components.month, months > 0 {
            if months == 1 {
                return "Over 1 month"
            } else {
                return "Over \(months) months"
            }
        } else if let days = components.day, days > 0 {
            if days == 1 {
                return "Over 1 day"
            } else {
                return "Over \(days) days"
            }
        }
        return nil
    }
    
    init(workouts: [Workout], initialMetric: BestEffort.MetricType? = nil) {
        self.workouts = workouts
        self.initialMetric = initialMetric
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if availableMetrics.isEmpty {
                    emptyState
                } else {
                    metricPicker
                    
                    if progressionData.count < 2 {
                        insufficientDataState
                    } else {
                        chartSection
                        legendSection
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let initial = initialMetric, availableMetrics.contains(initial) {
                selectedMetric = initial
            } else if let first = availableMetrics.first {
                selectedMetric = first
            }
        }
    }
    
    // MARK: - Metric Picker
    
    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableMetrics) { metric in
                    metricButton(for: metric)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func metricButton(for metric: BestEffort.MetricType) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMetric = metric
                selectedDataPoint = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: metric.iconName)
                    .font(.system(size: 14, weight: .medium))
                
                Text(metric.displayName)
                    .font(.montserratMedium(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selectedMetric == metric
                          ? Color.accentColor
                          : (effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            )
            .foregroundStyle(selectedMetric == metric
                             ? .white
                             : (effectiveColorScheme == .dark ? .white : .black))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedMetric.displayName)
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    if let latest = progressionData.last {
                        Text("Current: \(formattedValue(latest.value)) \(selectedMetric.unitLabel)")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                }
                
                Spacer()
                
                // Improvement percentage
                if progressionData.count >= 2,
                   let first = progressionData.first,
                   let last = progressionData.last,
                   first.value > 0 {
                    let improvement = ((last.value - first.value) / first.value) * 100
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                        Text("+\(Int(improvement))%")
                            .font(.montserratBold(size: 16))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
                }
            }
            
            // Selected point tooltip
            if let selected = selectedDataPoint {
                selectedPointTooltip(for: selected)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Chart with gesture overlay
            Chart {
                ForEach(progressionData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        selectedDataPoint?.id == point.id
                        ? Color.accentColor
                        : (point.id == progressionData.last?.id
                           ? Color.accentColor
                           : (effectiveColorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.6)))
                    )
                    .symbolSize(selectedDataPoint?.id == point.id ? 140 : (point.id == progressionData.last?.id ? 100 : 60))
                }
                
                // Highlight selected point with rule
                if let selected = selectedDataPoint {
                    RuleMark(x: .value("Selected", selected.date))
                        .foregroundStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: strideMonths)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    AxisValueLabel()
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectNearestPoint(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    // Keep selection visible after drag ends
                                }
                        )
                        .onTapGesture { location in
                            selectNearestPoint(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
            .frame(height: 220)
            .padding(.top, 8)
            
            // Time range indicator
            if let timeRange = timeRangeDescription {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                    Text(timeRange)
                        .font(.montserratMedium(size: 12))
                }
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    /// Determine appropriate stride for X axis based on data range
    private var strideMonths: Int {
        guard let first = progressionData.first,
              let last = progressionData.last else { return 1 }
        
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: first.date, to: last.date).month ?? 0
        
        if months <= 6 {
            return 1
        } else if months <= 12 {
            return 2
        } else if months <= 24 {
            return 3
        } else {
            return 6
        }
    }
    
    private func selectedPointTooltip(for point: ProgressionDataPoint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedFullDate(point.date))
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text(point.workout.name)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(formattedValue(point.value)) \(selectedMetric.unitLabel)")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.accent)
            
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedDataPoint = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func selectNearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry.frame(in: .local)
        guard plotFrame.contains(location) else { return }
        
        // Find the nearest data point
        var nearestPoint: ProgressionDataPoint?
        var nearestDistance: CGFloat = .infinity
        
        for point in progressionData {
            guard let xPosition = proxy.position(forX: point.date),
                  let yPosition = proxy.position(forY: point.value) else { continue }
            
            let pointLocation = CGPoint(x: xPosition, y: yPosition)
            let distance = hypot(location.x - pointLocation.x, location.y - pointLocation.y)
            
            if distance < nearestDistance {
                nearestDistance = distance
                nearestPoint = point
            }
        }
        
        // Only select if within reasonable distance (50 points)
        if nearestDistance < 50, let point = nearestPoint {
            if selectedDataPoint?.id != point.id {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedDataPoint = point
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
    
    // MARK: - Legend / Record List
    
    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record History")
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            VStack(spacing: 8) {
                ForEach(progressionData.reversed()) { point in
                    NavigationLink(destination: WorkoutDetailView(workout: point.workout)) {
                        recordRow(for: point)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func recordRow(for point: ProgressionDataPoint) -> some View {
        HStack(spacing: 12) {
            // Record indicator
            Circle()
                .fill(point.id == progressionData.last?.id ? Color.accentColor : (effectiveColorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.4)))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(point.workout.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                Text(formattedDate(point.date))
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            
            Spacer()
            
            Text("\(formattedValue(point.value)) \(selectedMetric.unitLabel)")
                .font(.montserratBold(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        )
    }
    
    // MARK: - Empty States
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
            
            Text("No Data Yet")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("Start logging workouts to track your personal record progression over time.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
        )
    }
    
    private var insufficientDataState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
            
            Text("Not Enough Records")
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("You need at least 2 personal records for \(selectedMetric.displayName) to see your progression chart.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
        )
    }
    
    // MARK: - Formatting
    
    private func formattedValue(_ value: Double) -> String {
        switch selectedMetric {
        case .longestWorkout, .highestAverageMETs:
            return String(format: "%.1f", value)
        case .highestStepsPerMinute:
            return String(format: "%.0f", value)
        default:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    let sampleWorkouts = [
        Workout(
            name: "First Climb",
            date: Calendar.current.date(byAdding: .month, value: -3, to: Date())!,
            duration: 20 * 60,
            steps: 1500,
            floors: 20,
            stepsPerFloor: 16,
            avgHeartRate: 120,
            caloriesBurned: 200
        ),
        Workout(
            name: "Getting Better",
            date: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
            duration: 30 * 60,
            steps: 2500,
            floors: 30,
            stepsPerFloor: 16,
            avgHeartRate: 130,
            caloriesBurned: 350
        ),
        Workout(
            name: "New Record",
            date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
            duration: 40 * 60,
            steps: 3800,
            floors: 42,
            stepsPerFloor: 16,
            avgHeartRate: 140,
            caloriesBurned: 480
        ),
        Workout(
            name: "Personal Best",
            date: Date(),
            duration: 50 * 60,
            steps: 5200,
            floors: 55,
            stepsPerFloor: 16,
            avgHeartRate: 145,
            caloriesBurned: 620
        )
    ]
    
    NavigationStack {
        BestEffortsProgressView(workouts: sampleWorkouts)
    }
}

#Preview("Dark Mode") {
    let sampleWorkouts = [
        Workout(
            name: "First Climb",
            date: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
            duration: 25 * 60,
            steps: 2000,
            floors: 25,
            stepsPerFloor: 16
        ),
        Workout(
            name: "Personal Best",
            date: Date(),
            duration: 45 * 60,
            steps: 4500,
            floors: 48,
            stepsPerFloor: 16
        )
    ]
    
    NavigationStack {
        BestEffortsProgressView(workouts: sampleWorkouts, initialMetric: .mostSteps)
    }
    .preferredColorScheme(.dark)
}

