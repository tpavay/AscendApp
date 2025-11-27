//
//  WorkoutTrendBarChartView.swift
//  AscendApp
//
//  Created by ChatGPT on 5/26/24.
//

import SwiftUI
import Charts

struct WorkoutTrendBarChartView: View {
    let title: String
    let unitLabel: String
    let buckets: [WorkoutTrendBucket]
    let valueType: WorkoutTrendBucketValueType
    let bucketStyle: TrendBucketStyle
    let range: WorkoutTrendRange
    let colorScheme: ColorScheme
    
    @State private var selectedBucket: WorkoutTrendBucket?
    
    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = valueType == .perMinute ? 1 : 0
        formatter.minimumFractionDigits = 0
        return formatter
    }
    
    private var yScaleDomain: ClosedRange<Double> {
        let maxValue = buckets.map { valueForBucket($0) }.max() ?? 0
        let upper = max(1, maxValue * 1.1)
        return 0...upper
    }
    
    private var latestValueText: String? {
        guard let last = buckets.last else { return nil }
        let value = valueForBucket(last)
        return "\(formattedValue(value)) \(unitLabel)"
    }
    
    private var xAxisValues: [Date] {
        switch bucketStyle {
        case .month:
            return buckets.map { $0.startDate }
        case .week:
            let stride = max(1, buckets.count / 6)
            return buckets.enumerated().compactMap { index, bucket in
                index % stride == 0 ? bucket.startDate : nil
            }
        case .perWorkout:
            return []
        }
    }
    
    private var bucketWidth: CGFloat {
        switch bucketStyle {
        case .week: return 38
        case .month: return 46
        case .perWorkout: return 38
        }
    }
    
    private func valueForBucket(_ bucket: WorkoutTrendBucket) -> Double {
        switch valueType {
        case .total:
            return bucket.totalMetric
        case .perMinute:
            return bucket.metricPerMinute
        case .averageHeartRate:
            return bucket.averageHeartRate ?? 0
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    if let latestValueText = latestValueText {
                        Text("Latest: \(latestValueText)")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
                
                Spacer()
            }
            
            if let selectedBucket = selectedBucket {
                tooltip(for: selectedBucket)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("Date", bucket.startDate),
                            y: .value(title, valueForBucket(bucket)),
                            width: .fixed(bucketWidth - 8)
                        )
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(8)
                        .annotation(position: .overlay, alignment: .top) {
                            if bucket.id == selectedBucket?.id {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .offset(y: -4)
                            }
                        }
                    }
                    
                    if let selected = selectedBucket {
                        RuleMark(x: .value("Selected Date", selected.startDate))
                            .foregroundStyle(Color.accentColor.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisValues) { value in
                        AxisGridLine()
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                Text(bucketLabel(for: dateValue, compact: true))
                                    .font(.montserratRegular(size: 10))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        AxisValueLabel()
                            .font(.montserratRegular(size: 11))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
                .chartYScale(domain: yScaleDomain)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectNearestBucket(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .onTapGesture { location in
                                selectNearestBucket(at: location, proxy: proxy, geometry: geometry)
                            }
                    }
                }
                .frame(width: max(320, CGFloat(buckets.count) * bucketWidth))
                .frame(height: 200)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
    
    private func bucketLabel(for date: Date, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        switch bucketStyle {
        case .week:
            formatter.dateFormat = compact ? "MMM d" : "MMMM d, yyyy"
        case .month:
            formatter.dateFormat = compact ? "MMM" : "MMMM"
            if compact && range == .lastYear {
                let month = formatter.string(from: date)
                return String(month.prefix(1))
            }
        case .perWorkout:
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
    
    private func selectNearestBucket(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry.frame(in: .local)
        guard plotFrame.contains(location) else { return }
        
        var nearest: WorkoutTrendBucket?
        var nearestDistance: CGFloat = .infinity
        
        for bucket in buckets {
            guard let xPosition = proxy.position(forX: bucket.startDate),
                  let yPosition = proxy.position(forY: valueForBucket(bucket)) else { continue }
            let pointLocation = CGPoint(x: xPosition, y: yPosition)
            let distance = hypot(location.x - pointLocation.x, location.y - pointLocation.y)
            
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = bucket
            }
        }
        
        if let bucket = nearest, nearestDistance < 80 {
            if selectedBucket?.id != bucket.id {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedBucket = bucket
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
    
    private func tooltip(for bucket: WorkoutTrendBucket) -> some View {
        let fullLabel = bucketLabel(for: bucket.startDate, compact: false)
        let workoutLabel = "\(bucket.workoutCount) workout\(bucket.workoutCount == 1 ? "" : "s")"
        let valueLabel = "\(formattedValue(valueForBucket(bucket))) \(unitLabel)"
        
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fullLabel)
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(workoutLabel)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            
            Spacer()
            
            Text(valueLabel)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
