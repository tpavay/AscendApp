//
//  RangeSlider.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/21/25.
//

import SwiftUI

struct RangeSlider: View {
    @Binding var lowValue: Double
    @Binding var highValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingChanged: (Bool) -> Void
    
    @State private var isDraggingLow = false
    @State private var isDraggingHigh = false
    @State private var sliderWidth: CGFloat = 0
    @State private var lastHapticLowStep: Int = 0
    @State private var lastHapticHighStep: Int = 0
    
    private let handleSize: CGFloat = 28
    private let trackHeight: CGFloat = 6
    
    init(
        lowValue: Binding<Double>,
        highValue: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0.1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._lowValue = lowValue
        self._highValue = highValue
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: trackHeight)
                
                // Active range track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.accentColor)
                    .frame(width: activeRangeWidth(totalWidth: geometry.size.width), height: trackHeight)
                    .offset(x: lowHandlePosition(totalWidth: geometry.size.width))
                
                // Low value handle
                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 3)
                    )
                    .offset(x: lowHandlePosition(totalWidth: geometry.size.width) - handleSize / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDraggingLow {
                                    isDraggingLow = true
                                    onEditingChanged(true)
                                }
                                updateLowValue(
                                    dragLocation: value.location.x,
                                    totalWidth: geometry.size.width
                                )
                            }
                            .onEnded { _ in
                                isDraggingLow = false
                                onEditingChanged(false)
                            }
                    )
                
                // High value handle
                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 3)
                    )
                    .offset(x: highHandlePosition(totalWidth: geometry.size.width) - handleSize / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDraggingHigh {
                                    isDraggingHigh = true
                                    onEditingChanged(true)
                                }
                                updateHighValue(
                                    dragLocation: value.location.x,
                                    totalWidth: geometry.size.width
                                )
                            }
                            .onEnded { _ in
                                isDraggingHigh = false
                                onEditingChanged(false)
                            }
                    )
            }
            .frame(height: handleSize)
            .onAppear {
                sliderWidth = geometry.size.width
            }
        }
        .frame(height: handleSize)
    }
    
    private func lowHandlePosition(totalWidth: CGFloat) -> CGFloat {
        let percentage = (lowValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return percentage * totalWidth
    }
    
    private func highHandlePosition(totalWidth: CGFloat) -> CGFloat {
        let percentage = (highValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return percentage * totalWidth
    }
    
    private func activeRangeWidth(totalWidth: CGFloat) -> CGFloat {
        return highHandlePosition(totalWidth: totalWidth) - lowHandlePosition(totalWidth: totalWidth)
    }
    
    private func updateLowValue(dragLocation: CGFloat, totalWidth: CGFloat) {
        let percentage = max(0, min(1, dragLocation / totalWidth))
        var newValue = range.lowerBound + percentage * (range.upperBound - range.lowerBound)
        
        // Round to step
        newValue = round(newValue / step) * step
        
        // Ensure low value doesn't exceed high value minus minimum gap
        let minimumGap = 0.5
        newValue = min(newValue, highValue - minimumGap)
        
        // Clamp to range
        newValue = max(range.lowerBound, min(range.upperBound, newValue))
        
        // Haptic feedback at step increments
        let currentStep = Int(round((newValue - range.lowerBound) / step))
        if currentStep != lastHapticLowStep {
            lastHapticLowStep = currentStep
            // Stronger haptic at bounds
            if newValue == range.lowerBound || newValue >= highValue - minimumGap {
                HapticsManager.shared.trigger(.mediumImpact)
            } else {
                HapticsManager.shared.trigger(.selection)
            }
        }
        
        lowValue = newValue
    }
    
    private func updateHighValue(dragLocation: CGFloat, totalWidth: CGFloat) {
        let percentage = max(0, min(1, dragLocation / totalWidth))
        var newValue = range.lowerBound + percentage * (range.upperBound - range.lowerBound)
        
        // Round to step
        newValue = round(newValue / step) * step
        
        // Ensure high value doesn't go below low value plus minimum gap
        let minimumGap = 0.5
        newValue = max(newValue, lowValue + minimumGap)
        
        // Clamp to range
        newValue = max(range.lowerBound, min(range.upperBound, newValue))
        
        // Haptic feedback at step increments
        let currentStep = Int(round((newValue - range.lowerBound) / step))
        if currentStep != lastHapticHighStep {
            lastHapticHighStep = currentStep
            // Stronger haptic at bounds
            if newValue == range.upperBound || newValue <= lowValue + minimumGap {
                HapticsManager.shared.trigger(.mediumImpact)
            } else {
                HapticsManager.shared.trigger(.selection)
            }
        }
        
        highValue = newValue
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var lowValue: Double = 2.0
        @State private var highValue: Double = 8.0
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Range: \(String(format: "%.1f", lowValue))s - \(String(format: "%.1f", highValue))s")
                    .font(.headline)
                
                RangeSlider(
                    lowValue: $lowValue,
                    highValue: $highValue,
                    in: 0...15,
                    step: 0.1
                )
                .padding(.horizontal, 20)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

