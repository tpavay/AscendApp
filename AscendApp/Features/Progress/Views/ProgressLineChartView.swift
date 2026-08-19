//
//  ProgressLineChartView.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import Charts
import SwiftUI

struct ProgressLineChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let valueText: String
    let dateText: String
}

enum ProgressLineChartXAxisStyle {
    case monthDay
    case monthYear
}

struct ProgressLineChartView: View {
    let title: String
    let points: [ProgressLineChartPoint]
    let colorScheme: ColorScheme
    let accentColor: Color
    let height: CGFloat
    let xAxisStyle: ProgressLineChartXAxisStyle
    let emptyText: String
    let yAxisLabel: (Double) -> String

    @State private var selectedPointID: ProgressLineChartPoint.ID?

    init(
        title: String,
        points: [ProgressLineChartPoint],
        colorScheme: ColorScheme,
        accentColor: Color = .accentColor,
        height: CGFloat = 300,
        xAxisStyle: ProgressLineChartXAxisStyle = .monthYear,
        emptyText: String = "No progression data yet.",
        yAxisLabel: @escaping (Double) -> String
    ) {
        self.title = title
        self.points = points
        self.colorScheme = colorScheme
        self.accentColor = accentColor
        self.height = height
        self.xAxisStyle = xAxisStyle
        self.emptyText = emptyText
        self.yAxisLabel = yAxisLabel
    }

    private var selectedPoint: ProgressLineChartPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    var body: some View {
        Group {
            if points.isEmpty {
                emptyChartState
            } else {
                chart
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        Chart {
            if points.count > 1 {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", yScaleDomain.lowerBound),
                        yEnd: .value(title, point.value)
                    )
                    .foregroundStyle(chartAreaGradient)
                    .interpolationMethod(.monotone)
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(chartLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if points.count == 1, let point = points.first {
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .symbol {
                    chartPointSymbol(isSelected: selectedPointID == point.id)
                }
            } else if let selectedPoint {
                PointMark(
                    x: .value("Selected Date", selectedPoint.date),
                    y: .value(title, selectedPoint.value)
                )
                .symbol {
                    chartPointSymbol(isSelected: true)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(for: date))
                    }
                }
                .font(.montserratRegular(size: 10))
                .foregroundStyle(foregroundSubtle)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.75, dash: [2, 6]))
                    .foregroundStyle(axisGrid)
                AxisValueLabel {
                    if let rawValue = value.as(Double.self) {
                        Text(yAxisLabel(rawValue))
                    }
                }
                .font(.montserratRegular(size: 10))
                .foregroundStyle(foregroundSubtle)
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXScale(domain: xScaleDomain)
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    selectionOverlay(proxy: proxy, geometry: geometry)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelectedPoint(
                                        at: value.location,
                                        proxy: proxy,
                                        geometry: geometry
                                    )
                                }
                        )
                }
            }
        }
        .sentryMasked()
    }

    private func chartPointSymbol(isSelected: Bool) -> some View {
        Circle()
            .fill(accentColor)
            .frame(width: isSelected ? 11 : 10, height: isSelected ? 11 : 10)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.92 : 0.82), lineWidth: isSelected ? 2.1 : 1.8)
            )
            .shadow(color: accentColor.opacity(isSelected ? 0.72 : 0.5), radius: isSelected ? 9 : 7, x: 0, y: 0)
    }

    @ViewBuilder
    private func selectionOverlay(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let selectedPoint,
           let rawX = proxy.position(forX: selectedPoint.date),
           let rawY = proxy.position(forY: selectedPoint.value),
           let plotFrameAnchor = proxy.plotFrame {
            let plotFrame = geometry[plotFrameAnchor]
            let selectedX = plotFrame.origin.x + rawX
            let selectedY = plotFrame.origin.y + rawY
            let calloutWidth: CGFloat = 132
            let calloutHeight: CGFloat = 54
            let clampedX = min(
                max(selectedX - calloutWidth / 2, 0),
                max(geometry.size.width - calloutWidth, 0)
            )
            let clampedY = max(selectedY - calloutHeight - 12, 4)

            Rectangle()
                .fill(selectionRule)
                .frame(width: 1, height: plotFrame.height)
                .position(x: selectedX, y: plotFrame.midY)

            chartCallout(for: selectedPoint)
                .frame(width: calloutWidth, height: calloutHeight, alignment: .leading)
                .offset(x: clampedX, y: clampedY)
        }
    }

    private func updateSelectedPoint(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        let xPosition = location.x - plotFrame.origin.x

        guard xPosition >= 0,
              xPosition <= plotFrame.width,
              let date = proxy.value(atX: xPosition, as: Date.self),
              let nearestPoint = nearestPoint(to: date)
        else {
            return
        }

        selectedPointID = nearestPoint.id
    }

    private func nearestPoint(to date: Date) -> ProgressLineChartPoint? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func chartCallout(for point: ProgressLineChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.valueText)
                .font(.montserratBold(size: 15))
                .foregroundStyle(accentColor)

            Text(point.dateText)
                .font(.montserratMedium(size: 10))
                .foregroundStyle(foregroundSubtle)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(calloutFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStroke.opacity(1.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 14, x: 0, y: 7)
    }

    private var emptyChartState: some View {
        Text(emptyText)
            .font(.montserratRegular(size: 13))
            .foregroundStyle(foregroundSubtle)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var yScaleDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let padding = max(abs(maxValue) * 0.15, 1)
            return max(minValue - padding, 0)...(maxValue + padding)
        }

        let padding = max((maxValue - minValue) * 0.18, maxValue * 0.04, 1)
        return max(minValue - padding, 0)...(maxValue + padding)
    }

    private var xScaleDomain: ClosedRange<Date> {
        let dates = points.map(\.date)
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            let now = Date()
            return now...now
        }

        let interval = max(maxDate.timeIntervalSince(minDate), 1)
        let padding = max(interval * 0.07, 86_400)
        return minDate.addingTimeInterval(-padding)...maxDate.addingTimeInterval(padding)
    }

    private func xAxisLabel(for date: Date) -> String {
        switch xAxisStyle {
        case .monthDay:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .monthYear:
            return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    private var foregroundSubtle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.52)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }

    private var axisGrid: Color {
        colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    private var calloutFill: Color {
        colorScheme == .dark ? Color(red: 0.055, green: 0.06, blue: 0.045).opacity(0.96) : .white
    }

    private var chartLine: Color {
        accentColor.opacity(colorScheme == .dark ? 0.98 : 0.98)
    }

    private var chartAreaGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(colorScheme == .dark ? 0.42 : 0.24),
                accentColor.opacity(colorScheme == .dark ? 0.18 : 0.1),
                accentColor.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectionRule: Color {
        colorScheme == .dark ? accentColor.opacity(0.18) : .black.opacity(0.18)
    }
}
